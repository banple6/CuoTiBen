const FAILURE_THRESHOLD = 3;
const OPEN_WINDOW_MS = 30_000;

class GeminiCircuitBreaker {
  constructor() {
    this.states = new Map();
  }

  beforeRequest(key) {
    const now = Date.now();
    const state = this.states.get(key);
    if (!state) {
      return { allowed: true, state: "closed", retryAfterMs: 0 };
    }

    if (state.openUntil && state.openUntil > now) {
      return {
        allowed: false,
        state: "open",
        retryAfterMs: Math.max(state.openUntil - now, 0)
      };
    }

    if (state.openUntil && state.openUntil <= now) {
      state.halfOpen = true;
      state.openUntil = 0;
      this.states.set(key, state);
      return { allowed: true, state: "half_open", retryAfterMs: 0 };
    }

    return { allowed: true, state: state.halfOpen ? "half_open" : "closed", retryAfterMs: 0 };
  }

  recordSuccess(key) {
    this.states.delete(key);
  }

  recordFailure(key) {
    const now = Date.now();
    const previous = this.states.get(key) ?? {
      consecutiveFailures: 0,
      openUntil: 0,
      halfOpen: false
    };
    const nextFailures = previous.halfOpen ? FAILURE_THRESHOLD : previous.consecutiveFailures + 1;
    const shouldOpen = nextFailures >= FAILURE_THRESHOLD;
    this.states.set(key, {
      consecutiveFailures: nextFailures,
      openUntil: shouldOpen ? now + OPEN_WINDOW_MS : 0,
      halfOpen: false
    });
  }
}

export const geminiCircuitBreaker = new GeminiCircuitBreaker();
