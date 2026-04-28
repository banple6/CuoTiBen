import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { once } from "node:events";
import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

import { createApp } from "../../src/app.js";
import { resetAIPersistentCacheStoreForTests } from "../../src/services/AIPersistentCacheStore.js";
import { __testables } from "../../src/services/explainSentenceService.js";

const {
  resetExplainSentenceModelInvokerForTests,
  setExplainSentenceModelInvokerForTests
} = __testables;

const SENTENCE = "The policy changes could be implemented only after further review.";

function explainResult() {
  return {
    original_sentence: SENTENCE,
    evidence_type: "supporting_evidence",
    sentence_function: "支撑证据句：这句说明政策变化需要进一步审查后才能执行。",
    core_skeleton: {
      subject: "The policy changes",
      predicate: "could be implemented",
      complement_or_object: "only after further review"
    },
    chunk_layers: [
      {
        text: "The policy changes could be implemented",
        role: "核心信息",
        attaches_to: "主句主干",
        gloss: "先抓政策变化可以被执行。"
      }
    ],
    grammar_focus: [
      {
        phenomenon: "passive voice",
        function: "被动结构强调政策变化被执行，而不是谁执行。",
        why_it_matters: "被动方向看错会误读动作承受者。",
        title_zh: "被动结构",
        explanation_zh: "这是把动作承受者放到前面的结构。",
        why_it_matters_zh: "它决定动作方向。",
        example_en: "could be implemented"
      }
    ],
    faithful_translation: "这些政策变化只有在进一步审查后才能执行。",
    teaching_interpretation: "先抓 The policy changes could be implemented，再把 only after further review 当作执行条件。",
    natural_chinese_meaning: "先抓 The policy changes could be implemented，再把 only after further review 当作执行条件。",
    contextual_vocabulary: [],
    misreading_traps: ["不要忽略 only after 带来的条件限制。"],
    exam_paraphrase_routes: ["题目可能把 only after 改写成 not until。"],
    simpler_rewrite: "The changes could happen after more review.",
    simpler_rewrite_translation: "这条改写保留原意，把被动执行改成更直接的 happen。",
    mini_check: "政策变化什么时候才能执行？",
    hierarchy_rebuild: [],
    syntactic_variation: "Further review was needed before the policy changes could happen."
  };
}

async function withServer(fn) {
  const originalModelName = process.env.MODEL_NAME;
  process.env.MODEL_NAME = "route-contract-model";
  const dir = mkdtempSync(join(tmpdir(), "cuotiben-route-cache-"));
  resetAIPersistentCacheStoreForTests({ dbPath: join(dir, "cache.sqlite3") });
  resetExplainSentenceModelInvokerForTests();
  const server = createServer(createApp());
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const { port } = server.address();

  try {
    await fn(`http://127.0.0.1:${port}`);
  } finally {
    resetExplainSentenceModelInvokerForTests();
    resetAIPersistentCacheStoreForTests();
    if (originalModelName === undefined) {
      delete process.env.MODEL_NAME;
    } else {
      process.env.MODEL_NAME = originalModelName;
    }
    rmSync(dir, { recursive: true, force: true });
    await new Promise((resolve, reject) => {
      server.close((error) => {
        if (error) reject(error);
        else resolve();
      });
    });
  }
}

test("/ai/explain-sentence route envelope remains stable", () => withServer(async (baseURL) => {
  setExplainSentenceModelInvokerForTests(async () => ({
    choices: [{ message: { content: JSON.stringify(explainResult()) } }]
  }));

  const response = await fetch(`${baseURL}/ai/explain-sentence`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      client_request_id: "route-request",
      title: "Demo",
      sentence: SENTENCE,
      context: "The passage discusses policy timing.",
      paragraph_theme: "Policy timing",
      paragraph_role: "support",
      document_id: "doc-route",
      sentence_id: "sen-route",
      sentence_text_hash: "hash-route",
      anchor_label: "第1页 第1句",
      segment_id: "seg-route"
    })
  });

  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(body.success, true);
  assert.equal(body.request_id, "route-request");
  assert.equal(body.used_cache, false);
  assert.equal(body.used_fallback, false);
  assert.equal(typeof body.retry_count, "number");
  assert.equal(body.data.original_sentence, SENTENCE);
  assert.equal(body.data.identity.document_id, "doc-route");
  assert.equal(body.data.analysis_identity.source_sentence_id, "sen-route");
  assert.equal(typeof body.data.faithful_translation, "string");
}));
