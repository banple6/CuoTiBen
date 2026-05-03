import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { once } from "node:events";
import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

import { createApp } from "../src/app.js";
import { resetAIPersistentCacheStoreForTests } from "../src/services/AIPersistentCacheStore.js";
import {
  resetDocumentExplainPrewarmQueueForTests,
  setDocumentExplainPrewarmQueueForTests
} from "../src/services/DocumentExplainPrewarmQueueRegistry.js";

function passageSentence(index, overrides = {}) {
  return {
    kind: "passageSentence",
    sentence_id: `sen_${index}`,
    sentence_text_hash: `hash_${index}`,
    text: `Passage sentence ${index}.`,
    context: `Context ${index}.`,
    anchor_label: `第1页 第${index}句`,
    segment_id: "seg_1",
    page_index: 0,
    paragraph_role: "passageBody",
    paragraph_theme: "theme",
    question_prompt: "",
    is_current_page: index === 1,
    is_key_sentence: false,
    is_passage_sentence: true,
    ...overrides
  };
}

function blockedSentence(kind, index) {
  return {
    kind,
    sentence_id: `${kind}_${index}`,
    sentence_text_hash: `${kind}_hash_${index}`,
    text: `${kind} should not prewarm.`,
    paragraph_role: kind,
    is_passage_sentence: false
  };
}

class FakePrewarmQueue {
  constructor() {
    this.jobs = new Map();
    this.jobsByDocument = new Map();
    this.lastPayload = null;
    this.counter = 0;
  }

  enqueueDocument(payload) {
    this.lastPayload = payload;
    this.counter += 1;
    const job = {
      job_id: `job-${this.counter}`,
      document_id: payload.document_id,
      title: payload.title,
      status: "queued",
      total_count: payload.sentences.length,
      ready_count: 0,
      failed_count: 0,
      processing_count: 0,
      queued_count: payload.sentences.length
    };
    this.jobs.set(job.job_id, job);
    this.jobsByDocument.set(job.document_id, job);
    return job;
  }

  getJobStatus(jobID) {
    return this.jobs.get(jobID) || null;
  }

  getLatestJobForDocument(documentID) {
    return this.jobsByDocument.get(documentID) || null;
  }
}

async function withServer(queue, fn) {
  setDocumentExplainPrewarmQueueForTests(queue);
  const server = createServer(createApp());
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const { port } = server.address();
  const baseURL = `http://127.0.0.1:${port}`;

  try {
    await fn(baseURL);
  } finally {
    resetDocumentExplainPrewarmQueueForTests();
    await new Promise((resolve, reject) => {
      server.close((error) => {
        if (error) reject(error);
        else resolve();
      });
    });
  }
}

async function requestJSON(baseURL, path, options = {}) {
  const response = await fetch(`${baseURL}${path}`, {
    ...options,
    headers: {
      "content-type": "application/json",
      ...(options.headers || {})
    }
  });
  const body = await response.json();
  return { response, body };
}

async function withFakeAnthropicUpstream(fn) {
  const requests = [];
  const upstream = createServer(async (request, response) => {
    const chunks = [];
    for await (const chunk of request) {
      chunks.push(chunk);
    }
    requests.push({
      method: request.method,
      url: request.url,
      body: JSON.parse(Buffer.concat(chunks).toString("utf8"))
    });
    response.writeHead(200, { "content-type": "application/json" });
    response.end(JSON.stringify({
      id: "msg_prewarm_fake",
      type: "message",
      role: "assistant",
      model: "claude-opus-4-6",
      content: [
        {
          type: "text",
          text: JSON.stringify({
            original_sentence: "Passage sentence 1.",
            evidence_type: "core_claim",
            sentence_function: "核心判断句：这句给出正文信息。",
            core_skeleton: {
              subject: "Passage sentence",
              predicate: "is",
              complement_or_object: "eligible"
            },
            chunk_layers: [
              {
                text: "Passage sentence 1.",
                role: "核心信息",
                attaches_to: "主句",
                gloss: "这是正文句。"
              }
            ],
            grammar_focus: [
              {
                phenomenon: "simple sentence",
                function: "简单句承载核心信息。",
                why_it_matters: "先识别主干。",
                title_zh: "简单句",
                explanation_zh: "主干清楚的正文句。",
                why_it_matters_zh: "避免把正文句当标题。",
                example_en: "Passage sentence 1."
              }
            ],
            faithful_translation: "正文句 1。",
            teaching_interpretation: "这是一个可预热的正文句。",
            natural_chinese_meaning: "这是一个可预热的正文句。",
            contextual_vocabulary: [],
            misreading_traps: [],
            exam_paraphrase_routes: [],
            simpler_rewrite: "Sentence 1 is eligible.",
            simpler_rewrite_translation: "句子 1 可用。",
            mini_check: "这是不是正文句？",
            hierarchy_rebuild: [],
            syntactic_variation: "The sentence is eligible."
          })
        }
      ]
    }));
  });
  upstream.listen(0, "127.0.0.1");
  await once(upstream, "listening");
  const { port } = upstream.address();

  try {
    await fn(`http://127.0.0.1:${port}`, requests);
  } finally {
    await new Promise((resolve, reject) => {
      upstream.close((error) => {
        if (error) reject(error);
        else resolve();
      });
    });
  }
}

