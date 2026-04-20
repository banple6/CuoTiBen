const DEFAULT_MODEL_NAME = "[次-流抗截]gemini-3.1-pro-preview-thinking";
const DEFAULT_AI_PROVIDER = "claude";
const DEFAULT_AI_API_KIND = "anthropic-messages";
const DEFAULT_AI_TIMEOUT_MS = 30000;
const DEFAULT_AI_MAX_RETRIES = 3;

function parsePositiveInteger(value, fallback) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return fallback;
  }

  return Math.floor(parsed);
}

function parseBoolean(value, fallback) {
  if (value === undefined || value === null || value === "") {
    return fallback;
  }

  if (typeof value === "boolean") {
    return value;
  }

  const normalized = String(value).trim().toLowerCase();
  if (normalized === "true") {
    return true;
  }
  if (normalized === "false") {
    return false;
  }

  return fallback;
}

export function getServerConfig() {
  return {
    port: Number(process.env.PORT) || 3000,
    modelName: process.env.MODEL_NAME || process.env.AI_MODEL || DEFAULT_MODEL_NAME
  };
}

export function getAIConfig() {
  return {
    apiKey: process.env.NOVAI_API_KEY || "",
    provider: process.env.AI_PROVIDER || DEFAULT_AI_PROVIDER,
    model: process.env.AI_MODEL || process.env.MODEL_NAME || DEFAULT_MODEL_NAME,
    baseUrl: process.env.AI_BASE_URL || "",
    apiKind: process.env.AI_API_KIND || DEFAULT_AI_API_KIND,
    timeoutMs: parsePositiveInteger(process.env.AI_TIMEOUT_MS, DEFAULT_AI_TIMEOUT_MS),
    maxRetries: parsePositiveInteger(process.env.AI_MAX_RETRIES, DEFAULT_AI_MAX_RETRIES),
    circuitBreakerEnabled: parseBoolean(process.env.AI_CIRCUIT_BREAKER_ENABLED, true)
  };
}

export function hasAIConfig() {
  const config = getAIConfig();
  return Boolean(config.apiKey && config.provider && config.model && config.baseUrl && config.apiKind);
}

// Legacy exports kept for existing services. They now fall back to the new AI config
// so current service imports do not break during the gateway transition.
export function getDashScopeConfig() {
  const aiConfig = getAIConfig();
  return {
    apiKey: process.env.DASHSCOPE_API_KEY || aiConfig.apiKey || "",
    baseURL: process.env.DASHSCOPE_BASE_URL || aiConfig.baseUrl || "",
    modelName: process.env.MODEL_NAME || aiConfig.model || DEFAULT_MODEL_NAME
  };
}

export function hasDashScopeConfig() {
  const { apiKey, baseURL } = getDashScopeConfig();
  return Boolean(apiKey && baseURL);
}
