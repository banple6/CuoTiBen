import test from "node:test";
import assert from "node:assert/strict";

import { AppError } from "../src/lib/appError.js";
import { validatePrewarmDocumentRequest } from "../src/validators/prewarmDocument.js";

function sentence(overrides = {}) {
  return {
    sentence_id: "sen_1",
    sentence_text_hash: "hash_1",
    text: "This is a passage sentence.",
    context: "Nearby passage context.",
    anchor_label: "第1页 第1句",
    segment_id: "seg_1",
    page_index: 0,
    paragraph_role: "passageBody",
    paragraph_theme: "main idea",
    question_prompt: "",
    kind: "passageSentence",
    is_current_page: true,
    is_key_sentence: false,
    is_passage_sentence: true,
    ...overrides
  };
}

test("validatePrewarmDocumentRequest keeps passage sentences and passage body sentences", () => {
  const result = validatePrewarmDocumentRequest({
    document_id: " doc-1 ",
    title: " Demo ",
    client_request_id: " req-1 ",
    sentences: [
      sentence(),
      sentence({
        sentence_id: "sen_2",
        sentence_text_hash: "hash_2",
        kind: "unknown",
        paragraph_role: "body",
        is_passage_sentence: undefined,
        text: "This body sentence is eligible."
      }),
      sentence({
        sentence_id: "sen_3",
        sentence_text_hash: "hash_3",
        kind: "unknown",
        paragraph_role: "passageBody",
        is_passage_sentence: undefined,
        text: "This passageBody sentence is eligible."
      })
    ]
  });

  assert.equal(result.document_id, "doc-1");
  assert.equal(result.title, "Demo");
  assert.equal(result.client_request_id, "req-1");
  assert.deepEqual(result.sentences.map((item) => item.sentence_id), ["sen_1", "sen_2", "sen_3"]);
  assert.equal(result.sentences[0].is_passage_sentence, true);
});

test("validatePrewarmDocumentRequest removes duplicate sentences by id and text hash", () => {
  const result = validatePrewarmDocumentRequest({
    document_id: "doc-1",
    sentences: [
      sentence(),
      sentence({ text: "Duplicate with different text should be removed." }),
      sentence({ sentence_id: "sen_1", sentence_text_hash: "hash_2", text: "Different hash remains." })
    ]
  });

  assert.deepEqual(
    result.sentences.map((item) => `${item.sentence_id}:${item.sentence_text_hash}`),
    ["sen_1:hash_1", "sen_1:hash_2"]
  );
});

test("validatePrewarmDocumentRequest filters non-passage sentence kinds", () => {
  const result = validatePrewarmDocumentRequest({
    document_id: "doc-1",
    sentences: [
      sentence({ sentence_id: "keep", sentence_text_hash: "hash_keep" }),
      sentence({ sentence_id: "heading", sentence_text_hash: "hash_heading", kind: "heading" }),
      sentence({ sentence_id: "question", sentence_text_hash: "hash_question", kind: "question" }),
      sentence({ sentence_id: "option", sentence_text_hash: "hash_option", kind: "option" }),
      sentence({ sentence_id: "vocabulary", sentence_text_hash: "hash_vocabulary", kind: "vocabulary" }),
      sentence({ sentence_id: "chineseInstruction", sentence_text_hash: "hash_chineseInstruction", kind: "chineseInstruction" }),
      sentence({ sentence_id: "bilingualNote", sentence_text_hash: "hash_bilingualNote", kind: "bilingualNote" }),
      sentence({ sentence_id: "answerKey", sentence_text_hash: "hash_answerKey", kind: "answerKey" }),
      sentence({ sentence_id: "pageHeader", sentence_text_hash: "hash_pageHeader", kind: "pageHeader" }),
      sentence({ sentence_id: "pageFooter", sentence_text_hash: "hash_pageFooter", kind: "pageFooter" })
    ]
  });

  assert.deepEqual(result.sentences.map((item) => item.sentence_id), ["keep"]);
});

test("validatePrewarmDocumentRequest skips explicit non-passage sentences", () => {
  const result = validatePrewarmDocumentRequest({
    document_id: "doc-1",
    sentences: [
      sentence({ sentence_id: "sen_false", sentence_text_hash: "hash_false", is_passage_sentence: false }),
      sentence({ sentence_id: "sen_true", sentence_text_hash: "hash_true", is_passage_sentence: true })
    ]
  });

  assert.deepEqual(result.sentences.map((item) => item.sentence_id), ["sen_true"]);
});

test("validatePrewarmDocumentRequest rejects missing document_id", () => {
  assert.throws(
    () => validatePrewarmDocumentRequest({ sentences: [sentence()] }),
    (error) => error instanceof AppError
      && error.statusCode === 400
      && error.code === "INVALID_PREWARM_DOCUMENT_REQUEST"
  );
});

test("validatePrewarmDocumentRequest rejects when all sentences are filtered", () => {
  assert.throws(
    () => validatePrewarmDocumentRequest({
      document_id: "doc-1",
      sentences: [
        sentence({ kind: "heading" }),
        sentence({ sentence_id: "q1", sentence_text_hash: "hash_q1", kind: "question" })
      ]
    }),
    (error) => error instanceof AppError
      && error.statusCode === 400
      && error.code === "INVALID_PREWARM_DOCUMENT_REQUEST"
  );
});

test("validatePrewarmDocumentRequest skips sentences missing id, hash, or text", () => {
  const result = validatePrewarmDocumentRequest({
    document_id: "doc-1",
    sentences: [
      sentence({ sentence_id: "" }),
      sentence({ sentence_id: "missing_hash", sentence_text_hash: "" }),
      sentence({ sentence_id: "missing_text", sentence_text_hash: "hash_missing_text", text: "" }),
      sentence({ sentence_id: "valid", sentence_text_hash: "hash_valid", text: "Valid passage sentence." })
    ]
  });

  assert.deepEqual(result.sentences.map((item) => item.sentence_id), ["valid"]);
});
