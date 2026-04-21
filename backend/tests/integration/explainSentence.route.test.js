import http from "node:http";
import test from "node:test";
import assert from "node:assert/strict";
import { once } from "node:events";

import { createApp } from "../../src/app.js";

const ENV_KEYS = [
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

function createPayload(overrides = {}) {
  return {
    client_request_id: "client-req-route-1",
    document_id: "document-1",
    sentence_id: "sentence-1",
    segment_id: "segment-1",
    sentence_text_hash: "hash-1",
    anchor_label: "S1",
    title: "Lesson Title",
    sentence: "After the storm, local leaders began to consider whether emergency plans needed revision.",
    context: "The author is explaining how the community responded after the storm.",
    paragraph_theme: "灾后应对评估",
    paragraph_role: "support",
    question_prompt: "Why did the leaders reconsider the emergency plans?",
    ...overrides
  };
}

async function withEnv(patch, callback) {
  const snapshot = new Map(ENV_KEYS.map((key) => [key, process.env[key]]));

  for (const key of ENV_KEYS) {
    if (patch[key] === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = patch[key];
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

async function withServer(server, callback) {
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

function buildOpenAIResponse(jsonObject) {
  return {
    id: "chatcmpl_test",
    object: "chat.completion",
    created: 1,
    model: "claude-opus-4-6",
    choices: [
      {
        index: 0,
        message: {
          role: "assistant",
          content: JSON.stringify(jsonObject)
        },
        finish_reason: "stop"
      }
    ]
  };
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

function createUpstreamServer(sequence) {
  const steps = [...sequence];
  const receivedRequests = [];

  const server = http.createServer(async (req, res) => {
    let body = "";
    req.on("data", (chunk) => {
      body += chunk;
    });
    await once(req, "end");

    if (req.url === "/v1/messages" || req.url === "/chat/completions" || req.url === "/v1/chat/completions") {
      receivedRequests.push({
        method: req.method,
        url: req.url,
        body
      });

      const step = steps.length > 1 ? steps.shift() : steps[0];
      if (!step) {
        res.writeHead(500, { "content-type": "application/json" });
        res.end(JSON.stringify({ error: { message: "missing scenario" } }));
        return;
      }

      if (step.type === "timeout") {
        return;
      }

      const responseBody = req.url === "/v1/messages"
        ? buildAnthropicResponse(step.body)
        : buildOpenAIResponse(step.body);

      res.writeHead(step.status ?? 200, { "content-type": "application/json" });
      res.end(JSON.stringify(step.status && step.status >= 400 ? step.body : responseBody));
      return;
    }

    res.writeHead(404, { "content-type": "application/json" });
    res.end(JSON.stringify({ error: { message: "not found" } }));
  });

  return {
    server,
    receivedRequests
  };
}

function assertPublicMeta(meta) {
  assert.equal(typeof meta.provider, "string");
  assert.equal(typeof meta.model, "string");
  assert.equal(typeof meta.retry_count, "number");
  assert.equal(typeof meta.used_cache, "boolean");
  assert.equal(typeof meta.used_fallback, "boolean");
  assert.equal(typeof meta.circuit_state, "string");
}

test("POST /ai/explain-sentence success path returns request_id, data, and public meta", async () => {
  const upstream = createUpstreamServer([
    {
      status: 200,
      body: {
        original_sentence: "After the storm, local leaders began to consider whether emergency plans needed revision.",
        sentence_function: "核心判断句：作者真正要成立的判断在这里。",
        core_skeleton: {
          subject: "local leaders",
          predicate: "began to consider",
          complement_or_object: "whether emergency plans needed revision"
        },
        chunk_layers: [
          {
            text: "After the storm",
            role: "前置框架",
            attaches_to: "核心信息",
            gloss: "先交代时间背景。"
          }
        ],
        grammar_focus: [
          {
            title_zh: "时间状语从句",
            explanation_zh: "这是句首的时间背景层。",
            why_it_matters_zh: "如果挂错，背景信息会被误读成核心判断。",
            example_en: "After the storm"
          }
        ],
        faithful_translation: "风暴过后，地方领导开始考虑应急方案是否需要修订。",
        teaching_interpretation: "先抓主句主干，再把前面的时间背景补回去。",
        misreading_traps: ["不要把时间背景误读成主干。"],
        exam_paraphrase_routes: ["题目可能把时间背景偷换成作者的核心判断。"],
        simpler_rewrite: "Local leaders considered whether the emergency plans needed revision after the storm.",
        simpler_rewrite_translation: "这句保留原意，只把时间背景后置。",
        mini_check: "这句真正的主干判断是什么？"
      }
    }
  ]);

  await withServer(upstream.server, async (upstreamPort) => {
    await withEnv({
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
    }, async () => {
      const app = createApp();
      await withServer(http.createServer(app), async (appPort) => {
        const response = await fetch(`http://127.0.0.1:${appPort}/ai/explain-sentence`, {
          method: "POST",
          headers: {
            "content-type": "application/json"
          },
          body: JSON.stringify(createPayload())
        });

        assert.equal(response.status, 200);
        const body = await response.json();

        assert.equal(body.success, true);
        assert.equal(typeof body.request_id, "string");
        assert.equal(typeof body.data, "object");
        assert.equal(typeof body.meta, "object");
        assertPublicMeta(body.meta);
      });
    });
  });
});

test("POST /ai/explain-sentence returns INVALID_REQUEST and never calls upstream when identity is missing", async () => {
  const upstream = createUpstreamServer([
    {
      status: 200,
      body: {
        original_sentence: "unused"
      }
    }
  ]);

  await withServer(upstream.server, async (upstreamPort) => {
    await withEnv({
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
    }, async () => {
      const app = createApp();
      await withServer(http.createServer(app), async (appPort) => {
        const payload = createPayload();
        delete payload.sentence_id;

        const response = await fetch(`http://127.0.0.1:${appPort}/ai/explain-sentence`, {
          method: "POST",
          headers: {
            "content-type": "application/json"
          },
          body: JSON.stringify(payload)
        });

        const body = await response.json();
        assert.equal(response.status, 400);
        assert.equal(body.success, false);
        assert.equal(body.error_code, "INVALID_REQUEST");
        assert.equal(upstream.receivedRequests.length, 0);
      });
    });
  });
});

test("POST /ai/explain-sentence fallback path returns public meta when upstream is 503", async () => {
  const upstream = createUpstreamServer([
    {
      status: 503,
      body: {
        error: {
          message: "busy"
        }
      }
    },
    {
      status: 503,
      body: {
        error: {
          message: "busy"
        }
      }
    },
    {
      status: 503,
      body: {
        error: {
          message: "busy"
        }
      }
    }
  ]);

  await withServer(upstream.server, async (upstreamPort) => {
    await withEnv({
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
    }, async () => {
      const app = createApp();
      await withServer(http.createServer(app), async (appPort) => {
        const response = await fetch(`http://127.0.0.1:${appPort}/ai/explain-sentence`, {
          method: "POST",
          headers: {
            "content-type": "application/json"
          },
          body: JSON.stringify(createPayload({
            client_request_id: "client-req-route-3",
            sentence_id: "sentence-3",
            sentence_text_hash: "hash-3"
          }))
        });

        const body = await response.json();
        assert.equal(response.status, 200);
        assert.equal(body.success, true);
        assertPublicMeta(body.meta);
        assert.equal(body.meta.used_fallback, true);
      });
    });
  });
});

test("POST /ai/explain-sentence repair path returns public meta after a contract-invalid first response", async () => {
  const upstream = createUpstreamServer([
    {
      status: 200,
      body: {
        original_sentence: "After the storm, local leaders began to consider whether emergency plans needed revision.",
        faithful_translation: "风暴过后，地方领导开始考虑应急方案是否需要修订。"
      }
    },
    {
      status: 200,
      body: {
        original_sentence: "After the storm, local leaders began to consider whether emergency plans needed revision.",
        sentence_function: "核心判断句：作者真正要成立的判断在这里。",
        core_skeleton: {
          subject: "local leaders",
          predicate: "began to consider",
          complement_or_object: "whether emergency plans needed revision"
        },
        chunk_layers: [
          {
            text: "After the storm",
            role: "前置框架",
            attaches_to: "核心信息",
            gloss: "先交代时间背景。"
          }
        ],
        grammar_focus: [
          {
            title_zh: "时间状语从句",
            explanation_zh: "这是句首的时间背景层。",
            why_it_matters_zh: "如果挂错，背景信息会被误读成核心判断。",
            example_en: "After the storm"
          }
        ],
        faithful_translation: "风暴过后，地方领导开始考虑应急方案是否需要修订。",
        teaching_interpretation: "先抓主句主干，再把前面的时间背景补回去。",
        misreading_traps: ["不要把时间背景误读成主干。"],
        exam_paraphrase_routes: ["题目可能把时间背景偷换成作者的核心判断。"],
        simpler_rewrite: "Local leaders considered whether the emergency plans needed revision after the storm.",
        simpler_rewrite_translation: "这句保留原意，只把时间背景后置。",
        mini_check: "这句真正的主干判断是什么？"
      }
    }
  ]);

  await withServer(upstream.server, async (upstreamPort) => {
    await withEnv({
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
    }, async () => {
      const app = createApp();
      await withServer(http.createServer(app), async (appPort) => {
        const response = await fetch(`http://127.0.0.1:${appPort}/ai/explain-sentence`, {
          method: "POST",
          headers: {
            "content-type": "application/json"
          },
          body: JSON.stringify(createPayload({
            client_request_id: "client-req-route-4",
            sentence_id: "sentence-4",
            sentence_text_hash: "hash-4"
          }))
        });

        const body = await response.json();
        assert.equal(response.status, 200);
        assert.equal(body.success, true);
        assertPublicMeta(body.meta);
      });
    });
  });
});
