import test from "node:test";
import assert from "node:assert/strict";

import { __testables } from "../src/services/explainSentenceService.js";

const {
  normalizeExplainResult,
  normalizeCoreSkeleton,
  normalizeGrammarFocus
} = __testables;

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

test("normalizeGrammarFocus localizes mixed grammar labels into Chinese-first fields", () => {
  const items = normalizeGrammarFocus([
    {
      phenomenon: "After引导的 temporal clause",
      function: "After引导的时间状语从句，先交代时间背景，再进入主句判断。",
      why_it_matters: "temporal clause 一旦挂错，背景信息就会被错读成核心判断。",
      title_zh: "",
      explanation_zh: "",
      why_it_matters_zh: "",
      example_en: "After the storm"
    }
  ], "After the storm, local leaders began to consider whether emergency plans needed revision.");

  assert.equal(items.length, 1);
  assert.equal(items[0].title_zh, "时间状语从句");
  assert.match(items[0].function, /时间背景|主句判断/);
  assert.doesNotMatch(items[0].explanation_zh, /temporal clause/i);
  assert.doesNotMatch(items[0].why_it_matters_zh, /temporal clause/i);
});

test("normalizeExplainResult replaces legacy sentence core markup and keeps grammar focus Chinese-first", () => {
  const sourceSentence = "After the storm, local leaders began to consider whether emergency plans needed revision.";
  const result = normalizeExplainResult({
    original_sentence: sourceSentence,
    evidence_type: "core_claim",
    sentence_function: "核心判断句：作者真正要成立的判断在这里。",
    core_skeleton: {
      subject: "[subject: local leaders]",
      predicate: "[predicate: began to consider]",
      complement_or_object: "[object clause: whether emergency plans needed revision]"
    },
    chunk_layers: [
      {
        text: "After the storm",
        role: "时间框架",
        attaches_to: "核心信息",
        gloss: "先交代时间背景。"
      }
    ],
    grammar_focus: [
      {
        phenomenon: "After引导的 temporal clause",
        function: "After引导的时间状语从句，先交代时间背景，再进入主句判断。",
        why_it_matters: "temporal clause 一旦挂错，背景信息就会被错读成核心判断。",
        title_zh: "",
        explanation_zh: "",
        why_it_matters_zh: "",
        example_en: "After the storm"
      }
    ],
    faithful_translation: "风暴过后，地方领导开始考虑应急方案是否需要修订。",
    teaching_interpretation: "先看主句，再把前面的时间背景补回去。",
    contextual_vocabulary: [],
    misreading_traps: ["不要把前面的时间背景误当成主句判断。"],
    exam_paraphrase_routes: ["命题人可能把时间背景偷换成作者真正的判断。"],
    simpler_rewrite: "Local leaders began to consider whether emergency plans needed revision after the storm.",
    simpler_rewrite_translation: "这句保留原意，只把时间背景后置。",
    mini_check: "",
    hierarchy_rebuild: [],
    syntactic_variation: ""
  }, sourceSentence, "support");

  assert.equal(
    result.sentence_core,
    "主语：local leaders｜谓语：began to consider｜核心补足：whether emergency plans needed revision"
  );
  assert.ok(!result.sentence_core.includes("[subject:"));
  assert.equal(result.grammar_focus[0].title_zh, "时间状语从句");
  assert.match(result.grammar_focus[0].function, /时间背景|主句判断/);
  assert.doesNotMatch(result.grammar_focus[0].explanation_zh, /temporal clause/i);
});
