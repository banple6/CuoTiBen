import { Router } from "express";
import { explainSentence } from "../services/explainSentenceService.js";
import { parseSource } from "../services/parseSourceService.js";
import { analyzePassage } from "../services/analyzePassageService.js";
import { validateExplainSentenceRequest } from "../validators/explainSentence.js";
import { validateParseSourceRequest } from "../validators/parseSource.js";

const router = Router();

router.post("/explain-sentence", async (req, res) => {
  const payload = validateExplainSentenceRequest(req.body);

  console.log("[ai/explain-sentence] request", {
    title: payload.title || "",
    sentenceLength: payload.sentence.length,
    contextLength: payload.context.length
  });

  const data = await explainSentence(payload);

  console.log("[ai/explain-sentence] success");

  return res.json({
    success: true,
    data
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

  const title = typeof body.title === "string" ? body.title.trim() : "";
  const paragraphs = Array.isArray(body.paragraphs) ? body.paragraphs : [];
  const keySentences = Array.isArray(body.key_sentences) ? body.key_sentences : [];

  if (paragraphs.length === 0) {
    return res.status(400).json({
      success: false,
      error: { code: "MISSING_PARAGRAPHS", message: "paragraphs 不能为空。" }
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
    keySentenceCount: validSentences.length
  });

  const data = await analyzePassage({
    title,
    paragraphs: validParagraphs,
    keySentences: validSentences
  });

  console.log("[ai/analyze-passage] success", {
    elapsed_ms: data.elapsed_ms,
    paragraphCards: data.paragraph_cards.length,
    sentenceAnalyses: data.sentence_analyses.length
  });

  return res.json({
    success: true,
    data
  });
});

export default router;
