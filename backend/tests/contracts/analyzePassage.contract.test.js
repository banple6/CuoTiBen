import test from "node:test";
import assert from "node:assert/strict";

import { analyzePassage } from "../../src/services/analyzePassageService.js";

function createPayload(overrides = {}) {
  return {
    identity: {
      client_request_id: "client-passage-1",
      document_id: "document-1",
      content_hash: "content-hash-1"
    },
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
      },
      {
        segment_id: "q-1",
        index: 2,
        anchor_label: "Q1",
        text: "Which paragraph best shows the shift from review to reform?",
        source_kind: "question",
        hygiene_score: 0.88
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

function createAIClientReturning(rawResultOrFactory, metaOverrides = {}) {
  const calls = [];

  return {
    calls,
    async request(input) {
      calls.push(input);
      const rawResult = typeof rawResultOrFactory === "function"
        ? rawResultOrFactory({ input, callIndex: calls.length - 1 })
        : rawResultOrFactory;

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

function assertPublicMeta(meta) {
  assert.equal(typeof meta.provider, "string");
  assert.equal(typeof meta.model, "string");
  assert.equal(typeof meta.retry_count, "number");
  assert.equal(typeof meta.used_cache, "boolean");
  assert.equal(typeof meta.used_fallback, "boolean");
  assert.equal(typeof meta.circuit_state, "string");
}

test("analyzePassage returns the new map-level contract and filters non-passage_body cards", async () => {
  const payload = createPayload();
  const aiClient = createAIClientReturning({
    passage_overview: {
      article_theme: "文章围绕灾后治理是否真正转向长期改革展开。",
      author_core_question: "作者真正关心的是灾后复盘能否转化为制度改革。",
      progression_path: "先回顾灾后复盘，再推进到预警改革，最后落在制度调整。",
      likely_question_types: ["主旨题：作者真正关心的治理问题是什么"],
      logic_pitfalls: ["容易把复盘细节误当成作者最终判断"]
    },
    paragraph_cards: [
      {
        segment_id: "seg-1",
        paragraph_index: 0,
        anchor_label: "P1",
        theme: "第一段先交代官方复盘的起点。",
        argument_role: "background",
        core_sentence_id: "seg-1::s1",
        relation_to_previous: "首段建立讨论背景。",
        exam_value: "常对应主旨铺垫或细节定位。",
        teaching_focuses: ["先看官方复盘在全文里只是起点，不是结论。"],
        student_blind_spot: "容易把复盘动作直接当成改革结论。",
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
        theme: "第二段把重心推进到治理改革。",
        argument_role: "support",
        core_sentence_id: "seg-2::s1",
        relation_to_previous: "在背景之后进一步推进作者真正关心的问题。",
        exam_value: "常对应段落作用题或作者意图题。",
        teaching_focuses: ["先盯 however 后的推进方向。"],
        student_blind_spot: "容易只记居民观点，不看它推动了全文判断。",
        provenance: {
          source_segment_id: "seg-2",
          source_sentence_id: "seg-2::s1",
          source_kind: "passage_body",
          generated_from: "ai_passage_analysis",
          hygiene_score: 0.9,
          consistency_score: 0.9
        }
      },
      {
        segment_id: "q-1",
        paragraph_index: 2,
        anchor_label: "Q1",
        theme: "这是一道题目。",
        argument_role: "support",
        core_sentence_id: "q-1::s1",
        relation_to_previous: "无",
        exam_value: "不该进入主导图。",
        teaching_focuses: ["这是题目辅助层。"],
        student_blind_spot: "会把题目误当正文。",
        provenance: {
          source_segment_id: "q-1",
          source_sentence_id: "q-1::s1",
          source_kind: "question",
          generated_from: "ai_passage_analysis",
          hygiene_score: 0.88,
          consistency_score: 0.4
        }
      }
    ],
    key_sentence_ids: [
      "seg-1::s1",
      "seg-2::s1",
      "seg-1::s1",
      "seg-2::s1",
      "seg-1::s1",
      "seg-2::s1",
      "seg-1::s1"
    ],
    question_links: [
      {
        source_kind: "question",
        linked_segment_id: "seg-2",
        summary: "题目会把第二段改写成改革方向题。"
      }
    ]
  });

  const result = await analyzePassage(payload, {
    requestId: "req-passage-1",
    aiClient
  });

  assert.ok(result.data.passage_overview);
  assert.ok(Array.isArray(result.data.paragraph_cards));
  assert.ok(Array.isArray(result.data.key_sentence_ids));
  assert.ok(Array.isArray(result.data.question_links));
  assert.equal(result.data.paragraph_cards.length, 2);
  assert.deepEqual(result.data.paragraph_cards.map((card) => card.segment_id), ["seg-1", "seg-2"]);
  assert.ok(result.data.paragraph_cards.every((card) => card.provenance.source_kind === "passage_body"));
  assert.ok(result.data.key_sentence_ids.length <= 6);
  assertPublicMeta(result.meta);

  const allKeys = collectKeys(result.data);
  for (const forbidden of [
    "grammar_focus",
    "faithful_translation",
    "teaching_interpretation",
    "core_skeleton",
    "chunk_layers",
    "sentence_function",
    "simpler_rewrite",
    "simpler_rewrite_translation",
    "mini_check",
    "sentence_core",
    "translation",
    "main_structure",
    "rewrite_example"
  ]) {
    assert.equal(allKeys.includes(forbidden), false, `unexpected field ${forbidden}`);
  }
});

test("analyzePassage repairs one contract-invalid response before returning the map contract", async () => {
  const payload = createPayload();
  const aiClient = createAIClientReturning(({ callIndex }) => {
    if (callIndex === 0) {
      return {
        passage_overview: {
          article_theme: "",
          author_core_question: "",
          progression_path: "",
          likely_question_types: [],
          logic_pitfalls: []
        },
        paragraph_cards: [
          {
            segment_id: "missing-segment",
            paragraph_index: 0,
            anchor_label: "P1",
            theme: "Bad card",
            argument_role: "support",
            core_sentence_id: "missing-segment::s1",
            relation_to_previous: "",
            exam_value: "",
            teaching_focuses: [],
            student_blind_spot: "",
            provenance: {
              source_segment_id: "missing-segment",
              source_sentence_id: "missing-segment::s1",
              source_kind: "passage_body",
              generated_from: "ai_passage_analysis",
              hygiene_score: 0.9,
              consistency_score: 0.2
            }
          }
        ],
        key_sentence_ids: [],
        question_links: []
      };
    }

    return {
      passage_overview: {
        article_theme: "文章围绕灾后治理与改革推进展开。",
        author_core_question: "作者追问复盘能否推动真正改革。",
        progression_path: "先讲复盘，再讲改革需求，最后聚焦预警调整。",
        likely_question_types: ["主旨题：作者核心关切"],
        logic_pitfalls: ["容易把背景段误认成结论段"]
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
          exam_value: "先确定背景与结论的边界。",
          teaching_focuses: ["先把第一段当背景，不要抢结论。"],
          student_blind_spot: "会把背景说明错看成作者主张。",
          provenance: {
            source_segment_id: "seg-1",
            source_sentence_id: "seg-1::s1",
            source_kind: "passage_body",
            generated_from: "ai_passage_analysis",
            hygiene_score: 0.92,
          consistency_score: 0.9
        }
      },
      {
        segment_id: "seg-2",
        paragraph_index: 1,
        anchor_label: "P2",
        theme: "第二段把焦点推进到改革是否真正落地。",
        argument_role: "support",
        core_sentence_id: "seg-2::s1",
        relation_to_previous: "在背景之后继续推进全文真正关心的判断。",
        exam_value: "常对应作者意图或段落功能题。",
        teaching_focuses: ["先看第二段怎样把讨论从复盘推到改革。"],
        student_blind_spot: "容易把居民声音只看成细节，不看它如何推进论证。",
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
      question_links: []
    };
  });

  const result = await analyzePassage(payload, {
    requestId: "req-passage-2",
    aiClient
  });

  assert.equal(aiClient.calls.length, 2);
  assert.equal(result.data.paragraph_cards[0].segment_id, "seg-1");
  assert.equal(result.meta.used_fallback, false);
});

test("analyzePassage falls back to a passage map skeleton when repair still fails", async () => {
  const payload = createPayload();
  const aiClient = createAIClientReturning(({ callIndex }) => ({
    passage_overview: {
      article_theme: callIndex === 0 ? "" : "",
      author_core_question: "",
      progression_path: "",
      likely_question_types: [],
      logic_pitfalls: []
    },
    paragraph_cards: [
      {
        segment_id: "q-1",
        paragraph_index: 2,
        anchor_label: "Q1",
        theme: "题目内容",
        argument_role: "support",
        core_sentence_id: "q-1::s1",
        relation_to_previous: "",
        exam_value: "",
        teaching_focuses: [],
        student_blind_spot: "",
        provenance: {
          source_segment_id: "q-1",
          source_sentence_id: "q-1::s1",
          source_kind: "question",
          generated_from: "ai_passage_analysis",
          hygiene_score: 0.88,
          consistency_score: 0.2
        }
      }
    ],
    key_sentence_ids: [],
    question_links: []
  }));

  const result = await analyzePassage(payload, {
    requestId: "req-passage-3",
    aiClient
  });

  assert.equal(aiClient.calls.length, 2);
  assert.equal(result.meta.used_fallback, true);
  assert.ok(result.data.passage_overview);
  assert.ok(result.data.paragraph_cards.length > 0);
  assert.ok(Array.isArray(result.data.key_sentence_ids));
  assert.ok(Array.isArray(result.data.question_links));
  assert.ok(result.data.paragraph_cards.every((card) => card.provenance.source_kind === "passage_body"));
});
