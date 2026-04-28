import {
  AI_PREWARM_CONCURRENCY,
  AI_PREWARM_MAX_SENTENCES_PER_DOCUMENT,
  getServerConfig
} from "../config/env.js";
import { getAIPersistentCacheStore } from "./AIPersistentCacheStore.js";
import { DocumentExplainPrewarmQueue } from "./DocumentExplainPrewarmQueue.js";
import { explainSentence } from "./explainSentenceService.js";

let queueSingleton = null;
let queueOverrideForTests = null;

async function explainPrewarmSentence(row) {
  const payload = row?.payload || {};
  return explainSentence({
    title: payload.title || "",
    sentence: payload.text || "",
    context: payload.context || "",
    paragraph_theme: payload.paragraph_theme || "",
    paragraph_role: payload.paragraph_role || "",
    question_prompt: payload.question_prompt || "",
    sentence_id: row?.sentence_id || payload.sentence_id || "",
    sentence_text_hash: row?.sentence_text_hash || payload.sentence_text_hash || "",
    anchor_label: payload.anchor_label || "",
    segment_id: payload.segment_id || "",
    document_id: row?.document_id || "",
    requestID: row?.request_id || undefined
  });
}

export function getDocumentExplainPrewarmQueue() {
  if (queueOverrideForTests) {
    return queueOverrideForTests;
  }

  if (!queueSingleton) {
    const { modelName } = getServerConfig();
    queueSingleton = new DocumentExplainPrewarmQueue({
      store: getAIPersistentCacheStore(),
      modelName,
      explainSentence: explainPrewarmSentence,
      concurrency: AI_PREWARM_CONCURRENCY,
      maxSentencesPerDocument: AI_PREWARM_MAX_SENTENCES_PER_DOCUMENT,
      autoStart: true
    });
  }

  return queueSingleton;
}

export function setDocumentExplainPrewarmQueueForTests(queue) {
  queueOverrideForTests = queue;
}

export function resetDocumentExplainPrewarmQueueForTests() {
  queueOverrideForTests = null;
  queueSingleton = null;
}
