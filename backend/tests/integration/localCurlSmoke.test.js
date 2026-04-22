import http from "node:http";
import test from "node:test";
import assert from "node:assert/strict";
import { once } from "node:events";

import { createApp } from "../../src/app.js";

const ENV_KEYS = [
  "PORT",
  "NOVAI_API_KEY",
  "AI_PROVIDER",
  "AI_MODEL",
  "AI_BASE_URL",
  "AI_API_KIND",
  "AI_TIMEOUT_MS",
  "AI_MAX_RETRIES",
  "AI_CIRCUIT_BREAKER_ENABLED",
  "DASHSCOPE_API_KEY",
  "DASHSCOPE_BASE_URL",
  "MODEL_NAME"
];

function createExplainPayload(overrides = {}) {
  return {
    client_request_id: "local-check-1",
    document_id: "doc-1",
    sentence_id: "s-1",
    segment_id: "seg-1",
    sentence_text_hash: "abc",
    anchor_label: "P1-S1",
    title: "Demo",
    sentence: "This is a sentence.",
    context: "This is a sentence.",
    ...overrides
  };
}

function createPassagePayload(overrides = {}) {
  return {
    client_request_id: "local-check-2",
    document_id: "doc-1",
    content_hash: "content-abc",
    title: "Demo",
    paragraphs: [
      {
        segment_id: "seg-1",
        index: 0,
        anchor_label: "P1",
        text: "This is paragraph one.",
        source_kind: "passage_body",
        hygiene_score: 0.9
      }
    ],
    ...overrides
  };
}

