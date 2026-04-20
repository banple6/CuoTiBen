export function createMockAIProvider(sequence = []) {
  const queue = [...sequence];
  const calls = [];

  return {
    calls,
    async request(context) {
      calls.push(context);

      const next = queue.length > 1 ? queue.shift() : queue[0];
      if (!next) {
        throw new Error("No mock provider response configured.");
      }

      if (next.type === "throw") {
        throw next.error;
      }

      if (next.type === "timeout") {
        const error = new Error(next.message || "Request timed out.");
        error.name = "AbortError";
        throw error;
      }

      return {
        provider: context.provider || "mock",
        model: context.model || "mock-model",
        text: next.text || "",
        raw: next.raw || {},
        usage: next.usage || null,
        data: next.data || { text: next.text || "" }
      };
    }
  };
}
