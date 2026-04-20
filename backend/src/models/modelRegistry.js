import { getAIConfig } from "../config/env.js";
import { createClaudeProvider } from "./providers/claudeProvider.js";
import { createAIError, ERROR_CODES } from "./errors.js";

const DEFAULT_PROVIDER_FACTORIES = {
  claude: ({ config, transport }) => createClaudeProvider({ config, transport })
};

export function createModelRegistry({
  getConfig = getAIConfig,
  providerFactories = DEFAULT_PROVIDER_FACTORIES,
  transport
} = {}) {
  function resolveActiveModel() {
    const config = getConfig();
    const provider = String(config.provider || "").trim().toLowerCase();
    const providerFactory = providerFactories[provider];

    if (!providerFactory) {
      throw createAIError(ERROR_CODES.MODEL_CONFIG_MISSING, {
        message: "AI provider 配置缺失或不受支持。",
        fallbackAvailable: true
      });
    }

    const activeModel = {
      provider,
      model: String(config.model || "").trim(),
      apiKey: String(config.apiKey || "").trim(),
      baseUrl: String(config.baseUrl || "").trim(),
      apiKind: String(config.apiKind || "").trim(),
      timeoutMs: Number(config.timeoutMs) || 30000,
      maxRetries: Number(config.maxRetries) || 3,
      circuitBreakerEnabled: Boolean(config.circuitBreakerEnabled)
    };

    return {
      ...activeModel,
      providerClient: providerFactory({
        config: activeModel,
        transport
      })
    };
  }

  function preflight() {
    const activeModel = resolveActiveModel();
    const missing = [];

    if (!activeModel.apiKey) {
      missing.push("NOVAI_API_KEY");
    }
    if (!activeModel.provider) {
      missing.push("AI_PROVIDER");
    }
    if (!activeModel.model) {
      missing.push("AI_MODEL");
    }
    if (!activeModel.baseUrl) {
      missing.push("AI_BASE_URL");
    }
    if (!activeModel.apiKind) {
      missing.push("AI_API_KIND");
    }

    if (missing.length > 0) {
      throw createAIError(ERROR_CODES.MODEL_CONFIG_MISSING, {
        message: `AI 配置缺失，无法请求模型。缺少：${missing.join(", ")}`,
        fallbackAvailable: true
      });
    }

    return activeModel;
  }

  return {
    resolveActiveModel,
    preflight
  };
}
