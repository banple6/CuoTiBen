import { randomUUID } from "node:crypto";

import {
  AI_PREWARM_CONCURRENCY,
  AI_PREWARM_MAX_SENTENCES_PER_DOCUMENT
} from "../config/env.js";
import {
  SENTENCE_EXPLAIN_PROMPT_VERSION,
  buildSentenceExplainCacheKey,
  getAIPersistentCacheStore
} from "./AIPersistentCacheStore.js";

export function rankPrewarmSentence(sentence, index = 0) {
  if (sentence?.is_current_page === true) return index;
  if (index < 20) return 100_000 + index;
  if (sentence?.is_key_sentence === true) return 200_000 + index;
  return 300_000 + index;
}

function isRemoteAIResult(result) {
  if (!result || result.used_fallback === true) return false;
  const source = result.current_result_source || result.currentResultSource;
  if (source) {
    return source === "remoteAI";
  }
  return result.used_cache === true
    || (result.used_fallback === false && typeof result.original_sentence === "string" && result.original_sentence.trim());
}

function requestIDFrom(result) {
  return result?.request_id || result?.requestID || null;
}

function invalidResultError(result) {
  return {
    code: result?.used_fallback === true ? "PREWARM_USED_FALLBACK" : "PREWARM_INVALID_RESULT",
    requestID: requestIDFrom(result)
  };
}

function parsePayload(row) {
  if (row?.payload && typeof row.payload === "object") {
    return row.payload;
  }
  if (!row?.payload_json) {
    return {};
  }
  try {
    return JSON.parse(row.payload_json);
  } catch {
    return {};
  }
}

export function buildPrewarmExplainSentencePayload(row) {
  const payload = parsePayload(row);
  const sentenceID = row?.sentence_id || payload.sentence_id || "";
  const sentenceTextHash = row?.sentence_text_hash || payload.sentence_text_hash || "";
  const documentID = row?.document_id || payload.document_id || "";
  const stableAnchorLabel = payload.anchor_label || sentenceID || "";
  const stableSegmentID = payload.segment_id || sentenceID || "";

  return {
    identity: {
      client_request_id: `prewarm:${row?.job_id || ""}:${sentenceID}`,
      document_id: documentID,
      sentence_id: sentenceID,
      segment_id: stableSegmentID,
      sentence_text_hash: sentenceTextHash,
      anchor_label: stableAnchorLabel
    },
    requestID: `prewarm:${row?.job_id || ""}:${sentenceID}`,
    client_request_id: `prewarm:${row?.job_id || ""}:${sentenceID}`,
    document_id: documentID,
    sentence_id: sentenceID,
    sentence_text_hash: sentenceTextHash,
    segment_id: stableSegmentID,
    anchor_label: stableAnchorLabel,
    title: payload.title || payload.document_title || "",
    sentence: payload.text || payload.sentence || "",
    context: payload.context || payload.text || "",
    paragraph_theme: payload.paragraph_theme || "",
    paragraph_role: payload.paragraph_role || "passageBody",
    question_prompt: payload.question_prompt || ""
  };
}

export class DocumentExplainPrewarmQueue {
  constructor({
    store = getAIPersistentCacheStore(),
    modelName,
    explainSentence,
    concurrency = AI_PREWARM_CONCURRENCY,
    maxSentencesPerDocument = AI_PREWARM_MAX_SENTENCES_PER_DOCUMENT,
    autoStart = true
  } = {}) {
    this.store = store;
    this.modelName = modelName;
    this.explainSentence = explainSentence;
    this.concurrency = Math.max(1, Number(concurrency) || 1);
    this.maxSentencesPerDocument = Math.max(1, Number(maxSentencesPerDocument) || 1);
    this.autoStart = autoStart;
    this.activeCount = 0;
    this.idleResolvers = [];

    this.recoverAbandonedWork();
    if (this.autoStart) {
      this.pump();
    }
  }

  recoverAbandonedWork() {
    this.store.requeueAbandonedProcessingSentences();
    this.store.recalculateRunningPrewarmJobs();
  }

  enqueueDocument({ document_id, title = "", sentences = [] }) {
    const selected = sentences
      .map((sentence, index) => ({
        sentence,
        priority: rankPrewarmSentence(sentence, index)
      }))
      .sort((lhs, rhs) => lhs.priority - rhs.priority)
      .slice(0, this.maxSentencesPerDocument);

    const job_id = `prewarm_${randomUUID()}`;
    this.store.createPrewarmJob({
      job_id,
      document_id,
      title,
      status: "queued",
      total_count: selected.length,
      queued_count: selected.length,
      processing_count: 0,
      ready_count: 0,
      failed_count: 0
    });

    for (const { sentence, priority } of selected) {
      const identity = {
        document_id,
        sentence_id: sentence.sentence_id,
        sentence_text_hash: sentence.sentence_text_hash,
        prompt_version: SENTENCE_EXPLAIN_PROMPT_VERSION,
        model_name: this.modelName
      };
      this.store.createSentencePrewarmJob({
        job_id,
        document_id,
        sentence_id: sentence.sentence_id,
        sentence_text_hash: sentence.sentence_text_hash,
        cache_key: buildSentenceExplainCacheKey(identity),
        model_name: this.modelName,
        priority,
        status: "queued",
        payload: sentence
      });
    }

    this.store.recalculatePrewarmJob(job_id);
    if (this.autoStart) {
      this.pump();
    }
    return this.getJobStatus(job_id);
  }

  getJobStatus(jobID) {
    return this.store.getPrewarmJobStatus(jobID);
  }

  getLatestJobForDocument(documentID) {
    return this.store.getLatestPrewarmJobByDocumentID(documentID);
  }

  pump() {
    while (this.activeCount < this.concurrency) {
      const row = this.store.claimNextQueuedSentence();
      if (!row) break;

      this.store.markSentencePrewarmProcessing(row);
      this.activeCount += 1;
      Promise.resolve(this.processSentence(row)).finally(() => {
        this.activeCount -= 1;
        this.pump();
        this.notifyIdleIfNeeded();
      });
    }

    this.notifyIdleIfNeeded();
  }

  async processSentence(row) {
    try {
      const result = await this.explainSentence(buildPrewarmExplainSentencePayload(row));
      if (!isRemoteAIResult(result)) {
        this.store.markSentencePrewarmFailed(row, invalidResultError(result));
        return;
      }
      this.store.markSentencePrewarmReady(row, {
        ...result,
        current_result_source: result?.current_result_source || result?.currentResultSource || "remoteAI"
      });
    } catch (error) {
      this.store.markSentencePrewarmFailed(row, error);
    }
  }

  async drainForTests() {
    this.pump();
    while (this.activeCount > 0 || this.store.hasQueuedSentences()) {
      await new Promise((resolve) => this.idleResolvers.push(resolve));
    }
  }

  notifyIdleIfNeeded() {
    if (this.activeCount > 0 || this.store.hasQueuedSentences()) return;
    const resolvers = this.idleResolvers.splice(0);
    for (const resolve of resolvers) {
      resolve();
    }
  }
}
