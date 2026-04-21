import test from "node:test";
import assert from "node:assert/strict";

import { __testables } from "../src/services/explainSentenceService.js";

const {
  buildExplainSentenceFallbackSkeleton,
  collectBracketLeaks,
  containsTeachingTone,
  normalizeCoreSkeleton,
  normalizeGrammarFocus,
  normalizePublicExplainSentenceContract,
  validateExplainSentencePublicContract
} = __testables;

function createPayload(overrides = {}) {
  return {
    identity: {
      client_request_id: "client-req-1",
      document_id: "document-1",
      sentence_id: "sentence-1",
      segment_id: "segment-1",
      sentence_text_hash: "hash-1",
      anchor_label: "S1",
      ...(overrides.identity || {})
    },
    title: "Lesson Title",
    sentence: "After the storm, local leaders began to consider whether emergency plans needed revision.",
    context: "The author is explaining how the community responded after the storm.",
    paragraph_theme: "灾后应对评估",
    paragraph_role: "support",
    question_prompt: "Why did the leaders reconsider the emergency plans?",
    ...overrides
  };
}

test("normalizeCoreSkeleton strips legacy bracket markup into structured fields", () => {
  const skeleton = normalizeCoreSkeleton({
    subject: "[subject: local leaders]",
    predicate: "[predicate: began to consider]",
    complement_or_object: "[object clause: whether emergency plans needed revision]"
  }, "unused");

  assert.deepEqual(skeleton, {
    subject: "local leaders",
    predicate: "began to consider",
    complement_or_object: "whether emergency plans needed revision"
  });
});

test("normalizeGrammarFocus localizes legacy english-only grammar fields into Chinese-first fields", () => {
  const items = normalizeGrammarFocus([
    {
      phenomenon: "After引导的 temporal clause",
      function: "After引导的时间状语从句，先交代时间背景，再进入主句判断。",
      why_it_matters: "temporal clause 一旦挂错，背景信息就会被错读成核心判断。",
      example_en: "After the storm"
    }
  ], "After the storm, local leaders began to consider whether emergency plans needed revision.");

  assert.equal(items.length, 1);
  assert.equal(items[0].title_zh, "时间状语从句");
  assert.doesNotMatch(items[0].explanation_zh, /temporal clause/i);
  assert.doesNotMatch(items[0].why_it_matters_zh, /temporal clause/i);
});

test("normalizePublicExplainSentenceContract emits the new contract without public legacy fields", () => {
  const payload = createPayload();

  const result = normalizePublicExplainSentenceContract({
    original_sentence: payload.sentence,
    sentence_function: "核心判断句：作者真正要成立的判断在这里。",
    core_skeleton: {
      subject: "[subject: local leaders]",
      predicate: "[predicate: began to consider]",
      complement_or_object: "[object clause: whether emergency plans needed revision]"
    },
    chunk_layers: [
      {
        text: "After the storm",
        role: "[complement: frame]",
        attaches_to: "[predicate: began to consider]",
        gloss: "先交代 [subject: local leaders] 开始思考的时间背景。"
      }
    ],
    grammar_focus: [
      {
        phenomenon: "After引导的 temporal clause",
        function: "After引导的时间状语从句，先交代时间背景，再进入主句判断。",
        why_it_matters: "temporal clause 一旦挂错，背景信息就会被错读成核心判断。",
        example_en: "After the storm"
      }
    ],
    faithful_translation: "风暴过后，地方领导开始考虑应急方案是否需要修订。",
    teaching_interpretation: "先抓主句主干，再把前面的时间背景补回去。",
    misreading_traps: ["不要把 [predicate: began to consider] 前面的时间背景误抬成主干。"],
    exam_paraphrase_routes: ["题目可能把 [object clause: whether emergency plans needed revision] 改写成更简短的同义表达。"],
    simpler_rewrite: "Local leaders considered whether the emergency plans needed revision after the storm.",
    simpler_rewrite_translation: "这句保留原意，只把时间背景后置。",
    mini_check: "先指出句子的主语和谓语。"
  }, payload);

  assert.equal(result.identity.client_request_id, payload.identity.client_request_id);
  assert.equal(result.original_sentence, payload.sentence);
  assert.equal(typeof result.sentence_function.title_zh, "string");
  assert.equal(typeof result.core_skeleton.explanation_zh, "string");
  assert.ok(!("translation" in result));
  assert.ok(!("main_structure" in result));
  assert.ok(!("rewrite_example" in result));
  assert.equal(collectBracketLeaks(result).length, 0);
});

test("validateExplainSentencePublicContract rejects teaching-tone translations and duplicated interpretations", () => {
  const payload = createPayload({
    identity: {
      client_request_id: "client-req-2",
      sentence_id: "sentence-2",
      sentence_text_hash: "hash-2"
    }
  });
  const contract = {
    identity: payload.identity,
    original_sentence: payload.sentence,
    sentence_function: {
      title_zh: "句子定位",
      explanation_zh: "这句话在本段中承担核心判断功能。"
    },
    core_skeleton: {
      subject: "local leaders",
      predicate: "began to consider",
      complement_or_object: "whether emergency plans needed revision",
      explanation_zh: "先锁定主干。"
    },
    faithful_translation: "学生容易误读这句，因为作者真正强调的是地方领导在风暴后重新考虑应急方案。",
    teaching_interpretation: "学生容易误读这句，因为作者真正强调的是地方领导在风暴后重新考虑应急方案。",
    chunk_layers: [
      {
        text: "After the storm",
        role_zh: "前置框架",
        attaches_to: "核心信息",
        gloss_zh: "先交代时间背景。"
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
    misreading_traps: ["不要把时间背景误读成主干。"],
    exam_paraphrase_routes: ["题目可能把时间背景偷换成作者的核心判断。"],
    simpler_rewrite: "Local leaders reconsidered the emergency plans after the storm.",
    simpler_rewrite_translation: "这句把结构改得更直接。",
    mini_check: "主干判断是什么？"
  };

  const reasons = validateExplainSentencePublicContract(contract, payload);

  assert.ok(containsTeachingTone(contract.faithful_translation));
  assert.ok(reasons.some((item) => item.includes("faithful_translation")));
  assert.ok(reasons.some((item) => item.includes("teaching_interpretation")));
});

test("buildExplainSentenceFallbackSkeleton returns a renderable local skeleton", () => {
  const payload = createPayload({
    identity: {
      client_request_id: "client-req-3",
      sentence_id: "sentence-3",
      sentence_text_hash: "hash-3"
    }
  });
  const skeleton = buildExplainSentenceFallbackSkeleton(payload);

  assert.equal(skeleton.identity.sentence_id, payload.identity.sentence_id);
  assert.equal(skeleton.original_sentence, payload.sentence);
  assert.equal(skeleton.faithful_translation, "AI 翻译暂不可用，可稍后重试。");
  assert.equal(skeleton.teaching_interpretation, "AI 精讲暂不可用，当前展示本地解析骨架。");
  assert.ok(Array.isArray(skeleton.chunk_layers));
  assert.ok(Array.isArray(skeleton.grammar_focus));
  assert.equal(collectBracketLeaks(skeleton).length, 0);
});
