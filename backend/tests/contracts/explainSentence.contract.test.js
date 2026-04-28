import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

import { resetAIPersistentCacheStoreForTests } from "../../src/services/AIPersistentCacheStore.js";
import {
  __testables,
  explainSentence
} from "../../src/services/explainSentenceService.js";

const {
  resetExplainSentenceModelInvokerForTests,
  setExplainSentenceModelInvokerForTests
} = __testables;

const SENTENCE = "Researchers found that trust depended on shared public systems.";

function resultJSON() {
  return {
    original_sentence: SENTENCE,
    evidence_type: "core_claim",
    sentence_function: "核心判断句：这句说明信任依赖共同的公共系统。",
    core_skeleton: {
      subject: "trust",
      predicate: "depended",
      complement_or_object: "on shared public systems"
    },
    chunk_layers: [
      {
        text: "trust depended on shared public systems",
        role: "核心信息",
        attaches_to: "主句主干",
        gloss: "先抓信任依赖什么。"
      }
    ],
    grammar_focus: [
      {
        phenomenon: "object of preposition",
        function: "介词 on 后面的名词短语说明 depended 的依赖对象。",
        why_it_matters: "看清介词宾语才能知道依赖对象。",
        title_zh: "介词宾语",
        explanation_zh: "这是介词后面承接的名词短语。",
        why_it_matters_zh: "它决定 depended on 的具体对象。",
        example_en: "on shared public systems"
      }
    ],
    faithful_translation: "研究者发现，信任依赖共同的公共系统。",
    teaching_interpretation: "先抓 trust depended on shared public systems，再看 Researchers found that 只是信息来源框架。",
    natural_chinese_meaning: "先抓 trust depended on shared public systems，再看 Researchers found that 只是信息来源框架。",
    contextual_vocabulary: [],
    misreading_traps: ["不要把 Researchers found that 当作核心观点本身。"],
    exam_paraphrase_routes: ["题目可能把 depended on 改写成 was based on。"],
    simpler_rewrite: "Trust relied on shared public systems.",
    simpler_rewrite_translation: "这条改写保留原意，把 depended on 换成 relied on。",
    mini_check: "trust 依赖什么？",
    hierarchy_rebuild: [],
    syntactic_variation: "Trust was based on shared public systems."
  };
}

async function withIsolatedCache(fn) {
  const originalModelName = process.env.MODEL_NAME;
  process.env.MODEL_NAME = "contract-model";
  const dir = mkdtempSync(join(tmpdir(), "cuotiben-contract-cache-"));
  resetAIPersistentCacheStoreForTests({ dbPath: join(dir, "cache.sqlite3") });
  resetExplainSentenceModelInvokerForTests();
  try {
    return await fn();
  } finally {
    resetExplainSentenceModelInvokerForTests();
    resetAIPersistentCacheStoreForTests();
    if (originalModelName === undefined) {
      delete process.env.MODEL_NAME;
    } else {
      process.env.MODEL_NAME = originalModelName;
    }
    rmSync(dir, { recursive: true, force: true });
  }
}

test("explainSentence service contract keeps public data fields stable", () => withIsolatedCache(async () => {
  setExplainSentenceModelInvokerForTests(async () => ({
    choices: [{ message: { content: JSON.stringify(resultJSON()) } }]
  }));

  const data = await explainSentence({
    requestID: "contract-request",
    title: "Demo",
    sentence: SENTENCE,
    context: "The passage discusses public systems.",
    paragraph_theme: "Public systems",
    paragraph_role: "support",
    document_id: "doc-contract-route",
    sentence_id: "sen-contract-route",
    sentence_text_hash: "hash-contract-route",
    anchor_label: "第1页 第1句",
    segment_id: "seg-contract-route"
  });

  assert.equal(data.original_sentence, SENTENCE);
  assert.equal(typeof data.faithful_translation, "string");
  assert.equal(typeof data.teaching_interpretation, "string");
  assert.equal(typeof data.sentence_core, "string");
  assert.equal(Array.isArray(data.chunk_layers), true);
  assert.equal(Array.isArray(data.grammar_focus), true);
  assert.equal(Array.isArray(data.misreading_traps), true);
  assert.equal(data.identity.document_id, "doc-contract-route");
  assert.equal(data.analysis_identity.source_sentence_id, "sen-contract-route");
  assert.equal(data.request_id, "contract-request");
  assert.equal(data.used_fallback, false);
  assert.equal("success" in data, false);
}));
