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
    client_request_id: "client-passage-route-1",
    document_id: "document-1",
    content_hash: "content-hash-1",
    title: "城市恢复与公共治理",
    paragraphs: [
      {
        segment_id: "seg-1",
        index: 0,
        anchor_label: "P1",
        text: "After the storm, local officials reviewed the city response and compared it with earlier emergency plans.",
        source_kind: "passage_body",
        hygiene_score: 0.92
      },
      {
        segment_id: "seg-2",
        index: 1,
        anchor_label: "P2",
        text: "However, residents argued that the review mattered only if it changed how future warnings reached vulnerable neighborhoods.",
        source_kind: "passage_body",
        hygiene_score: 0.9
      }
    ],
    question_blocks: [
      {
        block_id: "question-1",
        source_kind: "question",
        text: "Which paragraph best shows the shift from review to reform?"
      }
    ],
    answer_blocks: [
      {
        block_id: "answer-1",
        source_kind: "answer_key",
        text: "Paragraph 2"
      }
    ],
    vocabulary_blocks: [
      {
        block_id: "vocab-1",
        source_kind: "vocabulary_support",
        text: "vulnerable: likely to be harmed"
      }
    ],
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

    if (req.url === "/v1/messages") {
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

      res.writeHead(step.status ?? 200, { "content-type": "application/json" });
      res.end(JSON.stringify(step.status && step.status >= 400 ? step.body : buildAnthropicResponse(step.body)));
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

function collectKeys(value, bucket = []) {
  if (Array.isArray(value)) {
    for (const item of value) {
      collectKeys(item, bucket);
    }
    return bucket;
  }

  if (value && typeof value === "object") {
    for (const [key, nested] of Object.entries(value)) {
      bucket.push(key);
      collectKeys(nested, bucket);
    }
  }

  return bucket;
}

test("POST /ai/analyze-passage success path returns request_id, data, and public meta", async () => {
  const upstream = createUpstreamServer([
    {
      status: 200,
      body: {
        passage_overview: {
          article_theme: "文章围绕灾后复盘与制度改革展开。",
          author_core_question: "作者真正关心复盘能否推动制度改进。",
          progression_path: "先交代复盘背景，再推进到改革要求，最后收束到治理调整。",
          likely_question_types: ["主旨题：作者真正关注什么"],
          logic_pitfalls: ["容易把背景信息错看成结论"]
        },
        paragraph_cards: [
          {
            segment_id: "seg-1",
            paragraph_index: 0,
            anchor_label: "P1",
            theme: "第一段先交代复盘背景。",
            argument_role: "background",
            core_sentence_id: "seg-1::s1",
            relation_to_previous: "首段建立背景。",
            exam_value: "可作为主旨题铺垫段。",
            teaching_focuses: ["先看复盘是背景，不是结论。"],
            student_blind_spot: "容易把复盘动作直接当成作者主张。",
            provenance: {
              source_segment_id: "seg-1",
              source_sentence_id: "seg-1::s1",
              source_kind: "passage_body",
              generated_from: "ai_passage_analysis",
              hygiene_score: 0.92,
              consistency_score: 0.91
            }
          },
          {
            segment_id: "seg-2",
            paragraph_index: 1,
            anchor_label: "P2",
            theme: "第二段把重心推进到改革必要性。",
            argument_role: "support",
            core_sentence_id: "seg-2::s1",
            relation_to_previous: "在背景之后推进真正关心的改革方向。",
            exam_value: "常对应作者意图或段落功能题。",
            teaching_focuses: ["盯住 however 后的真正推进方向。"],
            student_blind_spot: "会把居民声音只看成细节，不看它推动了论证方向。",
            provenance: {
              source_segment_id: "seg-2",
              source_sentence_id: "seg-2::s1",
              source_kind: "passage_body",
              generated_from: "ai_passage_analysis",
              hygiene_score: 0.9,
              consistency_score: 0.9
            }
          }
        ],
        key_sentence_ids: ["seg-1::s1", "seg-2::s1"],
        question_links: [
          {
            source_kind: "question",
            linked_segment_id: "seg-2",
            summary: "题目会抓第二段的转折推进。"
          }
        ]
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
      const server = http.createServer(app);

      await withServer(server, async (port) => {
        const response = await fetch(`http://127.0.0.1:${port}/ai/analyze-passage`, {
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
        assert.ok(body.data.passage_overview);
        assert.ok(Array.isArray(body.data.paragraph_cards));
        assert.ok(Array.isArray(body.data.key_sentence_ids));
        assert.ok(Array.isArray(body.data.question_links));
        assertPublicMeta(body.meta);
        assert.equal(upstream.receivedRequests.length > 0, true);
      });
    });
  });
});

test("POST /ai/analyze-passage returns INVALID_REQUEST and never calls upstream when identity is missing", async () => {
  const upstream = createUpstreamServer([]);

  await withServer(upstream.server, async (upstreamPort) => {
    await withEnv({
      NOVAI_API_KEY: "test-token",
      AI_PROVIDER: "claude",
      AI_MODEL: "claude-opus-4-6",
      AI_BASE_URL: `http://127.0.0.1:${upstreamPort}`,
      AI_API_KIND: "anthropic-messages",
      AI_TIMEOUT_MS: "30000",
      AI_MAX_RETRIES: "3",
      AI_CIRCUIT_BREAKER_ENABLED: "true"
    }, async () => {
      const app = createApp();
      const server = http.createServer(app);

      await withServer(server, async (port) => {
        const payload = createPayload();
        delete payload.document_id;

        const response = await fetch(`http://127.0.0.1:${port}/ai/analyze-passage`, {
          method: "POST",
          headers: {
            "content-type": "application/json"
          },
          body: JSON.stringify(payload)
        });

        assert.equal(response.status, 400);
        const body = await response.json();
        assert.equal(body.success, false);
        assert.equal(body.error_code, "INVALID_REQUEST");
        assert.equal(upstream.receivedRequests.length, 0);
      });
    });
  });
});

test("POST /ai/analyze-passage rejects more than four paragraphs before upstream", async () => {
  const upstream = createUpstreamServer([]);

  await withServer(upstream.server, async (upstreamPort) => {
    await withEnv({
      NOVAI_API_KEY: "test-token",
      AI_PROVIDER: "claude",
      AI_MODEL: "claude-opus-4-6",
      AI_BASE_URL: `http://127.0.0.1:${upstreamPort}`,
      AI_API_KIND: "anthropic-messages",
      AI_TIMEOUT_MS: "30000",
      AI_MAX_RETRIES: "3",
      AI_CIRCUIT_BREAKER_ENABLED: "true"
    }, async () => {
      const app = createApp();
      const server = http.createServer(app);

      await withServer(server, async (port) => {
        const paragraphs = Array.from({ length: 5 }, (_, index) => ({
          segment_id: `seg-${index + 1}`,
          index,
          anchor_label: `P${index + 1}`,
          text: "This paragraph is long enough to be treated as a passage body sentence for testing.",
          source_kind: "passage_body",
          hygiene_score: 0.9
        }));

        const response = await fetch(`http://127.0.0.1:${port}/ai/analyze-passage`, {
          method: "POST",
          headers: {
            "content-type": "application/json"
          },
          body: JSON.stringify(createPayload({ paragraphs }))
        });

        assert.equal(response.status, 400);
        const body = await response.json();
        assert.equal(body.error_code, "INVALID_REQUEST");
        assert.equal(upstream.receivedRequests.length, 0);
      });
    });
  });
});

test("POST /ai/analyze-passage rejects paragraphs longer than 700 chars before upstream", async () => {
  const upstream = createUpstreamServer([]);

  await withServer(upstream.server, async (upstreamPort) => {
    await withEnv({
      NOVAI_API_KEY: "test-token",
      AI_PROVIDER: "claude",
      AI_MODEL: "claude-opus-4-6",
      AI_BASE_URL: `http://127.0.0.1:${upstreamPort}`,
      AI_API_KIND: "anthropic-messages",
      AI_TIMEOUT_MS: "30000",
      AI_MAX_RETRIES: "3",
      AI_CIRCUIT_BREAKER_ENABLED: "true"
    }, async () => {
      const app = createApp();
      const server = http.createServer(app);

      await withServer(server, async (port) => {
        const response = await fetch(`http://127.0.0.1:${port}/ai/analyze-passage`, {
          method: "POST",
          headers: {
            "content-type": "application/json"
          },
          body: JSON.stringify(createPayload({
            paragraphs: [
              {
                segment_id: "seg-1",
                index: 0,
                anchor_label: "P1",
                text: "A".repeat(701),
                source_kind: "passage_body",
                hygiene_score: 0.9
              }
            ]
          }))
        });

        assert.equal(response.status, 400);
        const body = await response.json();
        assert.equal(body.error_code, "INVALID_REQUEST");
        assert.equal(upstream.receivedRequests.length, 0);
      });
    });
  });
});

test("POST /ai/analyze-passage returns a passage map fallback skeleton when upstream is 503", async () => {
  const upstream = createUpstreamServer([
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
      AI_TIMEOUT_MS: "30",
      AI_MAX_RETRIES: "2",
      AI_CIRCUIT_BREAKER_ENABLED: "true"
    }, async () => {
      const app = createApp();
      const server = http.createServer(app);

      await withServer(server, async (port) => {
        const response = await fetch(`http://127.0.0.1:${port}/ai/analyze-passage`, {
          method: "POST",
          headers: {
            "content-type": "application/json"
          },
          body: JSON.stringify(createPayload({
            document_id: "document-503",
            content_hash: "content-hash-503"
          }))
        });

        assert.equal(response.status, 200);
        const body = await response.json();
        assert.equal(body.success, true);
        assert.equal(body.meta.used_fallback, true);
        assert.ok(body.data.passage_overview);
        assert.ok(Array.isArray(body.data.paragraph_cards));
        assert.ok(Array.isArray(body.data.key_sentence_ids));
        assert.ok(Array.isArray(body.data.question_links));
      });
    });
  });
});

test("POST /ai/analyze-passage strips forbidden sentence-level fields from a fat upstream payload", async () => {
  const upstream = createUpstreamServer([
    {
      status: 200,
      body: {
        passage_overview: {
          article_theme: "文章围绕灾后治理与制度改革展开。",
          author_core_question: "作者真正关心复盘能否推动制度改进。",
          progression_path: "先交代背景，再推进改革需求。",
          likely_question_types: ["主旨题：作者关切"],
          logic_pitfalls: ["容易把背景误判成结论"]
        },
        paragraph_cards: [
          {
            segment_id: "seg-1",
            paragraph_index: 0,
            anchor_label: "P1",
            theme: "第一段交代复盘背景。",
            argument_role: "background",
            core_sentence_id: "seg-1::s1",
            relation_to_previous: "首段建立背景。",
            exam_value: "主旨题背景铺垫。",
            teaching_focuses: ["先定位背景角色。"],
            student_blind_spot: "会把背景直接当作者主张。",
            grammar_focus: [{ title_zh: "不该出现" }],
            faithful_translation: "不该出现",
            teaching_interpretation: "不该出现",
            core_skeleton: {
              subject: "it"
            },
            chunk_layers: [
              {
                text: "bad"
              }
            ],
            provenance: {
              source_segment_id: "seg-1",
              source_sentence_id: "seg-1::s1",
              source_kind: "passage_body",
              generated_from: "ai_passage_analysis",
              hygiene_score: 0.92,
              consistency_score: 0.91
            }
          }
        ],
        key_sentence_ids: ["seg-1::s1"],
        question_links: []
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
      AI_CIRCUIT_BREAKER_ENABLED: "true"
    }, async () => {
      const app = createApp();
      const server = http.createServer(app);

      await withServer(server, async (port) => {
        const response = await fetch(`http://127.0.0.1:${port}/ai/analyze-passage`, {
          method: "POST",
          headers: {
            "content-type": "application/json"
          },
          body: JSON.stringify(createPayload())
        });

        assert.equal(response.status, 200);
        const body = await response.json();
        const keys = collectKeys(body.data);

        for (const forbidden of [
          "grammar_focus",
          "faithful_translation",
          "teaching_interpretation",
          "core_skeleton",
          "chunk_layers"
        ]) {
          assert.equal(keys.includes(forbidden), false, `unexpected field ${forbidden}`);
        }
      });
    });
  });
});
