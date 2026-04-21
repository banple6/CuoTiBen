import { Router } from "express";
import { explainSentence } from "../services/explainSentenceService.js";
import { parseSource } from "../services/parseSourceService.js";
import { analyzePassage } from "../services/analyzePassageService.js";
import { validateExplainSentenceRequest } from "../validators/explainSentence.js";
import { validateParseSourceRequest } from "../validators/parseSource.js";
import { normalizeClientRequestID, resolveRequestID } from "../lib/requestId.js";

const router = Router();

router.post("/explain-sentence", async (req, res) => {
  const payload = validateExplainSentenceRequest(req.body);
  const requestID = resolveRequestID(
    payload.client_request_id || req.headers["x-client-request-id"]
  );
  req.requestID = requestID;

  console.log("[ai/explain-sentence] request", {
    title: payload.title || "",
    sentenceLength: payload.sentence.length,
    contextLength: payload.context.length,
    requestID
  });

  const data = await explainSentence({
    ...payload,
    requestID
  });

  console.log("[ai/explain-sentence] success");

  return res.json({
    success: true,
    data,
    request_id: requestID,
    retryable: false,
    fallback_available: false,
    used_cache: Boolean(data?.used_cache),
    used_fallback: Boolean(data?.used_fallback),
    retry_count: Number(data?.retry_count || 0)
  });
});

router.post("/parse-source", async (req, res) => {
  const payload = validateParseSourceRequest(req.body);

  console.log("[ai/parse-source] request", {
    sourceId: payload.source_id || "",
    title: payload.title || "",
    rawTextLength: payload.raw_text.length,
    anchorCount: payload.anchors.length
  });

  const data = await parseSource(payload);

  return res.json({
    success: true,
    data
  });
});

// ─── 教授级全文教学分析 ───

router.post("/analyze-passage", async (req, res) => {
  const body = req.body ?? {};
  const clientRequestID = normalizeClientRequestID(
    body.client_request_id || req.headers["x-client-request-id"]
  );
  const requestID = resolveRequestID(clientRequestID);
  req.requestID = requestID;

  const title = typeof body.title === "string" ? body.title.trim() : "";
  const paragraphs = Array.isArray(body.paragraphs) ? body.paragraphs : [];
  const keySentences = Array.isArray(body.key_sentences) ? body.key_sentences : [];

  if (paragraphs.length === 0) {
    return res.status(400).json({
      success: false,
      error_code: "MISSING_PARAGRAPHS",
      message: "paragraphs 不能为空。",
      request_id: requestID,
      retryable: false,
      fallback_available: false,
      used_cache: false,
      used_fallback: false,
      retry_count: 0
    });
  }

  const validParagraphs = paragraphs
    .filter((p) => typeof p?.text === "string" && p.text.trim().length >= 5)
    .map((p, i) => ({
      index: typeof p.index === "number" ? p.index : i,
      text: p.text.trim()
    }));

  const validSentences = keySentences
    .filter((s) => typeof s?.text === "string" && typeof s?.ref === "string")
    .map((s) => ({
      ref: s.ref.trim(),
      text: s.text.trim(),
      paragraphIndex: typeof s.paragraph_index === "number" ? s.paragraph_index : 0
    }));

  console.log("[ai/analyze-passage] request", {
    title,
    paragraphCount: validParagraphs.length,
    keySentenceCount: validSentences.length,
    requestID
  });

  const data = await analyzePassage({
    requestID,
    title,
    paragraphs: validParagraphs,
    keySentences: validSentences
  });

  console.log("[ai/analyze-passage] success", {
    elapsed_ms: data.elapsed_ms,
    paragraphCards: data.paragraph_cards.length,
    keySentenceRefs: data.key_sentence_refs?.length ?? 0,
    requestID
  });

  return res.json({
    success: true,
    data,
    request_id: requestID,
    retryable: false,
    fallback_available: false,
    used_cache: Boolean(data?.used_cache),
    used_fallback: Boolean(data?.used_fallback),
    retry_count: Number(data?.retry_count || 0)
  });
});

export default router;