test("POST /ai/prewarm-document creates a prewarm job", async () => {
  const queue = new FakePrewarmQueue();
  await withServer(queue, async (baseURL) => {
    const { response, body } = await requestJSON(baseURL, "/ai/prewarm-document", {
      method: "POST",
      body: JSON.stringify({
        document_id: "doc-1",
        title: "Demo",
        client_request_id: "client-1",
        sentences: [passageSentence(1), passageSentence(2)]
      })
    });

    assert.equal(response.status, 200);
    assert.equal(body.success, true);
    assert.equal(body.request_id, "client-1");
    assert.equal(body.used_cache, false);
    assert.equal(body.used_fallback, false);
    assert.equal(body.data.job_id, "job-1");
    assert.equal(body.data.document_id, "doc-1");
    assert.equal(body.data.total_count, 2);
    assert.equal(body.data.queued_count, 2);
  });
});

test("POST /ai/prewarm-document filters non-passage sentence kinds", async () => {
  const queue = new FakePrewarmQueue();
  await withServer(queue, async (baseURL) => {
    const { response, body } = await requestJSON(baseURL, "/ai/prewarm-document", {
      method: "POST",
      body: JSON.stringify({
        document_id: "doc-filter",
        title: "Filter Demo",
        sentences: [
          passageSentence(1),
          blockedSentence("heading", 1),
          blockedSentence("question", 1),
          blockedSentence("vocabulary", 1)
        ]
      })
    });

    assert.equal(response.status, 200);
    assert.equal(body.success, true);
    assert.equal(body.data.total_count, 1);
    assert.equal(queue.lastPayload.sentences.length, 1);
    assert.equal(queue.lastPayload.sentences[0].sentence_id, "sen_1");
  });
});

test("POST /ai/prewarm-document rejects requests with no eligible passage sentences", async () => {
  const queue = new FakePrewarmQueue();
  await withServer(queue, async (baseURL) => {
    const { response, body } = await requestJSON(baseURL, "/ai/prewarm-document", {
      method: "POST",
      body: JSON.stringify({
        document_id: "doc-empty",
        sentences: [
          blockedSentence("heading", 1),
          blockedSentence("question", 1),
          blockedSentence("vocabulary", 1)
        ]
      })
    });

    assert.equal(response.status, 400);
    assert.equal(body.success, false);
    assert.equal(body.error_code, "INVALID_PREWARM_DOCUMENT_REQUEST");
    assert.ok(body.request_id);
  });
});

test("POST /ai/prewarm-document rejects missing document_id", async () => {
  const queue = new FakePrewarmQueue();
  await withServer(queue, async (baseURL) => {
    const { response, body } = await requestJSON(baseURL, "/ai/prewarm-document", {
      method: "POST",
      body: JSON.stringify({
        sentences: [passageSentence(1)]
      })
    });

    assert.equal(response.status, 400);
    assert.equal(body.success, false);
    assert.equal(body.error_code, "INVALID_PREWARM_DOCUMENT_REQUEST");
    assert.ok(body.request_id);
  });
});

test("GET /ai/prewarm-document/:job_id returns job status", async () => {
  const queue = new FakePrewarmQueue();
  await withServer(queue, async (baseURL) => {
    const created = await requestJSON(baseURL, "/ai/prewarm-document", {
      method: "POST",
      body: JSON.stringify({
        document_id: "doc-status",
        sentences: [passageSentence(1)]
      })
    });
    const jobID = created.body.data.job_id;

    const { response, body } = await requestJSON(baseURL, `/ai/prewarm-document/${jobID}`, {
      method: "GET"
    });

    assert.equal(response.status, 200);
    assert.equal(body.success, true);
    assert.ok(body.request_id);
    assert.equal(body.data.job_id, jobID);
    assert.equal(body.data.document_id, "doc-status");
  });
});

test("GET /ai/prewarm-document/latest returns latest job by document_id", async () => {
  const queue = new FakePrewarmQueue();
  await withServer(queue, async (baseURL) => {
    await requestJSON(baseURL, "/ai/prewarm-document", {
      method: "POST",
      body: JSON.stringify({
        document_id: "doc-latest",
        sentences: [passageSentence(1)]
      })
    });
    const second = await requestJSON(baseURL, "/ai/prewarm-document", {
      method: "POST",
      body: JSON.stringify({
        document_id: "doc-latest",
        sentences: [passageSentence(2)]
      })
    });

    const { response, body } = await requestJSON(
      baseURL,
      "/ai/prewarm-document/latest?document_id=doc-latest",
      { method: "GET" }
    );

    assert.equal(response.status, 200);
    assert.equal(body.success, true);
    assert.ok(body.request_id);
    assert.equal(body.data.job_id, second.body.data.job_id);
  });
});

