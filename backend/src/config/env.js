const DEFAULT_MODEL_NAME = "[次-流抗截]gemini-3.1-pro-preview-thinking";

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
