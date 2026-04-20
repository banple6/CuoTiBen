import { createAIError, ERROR_CODES, mapUpstreamStatusToErrorCode } from "../errors.js";

function joinUrl(baseUrl, pathname) {
  return `${String(baseUrl || "").replace(/\/+$/, "")}${pathname}`;
}

function buildProviderUrl(baseUrl, apiKind) {
  if (apiKind === "anthropic-messages") {
    return joinUrl(baseUrl, "/v1/messages");
  }

  return joinUrl(baseUrl, "/v1/messages");
}

function normalizeContentItem(item) {
  if (typeof item === "string") {
    return {
      type: "text",
      text: item
    };
  }

  if (item?.type === "text" && typeof item.text === "string") {
    return {
      type: "text",
      text: item.text
    };
  }

  return {
    type: "text",
    text: String(item?.text || "")
  };
}

function normalizeMessages(payload) {
  if (Array.isArray(payload?.messages) && payload.messages.length > 0) {
    return payload.messages.map((message) => ({
      role: message?.role || "user",
      content: Array.isArray(message?.content)
        ? message.content.map(normalizeContentItem)
        : [normalizeContentItem(message?.content || "")]
    }));
  }

  return [
    {
      role: "user",
      content: [
        {
          type: "text",
          text: String(payload?.prompt || payload?.input || "")
        }
      ]
    }
  ];
}

function buildRequestBody(payload, model) {
  const body = {
    model,
    max_tokens: Number(payload?.maxTokens) > 0 ? Number(payload.maxTokens) : 8192,
    messages: normalizeMessages(payload)
  };

  if (typeof payload?.system === "string" && payload.system.trim()) {
    body.system = payload.system.trim();
  }

  return body;
}

async function defaultTransport({ url, method, headers, body, timeoutMs }) {
  const controller = new AbortController();
  const timeout = setTimeout(() => {
    controller.abort();
  }, timeoutMs);

  try {
    const response = await fetch(url, {
      method,
      headers,
      body: JSON.stringify(body),
      signal: controller.signal
    });

    let responseBody = {};
    try {
      responseBody = await response.json();
    } catch {
      responseBody = {};
    }

    return {
      status: response.status,
      body: responseBody,
      headers: Object.fromEntries(response.headers.entries())
    };
  } catch (error) {
    if (error?.name === "AbortError") {
      throw createAIError(ERROR_CODES.UPSTREAM_TIMEOUT);
    }

    throw error;
  } finally {
    clearTimeout(timeout);
  }
}

function extractResponseBody(response) {
  if (typeof response?.json === "function") {
    return response.json();
  }

  if (response?.body !== undefined) {
    return response.body;
  }

  return {};
}

function extractTextContent(body) {
  if (typeof body?.output_text === "string" && body.output_text.trim()) {
    return body.output_text.trim();
  }

  if (Array.isArray(body?.content)) {
    return body.content
      .filter((item) => item?.type === "text" && typeof item.text === "string")
      .map((item) => item.text.trim())
      .join("")
      .trim();
  }

  return "";
}

export function createClaudeProvider({ config, transport = defaultTransport } = {}) {
  return {
    name: "claude",
    async request(context) {
      const url = buildProviderUrl(context.baseUrl || config.baseUrl, context.apiKind || config.apiKind);

      try {
        const response = await transport({
          url,
          method: "POST",
          timeoutMs: context.timeoutMs || config.timeoutMs || 30000,
          headers: {
            "content-type": "application/json",
            authorization: `Bearer ${config.apiKey}`
          },
          body: buildRequestBody(context.payload, context.model || config.model)
        });

        const statusCode = Number(response?.status) || 200;
        const responseBody = await extractResponseBody(response);

        if (statusCode >= 400) {
          throw createAIError(mapUpstreamStatusToErrorCode(statusCode), {
            statusCode
          });
        }

        const text = extractTextContent(responseBody);
        if (!text) {
          throw createAIError(ERROR_CODES.INVALID_MODEL_RESPONSE, {
            message: "模型返回缺少可读文本内容。"
          });
        }

        return {
          provider: "claude",
          model: context.model || config.model,
          text,
          raw: responseBody,
          usage: responseBody?.usage || null,
          data: {
            text
          }
        };
      } catch (error) {
        if (error?.code) {
          throw error;
        }

        if (error?.name === "AbortError") {
          throw createAIError(ERROR_CODES.UPSTREAM_TIMEOUT);
        }

        throw createAIError(ERROR_CODES.UPSTREAM_500, {
          message: error?.message || "AI provider 请求失败。"
        });
      }
    }
  };
}
