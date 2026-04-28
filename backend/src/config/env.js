const DEFAULT_MODEL_NAME = "[次-流抗截]gemini-3.1-pro-preview-thinking";

export const AI_CACHE_DB_PATH = process.env.AI_CACHE_DB_PATH || ".data/ai-cache.sqlite3";
export const AI_PREWARM_CONCURRENCY = Number(process.env.AI_PREWARM_CONCURRENCY || 2);
export const AI_PREWARM_MAX_SENTENCES_PER_DOCUMENT = Number(
  process.env.AI_PREWARM_MAX_SENTENCES_PER_DOCUMENT || 200
);

export function getServerConfig() {
  return {
    port: Number(process.env.PORT) || 3000,
    modelName: process.env.MODEL_NAME || DEFAULT_MODEL_NAME
  };
}

export function getDashScopeConfig() {
  return {
    apiKey: process.env.DASHSCOPE_API_KEY || "",
    baseURL: process.env.DASHSCOPE_BASE_URL || "",
    modelName: process.env.MODEL_NAME || DEFAULT_MODEL_NAME
  };
}

export function hasDashScopeConfig() {
  const { apiKey, baseURL } = getDashScopeConfig();
  return Boolean(apiKey && baseURL);
}
