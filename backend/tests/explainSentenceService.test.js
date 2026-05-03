import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

import { AppError } from "../src/lib/appError.js";
import {
  buildSentenceExplainCacheKey,
  getAIPersistentCacheStore,
  resetAIPersistentCacheStoreForTests
} from "../src/services/AIPersistentCacheStore.js";
import {
  __testables,
  explainSentence,
  makePersistentExplainCacheIdentity
} from "../src/services/explainSentenceService.js";

const {
  normalizeExplainResult,
  normalizeCoreSkeleton,
  normalizeGrammarFocus,
  resetExplainSentenceModelInvokerForTests,
  setExplainSentenceModelInvokerForTests,
  storePersistentExplainReadyIfEligible
} = __testables;

const TEST_MODEL_NAME = "test-sentence-model";
const TEST_SENTENCE = "Local leaders began to consider whether emergency plans needed revision.";

async function withPersistentStore(fn) {
  const originalModelName = process.env.MODEL_NAME;
  process.env.MODEL_NAME = TEST_MODEL_NAME;
  const dir = mkdtempSync(join(tmpdir(), "cuotiben-explain-cache-"));
  resetAIPersistentCacheStoreForTests({ dbPath: join(dir, "cache.sqlite3") });
  resetExplainSentenceModelInvokerForTests();
  try {
    return await fn(getAIPersistentCacheStore());
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

function explainPayload(overrides = {}) {
  return {
    requestID: "req-current",
    title: "Demo",
    sentence: TEST_SENTENCE,
    context: "The article discusses public emergency planning.",
    paragraph_theme: "Emergency planning",
    paragraph_role: "support",
    question_prompt: "",
    document_id: "doc-1",
    client_request_id: "client-1",
    sentence_id: "sen-1",
    sentence_text_hash: "hash-1",
    anchor_label: "第1页 第1句",
    segment_id: "seg-1",
    ...overrides
  };
}

function modelResult(sentence = TEST_SENTENCE) {
  return {
    original_sentence: sentence,
    evidence_type: "core_claim",
    sentence_function: "核心判断句：这句说明地方领导开始考虑应急方案是否需要修订。",
    core_skeleton: {
      subject: "Local leaders",
      predicate: "began to consider",
      complement_or_object: "whether emergency plans needed revision"
    },
    chunk_layers: [
      {
        text: "Local leaders began to consider",
        role: "核心信息",
        attaches_to: "主句主干",
        gloss: "先抓地方领导开始考虑这一动作。"
      }
    ],
    grammar_focus: [
      {
        phenomenon: "object clause",
        function: "宾语从句承接 consider，说明具体考虑内容。",
        why_it_matters: "宾语从句挂错会误读考虑对象。",
        title_zh: "宾语从句",
        explanation_zh: "这是跟在谓语后面充当内容对象的从句。",
        why_it_matters_zh: "看清宾语从句才能知道真正被考虑的内容。",
        example_en: "whether emergency plans needed revision"
      }
    ],
    faithful_translation: "地方领导开始考虑应急方案是否需要修订。",
    teaching_interpretation: "先抓主干 Local leaders began to consider，再把 whether 从句当作考虑的具体内容。",
    natural_chinese_meaning: "先抓主干 Local leaders began to consider，再把 whether 从句当作考虑的具体内容。",
    contextual_vocabulary: [],
    misreading_traps: ["不要把 whether 从句误当成另一个独立主句。"],
    exam_paraphrase_routes: ["题目可能把 consider 改写成 discuss 或 review。"],
    simpler_rewrite: "Local leaders considered revising emergency plans.",
    simpler_rewrite_translation: "这条改写保留原意，把 whether 从句压缩成 revising emergency plans。",
    mini_check: "consider 的宾语是什么？",
    hierarchy_rebuild: [],
    syntactic_variation: "Local leaders started to review whether the plans needed revision."
  };
}

function completionFor(sentence = TEST_SENTENCE) {
  return {
    choices: [
      {
        message: {
          content: JSON.stringify(modelResult(sentence))
        }
      }
    ]
  };
}

function persistentIdentity(overrides = {}) {
  return makePersistentExplainCacheIdentity({
    document_id: "doc-1",
    sentence_id: "sen-1",
    sentence_text_hash: "hash-1",
    modelName: TEST_MODEL_NAME,
    ...overrides
  });
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

test("makePersistentExplainCacheIdentity includes document, sentence, hash, prompt version, and model", () => {
  const identity = persistentIdentity();
  const sameKey = buildSentenceExplainCacheKey(identity);
  const differentDocumentKey = buildSentenceExplainCacheKey(persistentIdentity({ document_id: "doc-2" }));
  const differentSentenceKey = buildSentenceExplainCacheKey(persistentIdentity({ sentence_id: "sen-2" }));
  const differentHashKey = buildSentenceExplainCacheKey(persistentIdentity({ sentence_text_hash: "hash-2" }));
  const differentModelKey = buildSentenceExplainCacheKey(persistentIdentity({ modelName: "other-model" }));

  assert.equal(sameKey, buildSentenceExplainCacheKey(persistentIdentity()));
  assert.notEqual(sameKey, differentDocumentKey);
  assert.notEqual(sameKey, differentSentenceKey);
  assert.notEqual(sameKey, differentHashKey);
  assert.notEqual(sameKey, differentModelKey);
  assert.equal(makePersistentExplainCacheIdentity({ document_id: "", sentence_id: "sen", sentence_text_hash: "hash", modelName: TEST_MODEL_NAME }), null);
});

test("explainSentence returns persistent cached result without calling the model", () => withPersistentStore(async (store) => {
  const identity = persistentIdentity();
  const cacheKey = buildSentenceExplainCacheKey(identity);
  store.storeReady({
    ...identity,
    cache_key: cacheKey,
    request_id: "req-old",
    result: {
      ...modelResult(),
      identity: {
        client_request_id: "client-old",
        document_id: "doc-1",
        sentence_id: "sen-1",
        sentence_text_hash: "hash-1",
        anchor_label: "第1页 第1句",
        segment_id: "seg-1"
      },
      request_id: "req-old",
      used_cache: false,
      used_fallback: false,
      retry_count: 0,
      current_result_source: "remoteAI"
    }
  });

  let modelCalls = 0;
  setExplainSentenceModelInvokerForTests(async () => {
    modelCalls += 1;
    throw new Error("model should not be called");
  });

  const result = await explainSentence(explainPayload({ requestID: "req-new" }));

  assert.equal(modelCalls, 0);
  assert.equal(result.request_id, "req-new");
  assert.equal(result.used_cache, true);
  assert.equal(result.used_fallback, false);
  assert.equal(result.retry_count, 0);
  assert.equal(result.original_sentence, TEST_SENTENCE);
  assert.equal(result.current_result_source, undefined);
}));

test("explainSentence stores remoteAI success in persistent ready cache", () => withPersistentStore(async (store) => {
  const payload = explainPayload({
    requestID: "req-success",
    document_id: "doc-success",
    sentence_id: "sen-success",
    sentence_text_hash: "hash-success",
    anchor_label: "第1页 第2句",
    segment_id: "seg-success"
  });
  let modelCalls = 0;
  setExplainSentenceModelInvokerForTests(async () => {
    modelCalls += 1;
    return completionFor();
  });

  const result = await explainSentence(payload);
  const identity = persistentIdentity({
    document_id: "doc-success",
    sentence_id: "sen-success",
    sentence_text_hash: "hash-success"
  });
  const cacheKey = buildSentenceExplainCacheKey(identity);
  const cached = store.getReady(cacheKey);

  assert.ok(modelCalls >= 1);
  assert.equal(result.used_cache, false);
  assert.equal(result.used_fallback, false);
  assert.equal(cached.result.original_sentence, TEST_SENTENCE);
  assert.equal(cached.result.current_result_source, "remoteAI");
}));

test("used_fallback=true result is not stored as persistent ready cache", () => withPersistentStore(async (store) => {
  const identity = persistentIdentity();
  const cacheKey = buildSentenceExplainCacheKey(identity);

  const didStore = storePersistentExplainReadyIfEligible({
    store,
    identity,
    cacheKey,
    requestID: "req-fallback",
    result: {
      ...modelResult(),
      used_fallback: true,
      current_result_source: "requestFailed"
    }
  });

  assert.equal(didStore, false);
  assert.equal(store.getReady(cacheKey), null);
}));

test("explainSentence stores failed persistent status when model request fails", () => withPersistentStore(async (store) => {
  const payload = explainPayload({
    requestID: "req-failed",
    document_id: "doc-failed",
    sentence_id: "sen-failed",
    sentence_text_hash: "hash-failed",
    anchor_label: "第1页 第3句",
    segment_id: "seg-failed"
  });
  setExplainSentenceModelInvokerForTests(async () => {
    throw new AppError("provider failed", {
      statusCode: 502,
      code: "GEMINI_INVALID_RESPONSE",
      retryable: false,
      fallbackAvailable: true,
      requestID: "req-failed"
    });
  });

  await assert.rejects(
    () => explainSentence(payload),
    /provider failed/
  );

  const status = store.getSentenceStatus({
    document_id: "doc-failed",
    sentence_id: "sen-failed",
    sentence_text_hash: "hash-failed"
  });

  assert.equal(status.status, "failed");
  assert.equal(status.error_code, "GEMINI_INVALID_RESPONSE");
  assert.equal(status.request_id, "req-failed");
}));

test("explainSentence output keeps public contract fields after persistent cache integration", () => withPersistentStore(async () => {
  setExplainSentenceModelInvokerForTests(async () => completionFor());

  const result = await explainSentence(explainPayload({
    requestID: "req-contract",
    document_id: "doc-contract",
    sentence_id: "sen-contract",
    sentence_text_hash: "hash-contract",
    anchor_label: "第1页 第4句",
    segment_id: "seg-contract"
  }));

  assert.equal(result.original_sentence, TEST_SENTENCE);
  assert.equal(typeof result.faithful_translation, "string");
  assert.equal(typeof result.teaching_interpretation, "string");
  assert.equal(typeof result.sentence_core, "string");
  assert.equal(Array.isArray(result.grammar_focus), true);
  assert.equal(Array.isArray(result.chunk_layers), true);
  assert.equal(Array.isArray(result.misreading_traps), true);
  assert.equal(result.identity.document_id, "doc-contract");
  assert.equal(result.analysis_identity.source_sentence_id, "sen-contract");
  assert.equal(result.used_cache, false);
  assert.equal(result.used_fallback, false);
}));