async function withEnv(patch, callback) {
  const snapshot = new Map(ENV_KEYS.map((key) => [key, process.env[key]]));

  for (const key of ENV_KEYS) {
    const value = patch[key];
    if (value === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = value;
    }
  }

  try {
    return await callback();
  } finally {
    for (const [key, value] of snapshot) {
      if (value === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
  }
}

async function withListeningServer(server, callback) {
  server.listen(0, "127.0.0.1");
  await once(server, "listening");

  try {
    const address = server.address();
    return await callback(address.port);
  } finally {
    server.close();
    await once(server, "close");
  }
}

function buildAnthropicResponse(jsonObject) {
  return {
    id: "msg_test",
    type: "message",
    model: "claude-opus-4-6",
    content: [
      {
        type: "text",
        text: JSON.stringify(jsonObject)
      }
    ],
    usage: {
      input_tokens: 10,
      output_tokens: 20
    }
  };
}

function createFakeUpstream(sequence) {
  const steps = [...sequence];

  return http.createServer(async (req, res) => {
    let body = "";
    req.on("data", (chunk) => {
      body += chunk;
    });
    await once(req, "end");

    if (req.url !== "/v1/messages") {
      res.writeHead(404, { "content-type": "application/json" });
      res.end(JSON.stringify({ error: { message: "not found" } }));
      return;
    }

    const step = steps.length > 1 ? steps.shift() : steps[0];
    if (!step) {
      res.writeHead(500, { "content-type": "application/json" });
      res.end(JSON.stringify({ error: { message: "missing scenario" } }));
      return;
    }

    if (step.status >= 400) {
      res.writeHead(step.status, { "content-type": "application/json" });
      res.end(JSON.stringify(step.body));
      return;
    }

    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify(buildAnthropicResponse(step.body)));
  });
}

async function withSmokeAppServer(envPatch, callback) {
  return withEnv(envPatch, async () => {
    const server = http.createServer(createApp());
    return withListeningServer(server, callback);
  });
}

test("local curl smoke: health + explain-sentence + analyze-passage are locally available with fake upstream", async () => {
  const upstream = createFakeUpstream([
    {
      status: 200,
      body: {
        original_sentence: "This is a sentence.",
        sentence_function: "核心判断句：这句承担最基本的判断。",
        core_skeleton: {
          subject: "This",
          predicate: "is",
          complement_or_object: "a sentence"
        },
        chunk_layers: [],
        grammar_focus: [],
        faithful_translation: "这是一个句子。",
        teaching_interpretation: "先抓主干，再看上下文。",
        natural_chinese_meaning: "先抓主干，再看上下文。",
        contextual_vocabulary: [],
        misreading_traps: [],
        exam_paraphrase_routes: [],
        simpler_rewrite: "This sentence is simple.",
        simpler_rewrite_translation: "这句把结构说得更直接。",
        mini_check: "",
        hierarchy_rebuild: [],
        syntactic_variation: "A simple sentence is shown."
      }
    },
    {
      status: 200,
      body: {
        passage_overview: {
          article_theme: "文章只做本地 smoke 验证。",
          author_core_question: "是否能稳定返回结构化段落地图。",
          progression_path: "先给出段落，再验证地图产物。",
          likely_question_types: ["结构题"],
          logic_pitfalls: ["把段落背景误判成结论"]
        },
        paragraph_cards: [
          {
            segment_id: "seg-1",
            paragraph_index: 0,
            anchor_label: "P1",
            theme: "第一段承担基本说明。",
            argument_role: "background",
            core_sentence_id: "seg-1::s1",
            relation_to_previous: "首段建立背景。",
            exam_value: "适合作为结构题入口。",
            teaching_focuses: ["先认清段落作用。"],
            student_blind_spot: "容易忽略结构功能。",
            provenance: {
              source_segment_id: "seg-1",
              source_sentence_id: "seg-1::s1",
              source_kind: "passage_body",
              generated_from: "ai_passage_analysis",
              hygiene_score: 0.9,
              consistency_score: 0.9
            }
          }
        ],
        key_sentence_ids: ["seg-1::s1"],
        question_links: []
      }
    }
  ]);

  await withListeningServer(upstream, async (upstreamPort) => {
    await withSmokeAppServer({
      NOVAI_API_KEY: "test-token",
      AI_PROVIDER: "claude",
      AI_MODEL: "claude-opus-4-6",
      AI_BASE_URL: `http://127.0.0.1:${upstreamPort}`,
      AI_API_KIND: "anthropic-messages",
      AI_TIMEOUT_MS: "30000",
      AI_MAX_RETRIES: "3",
      AI_CIRCUIT_BREAKER_ENABLED: "true",
      DASHSCOPE_API_KEY: "",
      DASHSCOPE_BASE_URL: "",
      MODEL_NAME: ""
    }, async (appPort) => {
      const healthResponse = await fetch(`http://127.0.0.1:${appPort}/health`);
      assert.equal(healthResponse.status, 200);
      const healthBody = await healthResponse.json();
      assert.equal(healthBody.ok, true);
      assert.deepEqual(healthBody.ai_gateway, {
        configured: true,
        provider: "claude",
        model: "claude-opus-4-6",
        api_kind: "anthropic-messages",
        timeout_ms: 30000,
        max_retries: 3,
        circuit_breaker_enabled: true,
        circuit_state: "closed"
      });

      const explainResponse = await fetch(`http://127.0.0.1:${appPort}/ai/explain-sentence`, {
        method: "POST",
        headers: {
          "content-type": "application/json"
        },
        body: JSON.stringify(createExplainPayload({
          client_request_id: "local-check-503",
          sentence_id: "s-503",
          sentence_text_hash: "abc-503"
        }))
      });
      assert.equal(explainResponse.status, 200);
      const explainBody = await explainResponse.json();
      assert.equal(typeof explainBody.request_id, "string");
      assert.equal(explainBody.meta.used_fallback, false);

      const passageResponse = await fetch(`http://127.0.0.1:${appPort}/ai/analyze-passage`, {
        method: "POST",
        headers: {
          "content-type": "application/json"
        },
        body: JSON.stringify(createPassagePayload())
      });
      assert.equal(passageResponse.status, 200);
      const passageBody = await passageResponse.json();
      assert.equal(typeof passageBody.request_id, "string");
      assert.equal(passageBody.meta.used_fallback, false);
    });
  });
});

test("local curl smoke: MODEL_CONFIG_MISSING is structured and keeps health available", async () => {
  await withSmokeAppServer({
    NOVAI_API_KEY: "",
    AI_PROVIDER: "claude",
    AI_MODEL: "claude-opus-4-6",
    AI_BASE_URL: "http://127.0.0.1:3199",
    AI_API_KIND: "anthropic-messages",
    AI_TIMEOUT_MS: "30000",
    AI_MAX_RETRIES: "3",
    AI_CIRCUIT_BREAKER_ENABLED: "true",
    DASHSCOPE_API_KEY: "",
    DASHSCOPE_BASE_URL: "",
    MODEL_NAME: ""
  }, async (appPort) => {
    const healthResponse = await fetch(`http://127.0.0.1:${appPort}/health`);
    assert.equal(healthResponse.status, 200);
    const healthBody = await healthResponse.json();
    assert.equal(healthBody.ai_gateway.configured, false);
    assert.equal(healthBody.ai_gateway.circuit_state, "closed");

    const explainResponse = await fetch(`http://127.0.0.1:${appPort}/ai/explain-sentence`, {
      method: "POST",
      headers: {
        "content-type": "application/json"
      },
      body: JSON.stringify(createExplainPayload())
    });

    assert.equal(explainResponse.status, 503);
    const explainBody = await explainResponse.json();
    assert.equal(explainBody.success, false);
    assert.equal(explainBody.error_code, "MODEL_CONFIG_MISSING");
    assert.equal(explainBody.fallback_available, true);
    assert.equal(typeof explainBody.request_id, "string");
  });
});

test("local curl smoke: fake 503 triggers local fallback and health reflects open circuit", async () => {
  const upstream = createFakeUpstream([
    {
      status: 503,
      body: {
        success: false,
        error_code: "UPSTREAM_503",
        message: "busy",
        retryable: true,
        fallback_available: true
      }
    },
    {
      status: 503,
      body: {
        success: false,
        error_code: "UPSTREAM_503",
        message: "busy",
        retryable: true,
        fallback_available: true
      }
    },
    {
      status: 503,
      body: {
        success: false,
        error_code: "UPSTREAM_503",
        message: "busy",
        retryable: true,
        fallback_available: true
      }
    }
  ]);

  await withListeningServer(upstream, async (upstreamPort) => {
    await withSmokeAppServer({
      NOVAI_API_KEY: "test-token",
      AI_PROVIDER: "claude",
      AI_MODEL: "claude-opus-4-6",
      AI_BASE_URL: `http://127.0.0.1:${upstreamPort}`,
      AI_API_KIND: "anthropic-messages",
      AI_TIMEOUT_MS: "30000",
      AI_MAX_RETRIES: "3",
      AI_CIRCUIT_BREAKER_ENABLED: "true",
      DASHSCOPE_API_KEY: "",
      DASHSCOPE_BASE_URL: "",
      MODEL_NAME: ""
    }, async (appPort) => {
      const explainResponse = await fetch(`http://127.0.0.1:${appPort}/ai/explain-sentence`, {
        method: "POST",
        headers: {
          "content-type": "application/json"
        },
        body: JSON.stringify(createExplainPayload())
      });

      assert.equal(explainResponse.status, 200);
      const explainBody = await explainResponse.json();
      assert.equal(typeof explainBody.request_id, "string");
      assert.equal(explainBody.meta.used_fallback, true);
      assert.equal(explainBody.meta.circuit_state, "open");

      const healthResponse = await fetch(`http://127.0.0.1:${appPort}/health`);
      assert.equal(healthResponse.status, 200);
      const healthBody = await healthResponse.json();
      assert.equal(healthBody.ai_gateway.circuit_state, "open");
    });
  });
});
