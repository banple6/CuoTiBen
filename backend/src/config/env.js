const DEFAULT_MODEL_NAME = "[次-流抗截]gemini-3.1-pro-preview-thinking";

export const AI_CACHE_DB_PATH = process.env.AI_CACHE_DB_PATH || ".data/ai-cache.sqlite3";
export const AI_PREWARM_CONCURRENCY = Number(process.env.AI_PREWARM_CONCURRENCY || 2);
export const AI_PREWARM_MAX_SENTENCES_PER_DOCUMENT = Number(
  process.env.AI_PREWARM_MAX_SENTENCES_PER_DOCUMENT || 200
);

export function getServerConfig() {
  return {
    port: Number(process.env.PORT) || 3000,
    modelName: getEffectiveExplainModelName()
  };
}

export function getEffectiveExplainModelName() {
  return process.env.MODEL_NAME || process.env.AI_MODEL || DEFAULT_MODEL_NAME;
}

export function getAIProviderConfig() {
  return {
    provider: process.env.AI_PROVIDER || "",
    apiKind: process.env.AI_API_KIND || "openai-chat-completions",
    apiKey: process.env["NOVAI" + "_API_KEY"] || process.env.DASHSCOPE_API_KEY || "",
    baseURL: process.env.AI_BASE_URL || process.env.DASHSCOPE_BASE_URL || "",
    modelName: getEffectiveExplainModelName()
  };
}

export function getDashScopeConfig() {
  return {
    apiKey: process.env.DASHSCOPE_API_KEY || process.env["NOVAI" + "_API_KEY"] || "",
    baseURL: process.env.DASHSCOPE_BASE_URL || process.env.AI_BASE_URL || "",
    modelName: getEffectiveExplainModelName()
  };
}

export function hasDashScopeConfig() {
  const { apiKey, baseURL } = getDashScopeConfig();
  return Boolean(apiKey && baseURL);
}
