import test from "node:test";
import assert from "node:assert/strict";

import { explainSentence } from "../../src/services/explainSentenceService.js";

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

function createAIClientReturning(rawResult, metaOverrides = {}) {
  return {
    async request() {
      return {
        success: true,
        data: {
          text: JSON.stringify(rawResult)
        },
        meta: {
          provider: "claude",
          model: "claude-opus-4-6",
          retry_count: 0,
          used_cache: false,
          used_fallback: false,
          circuit_state: "closed",
          ...metaOverrides
        }
      };
    }
  };
}

function collectStringValues(value, bucket = []) {
  if (typeof value === "string") {
    bucket.push(value);
    return bucket;
  }

  if (Array.isArray(value)) {
    for (const item of value) {
      collectStringValues(item, bucket);
    }
    return bucket;
  }

  if (value && typeof value === "object") {
    for (const item of Object.values(value)) {
      collectStringValues(item, bucket);
    }
  }

  return bucket;
}

test("explainSentence returns the new public contract with identity and meta", async () => {
  const payload = createPayload();
  const aiClient = createAIClientReturning({
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
        role: "前置框架",
        attaches_to: "核心信息",
        gloss: "先交代时间背景。"
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
    misreading_traps: ["不要把句首时间背景误当成作者真正的判断。"],
    exam_paraphrase_routes: ["题目可能把时间背景偷换成作者的核心判断。"],
    simpler_rewrite: "Local leaders began to consider whether emergency plans needed revision after the storm.",
    simpler_rewrite_translation: "这句保留原意，只把时间背景后置。",
    mini_check: "这句真正的主干判断落在哪一层？"
  });

  const result = await explainSentence(payload, {
    requestId: "req-contract-1",
    aiClient
  });

  assert.equal(result.data.identity.client_request_id, payload.identity.client_request_id);
  assert.equal(result.data.identity.document_id, payload.identity.document_id);
  assert.equal(result.data.identity.sentence_id, payload.identity.sentence_id);
  assert.equal(result.data.identity.segment_id, payload.identity.segment_id);
  assert.equal(result.data.identity.sentence_text_hash, payload.identity.sentence_text_hash);
  assert.equal(result.data.identity.anchor_label, payload.identity.anchor_label);
  assert.equal(result.data.original_sentence, payload.sentence);
  assert.equal(typeof result.data.sentence_function.title_zh, "string");
  assert.equal(typeof result.data.sentence_function.explanation_zh, "string");
  assert.equal(typeof result.data.core_skeleton.subject, "string");
  assert.equal(typeof result.data.core_skeleton.predicate, "string");
  assert.equal(typeof result.data.core_skeleton.complement_or_object, "string");
  assert.equal(typeof result.data.core_skeleton.explanation_zh, "string");
  assert.equal(typeof result.data.faithful_translation, "string");
  assert.equal(typeof result.data.teaching_interpretation, "string");
  assert.ok(Array.isArray(result.data.chunk_layers));
  assert.ok(Array.isArray(result.data.grammar_focus));
  assert.deepEqual(result.meta, {
    provider: "claude",
    model: "claude-opus-4-6",
    retry_count: 0,
    used_cache: false,
    used_fallback: false,
    circuit_state: "closed"
  });
});

test("explainSentence enforces anti-teaching translation rules and keeps teaching_interpretation distinct", async () => {
  const payload = createPayload({
    identity: {
      client_request_id: "client-req-2",
      sentence_id: "sentence-2",
      sentence_text_hash: "hash-2"
    }
  });
  const aiClient = createAIClientReturning({
    original_sentence: payload.sentence,
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
    faithful_translation: "学生容易误读这句，因为作者真正强调的是地方领导在风暴后重新考虑应急方案。",
    teaching_interpretation: "学生容易误读这句，因为作者真正强调的是地方领导在风暴后重新考虑应急方案。",
    misreading_traps: ["不要把时间背景误当成主句判断。"],
    exam_paraphrase_routes: ["题目会把时间背景偷换成核心判断。"],
    simpler_rewrite: "Local leaders reconsidered the emergency plans after the storm.",
    simpler_rewrite_translation: "这句把结构改得更直接。",
    mini_check: "主干判断是什么？"
  });

  const result = await explainSentence(payload, {
    requestId: "req-contract-2",
    aiClient
  });

  assert.doesNotMatch(result.data.faithful_translation, /学生容易误读|做题时要注意|作者真正强调|本句承担/);
  assert.notEqual(result.data.teaching_interpretation, result.data.faithful_translation);
  assert.notEqual(
    result.data.teaching_interpretation.replace(/\s+/g, ""),
    result.data.faithful_translation.replace(/\s+/g, "")
  );
});

test("explainSentence recursively removes bracket leakage and localizes grammar_focus display fields", async () => {
  const payload = createPayload({
    identity: {
      client_request_id: "client-req-3",
      sentence_id: "sentence-3",
      sentence_text_hash: "hash-3"
    }
  });
  const aiClient = createAIClientReturning({
    original_sentence: payload.sentence,
    sentence_function: "核心判断句：[subject: local leaders] 在这里提出真正判断。",
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
        gloss: "这一块说明 [subject: local leaders] 开始思考的时间背景。"
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
    teaching_interpretation: "这句先给时间背景，再把真正判断压在主句里。",
    misreading_traps: ["不要把 [predicate: began to consider] 前面的时间背景误抬成主干。"],
    exam_paraphrase_routes: ["题目可能把 [object clause: whether emergency plans needed revision] 改写成更简短的同义表达。"],
    simpler_rewrite: "Local leaders considered whether the emergency plans needed revision after the storm.",
    simpler_rewrite_translation: "这句保留原意，只把修饰层压缩。",
    mini_check: "先指出句子的主语和谓语。"
  });

  const result = await explainSentence(payload, {
    requestId: "req-contract-3",
    aiClient
  });

  const strings = collectStringValues(result.data);
  for (const value of strings) {
    assert.doesNotMatch(value, /\[subject:|\[predicate:|\[object clause:|\[complement:/);
  }

  assert.equal(typeof result.data.grammar_focus[0].title_zh, "string");
  assert.equal(typeof result.data.grammar_focus[0].explanation_zh, "string");
  assert.equal(typeof result.data.grammar_focus[0].why_it_matters_zh, "string");
  assert.ok(result.data.grammar_focus[0].title_zh.length > 0);
  assert.ok(result.data.grammar_focus[0].explanation_zh.length > 0);
  assert.ok(result.data.grammar_focus[0].why_it_matters_zh.length > 0);
});
