import { Router } from "express";
import { getAIConfig, hasAIConfig } from "../config/env.js";

const router = Router();

router.get("/", (_req, res) => {
  const aiConfig = getAIConfig();
  const gatewayStatus = _req.app?.locals?.aiGatewayStatus;

  res.json({
    ok: true,
    service: "cuotiben-backend",
    timestamp: new Date().toISOString(),
    node: process.version,
    ai_gateway: {
      configured: hasAIConfig(),
      provider: aiConfig.provider,
      model: aiConfig.model,
      api_kind: aiConfig.apiKind,
      timeout_ms: aiConfig.timeoutMs,
      max_retries: aiConfig.maxRetries,
      circuit_breaker_enabled: aiConfig.circuitBreakerEnabled,
      circuit_state: gatewayStatus?.circuitState || "closed"
    }
  });
});

export default router;
