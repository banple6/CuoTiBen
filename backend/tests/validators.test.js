import test from "node:test";
import assert from "node:assert/strict";

import { AppError } from "../src/lib/appError.js";
import { validateExplainSentenceRequest } from "../src/validators/explainSentence.js";
import { validateParseSourceRequest } from "../src/validators/parseSource.js";

test("validateExplainSentenceRequest trims strings and preserves optional defaults", () => {
  const result = validateExplainSentenceRequest({
    client_request_id: "  client-1  ",
    document_id: "  document-1  ",
    sentence_id: "  sentence-1  ",
    segment_id: "  segment-1  ",
    sentence_text_hash: "  hash-1  ",
    anchor_label: "  Anchor A  ",
    title: "  Lesson Title  ",
    sentence: "  This is the target sentence.  ",
    context: "  Context here.  ",
    paragraph_theme: "  Theme  ",
    paragraph_role: "  support  ",
    question_prompt: "  Why is this important?  "
  });

  assert.deepEqual(result, {
    identity: {
      client_request_id: "client-1",
      document_id: "document-1",
      sentence_id: "sentence-1",
      segment_id: "segment-1",
      sentence_text_hash: "hash-1",
      anchor_label: "Anchor A"
    },
    title: "Lesson Title",
    sentence: "This is the target sentence.",
    context: "Context here.",
    paragraph_theme: "Theme",
    paragraph_role: "support",
    question_prompt: "Why is this important?"
  });
});

test("validateExplainSentenceRequest rejects missing sentence", () => {
  assert.throws(
    () => validateExplainSentenceRequest({
      client_request_id: "client-1",
      document_id: "document-1",
      sentence_id: "sentence-1",
      segment_id: "segment-1",
      sentence_text_hash: "hash-1",
      anchor_label: "Anchor A",
      title: "Only title"
    }),
    (error) => error instanceof AppError && error.message === "sentence 不能为空。"
  );
});

test("validateExplainSentenceRequest rejects missing sentence identity", () => {
  assert.throws(
    () => validateExplainSentenceRequest({
      title: "Lesson Title",
      sentence: "This is the target sentence."
    }),
    (error) => error instanceof AppError && error.code === "INVALID_REQUEST" && error.message === "缺少 sentence identity 字段。"
  );
});

test("validateParseSourceRequest trims input and applies anchor defaults", () => {
  const result = validateParseSourceRequest({
    source_id: "  source-1  ",
    title: "  Reading 1  ",
    source_type: "  pdf  ",
    raw_text: "  Example passage  ",
    anchors: [
      {
        label: "  P1  ",
        text: "  Anchor text  "
      }
    ]
  });

  assert.deepEqual(result, {
    source_id: "source-1",
    title: "Reading 1",
    source_type: "pdf",
    raw_text: "Example passage",
    page_count: null,
    anchors: [
      {
        anchor_id: "anchor_1",
        page: null,
        label: "P1",
        text: "Anchor text"
      }
    ]
  });
});

test("validateParseSourceRequest rejects invalid page_count", () => {
  assert.throws(
    () => validateParseSourceRequest({ raw_text: "text", page_count: -1 }),
    (error) => error instanceof AppError && error.message === "page_count 必须是非负整数。"
  );
});

test("validateParseSourceRequest rejects non-object anchors", () => {
  assert.throws(
    () => validateParseSourceRequest({ raw_text: "text", anchors: ["bad"] }),
    (error) => error instanceof AppError && error.message === "anchors[0] 必须是对象。"
  );
});
