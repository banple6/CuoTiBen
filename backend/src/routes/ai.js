import { Router } from "express";
import { explainSentence } from "../services/explainSentenceService.js";
import { parseSource } from "../services/parseSourceService.js";
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

export default router;
