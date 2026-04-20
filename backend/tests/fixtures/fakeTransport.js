export function createFakeTransport(sequence = []) {
  const queue = [...sequence];
  const calls = [];

  async function transport(request) {
    calls.push(request);

    const next = queue.length > 1 ? queue.shift() : queue[0];
    if (!next) {
      throw new Error("No fake transport response configured.");
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
      status: next.status ?? 200,
      body: next.body ?? {},
      headers: next.headers ?? {}
    };
  }

  transport.calls = calls;
  transport.push = (step) => {
    queue.push(step);
  };

  return transport;
}
