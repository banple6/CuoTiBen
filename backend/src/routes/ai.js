import crypto from "crypto";
import { Router } from "express";
import { explainSentence } from "../services/explainSentenceService.js";
import { parseSource } from "../services/parseSourceService.js";
import { analyzePassage } from "../services/analyzePassageService.js";
import { validateExplainSentenceRequest } from "../validators/explainSentence.js";
import { validateAnalyzePassageRequest } from "../validators/analyzePassage.js";
import { validateParseSourceRequest } from "../validators/parseSource.js";
import { createModelRegistry } from "../models/modelRegistry.js";
import { createAIError, attachAIErrorMetadata, ERROR_CODES } from "../models/errors.js";

const router = Router();
const modelRegistry = createModelRegistry();

function ensureRequestId(req) {
  if (typeof req.requestId === "string" && req.requestId.trim()) {
    return req.requestId;
  }

  const candidate = typeof req.get === "function" ? req.get("x-request-id") : "";
  const requestId = candidate?.trim() || crypto.randomUUID();
  req.requestId = requestId;
  return requestId;
}

function runAIPreflight(req, routeName) {
  const requestId = ensureRequestId(req);

  try {
    modelRegistry.preflight();
  } catch (error) {
    throw attachAIErrorMetadata(
      error?.code
        ? error
        : createAIError(ERROR_CODES.MODEL_CONFIG_MISSING, {
          fallbackAvailable: true
        }),
      {
        requestId,
        routeName,
        fallbackAvailable: true
      }
    );
  }

  return requestId;
}

router.post("/explain-sentence", async (req, res) => {
  const requestId = ensureRequestId(req);
  const payload = validateExplainSentenceRequest(req.body);
  runAIPreflight(req, "ai/explain-sentence");

  console.log("[ai/explain-sentence] request", {
    requestId,
    sentenceId: payload.identity.sentence_id,
    title: payload.title || "",
    sentenceLength: payload.sentence.length,
    contextLength: payload.context.length
  });

  const result = await explainSentence(payload, { requestId });

  console.log("[ai/explain-sentence] success");

  return res.json({
    success: true,
    request_id: requestId,
    data: result.data,
    meta: result.meta
  });
});

router.post("/parse-source", async (req, res) => {
  const requestId = runAIPreflight(req, "ai/parse-source");
  const payload = validateParseSourceRequest(req.body);

  console.log("[ai/parse-source] request", {
    requestId,
    sourceId: payload.source_id || "",
    title: payload.title || "",
    rawTextLength: payload.raw_text.length,
    anchorCount: payload.anchors.length
  });

  const data = await parseSource(payload);

  return res.json({
    success: true,
    request_id: requestId,
    data
  });
});

// ─── 教授级全文教学分析 ───

router.post("/analyze-passage", async (req, res) => {
  const requestId = ensureRequestId(req);
  const payload = validateAnalyzePassageRequest(req.body);
  runAIPreflight(req, "ai/analyze-passage");

  console.log("[ai/analyze-passage] request", {
    requestId,
    documentId: payload.identity.document_id,
    title: payload.title,
    paragraphCount: payload.paragraphs.length
  });

  const result = await analyzePassage(payload, { requestId });

  console.log("[ai/analyze-passage] success", {
    requestId,
    paragraphCards: result.data.paragraph_cards.length,
    usedFallback: result.meta.used_fallback
  });

  return res.json({
    success: true,
    request_id: requestId,
    data: result.data,
    meta: result.meta
  });
});

export default router;
