import test from "node:test";
import assert from "node:assert/strict";

import { __testables } from "../src/services/analyzePassageService.js";

const {
  normalizeAnalyzePassageContract,
  validateAnalyzePassageContract,
  buildAnalyzePassageFallbackSkeleton,
  splitIntoSentences,
  inferArgumentRole
} = __testables;

function createPayload() {
  return {
    identity: {
      client_request_id: "client-passage-service-1",
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
    answer_blocks: [],
    vocabulary_blocks: []
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

test("normalizeAnalyzePassageContract strips forbidden sentence-level fields and keeps only passage_body cards", () => {
  const result = normalizeAnalyzePassageContract({
    passage_overview: {
      article_theme: "文章围绕灾后治理与改革推进展开。",
      author_core_question: "作者真正关心复盘能否转成改革。",
      progression_path: "先讲复盘，再讲改革。",
      likely_question_types: ["主旨题：作者关切"],
      logic_pitfalls: ["容易把背景误判成结论"]
    },
    paragraph_cards: [
      {
        segment_id: "seg-1",
        paragraph_index: 0,
        anchor_label: "P1",
        theme: "第一段先交代背景。",
        argument_role: "background",
        core_sentence_id: "seg-1::s1",
        relation_to_previous: "首段建立背景。",
        exam_value: "先定位背景作用。",
        teaching_focuses: ["先看背景，不要先抢结论。"],
        student_blind_spot: "容易把背景当主张。",
        grammar_focus: [{ title_zh: "不该出现" }],
        faithful_translation: "不该出现",
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
        segment_id: "q-1",
        paragraph_index: 2,
        anchor_label: "Q1",
        theme: "题目块不该进入主线。",
        argument_role: "support",
        core_sentence_id: "q-1::s1",
        relation_to_previous: "无",
        exam_value: "无",
        teaching_focuses: [],
        student_blind_spot: "无",
        provenance: {
          source_segment_id: "q-1",
          source_sentence_id: "q-1::s1",
          source_kind: "question",
          generated_from: "ai_passage_analysis",
          hygiene_score: 0.88,
          consistency_score: 0.3
        }
      }
    ],
    key_sentence_ids: ["seg-1::s1", "seg-2::s1", "seg-1::s1"],
    question_links: []
  }, createPayload());

  assert.equal(result.paragraph_cards.length, 1);
  assert.equal(result.paragraph_cards[0].segment_id, "seg-1");

  const keys = collectKeys(result);
  for (const forbidden of ["grammar_focus", "faithful_translation", "teaching_interpretation", "core_skeleton", "chunk_layers"]) {
    assert.equal(keys.includes(forbidden), false, `unexpected field ${forbidden}`);
  }
});

test("validateAnalyzePassageContract flags missing map-level coverage and invalid provenance", () => {
  const payload = createPayload();
  const badData = {
    passage_overview: {
      article_theme: "",
      author_core_question: "",
      progression_path: "",
      likely_question_types: [],
      logic_pitfalls: []
    },
    paragraph_cards: [
      {
        segment_id: "seg-1",
        paragraph_index: 0,
        anchor_label: "P1",
        theme: "Not chinese",
        argument_role: "background",
        core_sentence_id: "seg-1::bad",
        relation_to_previous: "Not chinese",
        exam_value: "Not chinese",
        teaching_focuses: ["Not chinese"],
        student_blind_spot: "Not chinese",
        provenance: {
          source_segment_id: "seg-2",
          source_sentence_id: "seg-1::bad",
          source_kind: "question",
          generated_from: "ai_passage_analysis",
          hygiene_score: 0.92,
          consistency_score: 0.1
        }
      }
    ],
    key_sentence_ids: ["seg-1::bad"],
    question_links: []
  };

  const reasons = validateAnalyzePassageContract(badData, payload);

  assert.ok(reasons.includes("overview.article_theme"));
  assert.ok(reasons.includes("invalid_core_sentence:seg-1"));
  assert.ok(reasons.includes("invalid_source_kind:seg-1"));
  assert.ok(reasons.includes("missing_paragraph_cards"));
});

test("buildAnalyzePassageFallbackSkeleton returns a renderable passage map skeleton", () => {
  const result = buildAnalyzePassageFallbackSkeleton(createPayload());

  assert.ok(result.passage_overview.article_theme.length > 0);
  assert.equal(result.paragraph_cards.length, 2);
  assert.ok(result.paragraph_cards.every((card) => card.provenance.source_kind === "passage_body"));
  assert.ok(result.key_sentence_ids.length <= 6);
  assert.ok(Array.isArray(result.question_links));
});

test("splitIntoSentences and inferArgumentRole provide stable local heuristics", () => {
  const sentences = splitIntoSentences("However, residents argued for reform. Officials then revised the warning system.");
  assert.equal(sentences.length, 2);
  assert.equal(inferArgumentRole("However, residents argued for reform.", 1, 2), "transition");
});
