import test from "node:test";
import assert from "node:assert/strict";

import { AppError } from "../src/lib/appError.js";
import { validateExplainSentenceRequest } from "../src/validators/explainSentence.js";
import { validateParseSourceRequest } from "../src/validators/parseSource.js";

test("validateExplainSentenceRequest trims strings and preserves optional defaults", () => {
  const result = validateExplainSentenceRequest({
    title: "  Lesson Title  ",
    sentence: "  This is the target sentence.  ",
    context: "  Context here.  ",
    paragraph_theme: "  Theme  ",
    paragraph_role: "  support  ",
    question_prompt: "  Why is this important?  "
  });

  assert.deepEqual(result, {
    title: "Lesson Title",
    sentence: "This is the target sentence.",
    context: "Context here.",
    paragraph_theme: "Theme",
    paragraph_role: "support",
    question_prompt: "Why is this important?",
    sentence_id: "",
    sentence_text_hash: "",
    anchor_label: "",
    segment_id: "",
    client_request_id: ""
  });
});

test("validateExplainSentenceRequest rejects missing sentence", () => {
  assert.throws(
    () => validateExplainSentenceRequest({ title: "Only title" }),
    (error) => error instanceof AppError && error.message === "sentence 不能为空。"
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