test("GET /ai/prewarm-document/latest rejects missing document_id", async () => {
  const queue = new FakePrewarmQueue();
  await withServer(queue, async (baseURL) => {
    const { response, body } = await requestJSON(baseURL, "/ai/prewarm-document/latest", {
      method: "GET"
    });

    assert.equal(response.status, 400);
    assert.equal(body.success, false);
    assert.equal(body.error_code, "MISSING_DOCUMENT_ID");
    assert.ok(body.request_id);
    assert.equal(body.retryable, false);
    assert.equal(body.fallback_available, false);
  });
});

test("GET /ai/prewarm-document/latest returns 404 when no job exists", async () => {
  const queue = new FakePrewarmQueue();
  await withServer(queue, async (baseURL) => {
    const { response, body } = await requestJSON(
      baseURL,
      "/ai/prewarm-document/latest?document_id=missing-doc",
      { method: "GET" }
    );

    assert.equal(response.status, 404);
    assert.equal(body.success, false);
    assert.equal(body.error_code, "PREWARM_JOB_NOT_FOUND");
    assert.ok(body.request_id);
    assert.equal(body.retryable, false);
    assert.equal(body.fallback_available, false);
  });
});

test("POST /ai/prewarm-document can prewarm through fake anthropic upstream and later explain from persistent cache", async () => withFakeAnthropicUpstream(async (upstreamURL, upstreamRequests) => {
  const upstreamKeyEnv = "NOVAI" + "_API_KEY";
  const originalEnv = {
    MODEL_NAME: process.env.MODEL_NAME,
    AI_MODEL: process.env.AI_MODEL,
    AI_API_KIND: process.env.AI_API_KIND,
    AI_BASE_URL: process.env.AI_BASE_URL,
    [upstreamKeyEnv]: process.env[upstreamKeyEnv],
    DASHSCOPE_API_KEY: process.env.DASHSCOPE_API_KEY,
    DASHSCOPE_BASE_URL: process.env.DASHSCOPE_BASE_URL,
    AI_PREWARM_CONCURRENCY: process.env.AI_PREWARM_CONCURRENCY
  };
  const dir = mkdtempSync(join(tmpdir(), "cuotiben-prewarm-route-cache-"));
  process.env.MODEL_NAME = "claude-opus-4-6";
  process.env.AI_MODEL = "claude-opus-4-6";
  process.env.AI_API_KIND = "anthropic-messages";
  process.env.AI_BASE_URL = upstreamURL;
  process.env[upstreamKeyEnv] = "test-key";
  process.env.AI_PREWARM_CONCURRENCY = "1";
  delete process.env.DASHSCOPE_API_KEY;
  delete process.env.DASHSCOPE_BASE_URL;
  resetAIPersistentCacheStoreForTests({ dbPath: join(dir, "cache.sqlite3") });
  resetDocumentExplainPrewarmQueueForTests();
  const server = createServer(createApp());
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const { port } = server.address();
  const baseURL = `http://127.0.0.1:${port}`;

  try {
    const created = await requestJSON(baseURL, "/ai/prewarm-document", {
      method: "POST",
      body: JSON.stringify({
        document_id: "doc-real-queue",
        title: "Real Queue Demo",
        client_request_id: "real-queue-create",
        sentences: [passageSentence(1)]
      })
    });

    assert.equal(created.response.status, 200);
    const jobID = created.body.data.job_id;
    let latest;
    for (let attempt = 0; attempt < 20; attempt += 1) {
      await new Promise((resolve) => setTimeout(resolve, 50));
      latest = await requestJSON(baseURL, "/ai/prewarm-document/latest?document_id=doc-real-queue", {
        method: "GET"
      });
      if (latest.body.data?.status === "completed" || latest.body.data?.status === "completed_with_errors" || latest.body.data?.status === "failed") {
        break;
      }
    }

    assert.equal(latest.response.status, 200);
    assert.equal(latest.body.data.job_id, jobID);
    assert.equal(latest.body.data.status, "completed");
    assert.equal(latest.body.data.ready_count, 1);
    const upstreamCallsAfterPrewarm = upstreamRequests.length;
    assert.ok(upstreamCallsAfterPrewarm >= 1);

    const cached = await requestJSON(baseURL, "/ai/explain-sentence", {
      method: "POST",
      body: JSON.stringify({
        client_request_id: "real-queue-cache-hit",
        document_id: "doc-real-queue",
        sentence_id: "sen_1",
        segment_id: "seg_1",
        sentence_text_hash: "hash_1",
        anchor_label: "第1页 第1句",
        title: "Real Queue Demo",
        sentence: "Passage sentence 1.",
        context: "Context 1."
      })
    });

    assert.equal(cached.response.status, 200);
    assert.equal(cached.body.success, true);
    assert.equal(cached.body.used_cache, true);
    assert.equal(cached.body.data.used_cache, true);
    assert.equal(upstreamRequests.length, upstreamCallsAfterPrewarm);
  } finally {
    await new Promise((resolve, reject) => {
      server.close((error) => {
        if (error) reject(error);
        else resolve();
      });
    });
    resetDocumentExplainPrewarmQueueForTests();
    resetAIPersistentCacheStoreForTests();
    rmSync(dir, { recursive: true, force: true });
    for (const [key, value] of Object.entries(originalEnv)) {
      if (value === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
  }
}));
