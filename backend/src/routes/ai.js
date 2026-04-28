import { Router } from "express";
import { explainSentence } from "../services/explainSentenceService.js";
import { parseSource } from "../services/parseSourceService.js";
import { analyzePassage } from "../services/analyzePassageService.js";
import { getDocumentExplainPrewarmQueue } from "../services/DocumentExplainPrewarmQueueRegistry.js";
import { validateExplainSentenceRequest } from "../validators/explainSentence.js";
import { validateParseSourceRequest } from "../validators/parseSource.js";
import { validatePrewarmDocumentRequest } from "../validators/prewarmDocument.js";
import { normalizeClientRequestID, resolveRequestID } from "../lib/requestId.js";

const router = Router();

function prewarmRequestID(req) {
  const body = typeof req.body === "object" && req.body !== null ? req.body : {};
  return resolveRequestID(body.client_request_id || req.headers["x-client-request-id"]);
}

function buildPrewarmJobPayload(job) {
  return {
    job_id: job.job_id,
    document_id: job.document_id,
    title: job.title || "",
    status: job.status,
    total_count: Number(job.total_count || 0),
    ready_count: Number(job.ready_count || 0),
    failed_count: Number(job.failed_count || 0),
    processing_count: Number(job.processing_count || 0),
    queued_count: Number(job.queued_count || 0),
    created_at: job.created_at,
    updated_at: job.updated_at
  };
}

function missingDocumentIDResponse(res, requestID) {
  return res.status(400).json({
    success: false,
    error_code: "MISSING_DOCUMENT_ID",
    message: "缺少 document_id。",
    request_id: requestID,
    retryable: false,
    fallback_available: false
  });
}

function prewarmJobNotFoundResponse(res, requestID) {
  return res.status(404).json({
    success: false,
    error_code: "PREWARM_JOB_NOT_FOUND",
    message: "该资料暂无 AI 精讲预生成任务。",
    request_id: requestID,
    retryable: false,
    fallback_available: false
  });
}

router.post("/prewarm-document", async (req, res) => {
  const requestID = prewarmRequestID(req);
  req.requestID = requestID;

  const payload = validatePrewarmDocumentRequest(req.body);
  const queue = getDocumentExplainPrewarmQueue();
  const job = queue.enqueueDocument(payload);

  return res.json({
    success: true,
    data: buildPrewarmJobPayload(job),
    request_id: requestID,
    used_cache: false,
    used_fallback: false
  });
});

router.get("/prewarm-document/latest", async (req, res) => {
  const requestID = resolveRequestID(req.headers["x-client-request-id"]);
  req.requestID = requestID;

  const documentID = typeof req.query.document_id === "string"
    ? req.query.document_id.trim()
    : "";
  if (!documentID) {
    return missingDocumentIDResponse(res, requestID);
  }

  const queue = getDocumentExplainPrewarmQueue();
  const job = queue.getLatestJobForDocument(documentID);
  if (!job) {
    return prewarmJobNotFoundResponse(res, requestID);
  }

  return res.json({
    success: true,
    data: buildPrewarmJobPayload(job),
    request_id: requestID
  });
});

router.get("/prewarm-document/:job_id", async (req, res) => {
  const requestID = resolveRequestID(req.headers["x-client-request-id"]);
  req.requestID = requestID;

  const queue = getDocumentExplainPrewarmQueue();
  const job = queue.getJobStatus(req.params.job_id);
  if (!job) {
    return prewarmJobNotFoundResponse(res, requestID);
  }

  return res.json({
    success: true,
    data: buildPrewarmJobPayload(job),
    request_id: requestID
  });
});

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
