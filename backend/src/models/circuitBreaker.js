import { isCircuitBreakerErrorCode } from "./errors.js";

function createDefaultEntry() {
  return {
    state: "closed",
    failureCount: 0,
    openedAt: null
  };
}

export function createCircuitBreaker({
  now = Date.now,
  failureThreshold = 3,
  openDurationMs = 30000
} = {}) {
  const states = new Map();

  function getEntry(key) {
    if (!states.has(key)) {
      states.set(key, createDefaultEntry());
    }

    return states.get(key);
  }

  function getState(key) {
    const entry = getEntry(key);

    if (entry.state === "open" && entry.openedAt !== null && (now() - entry.openedAt) >= openDurationMs) {
      entry.state = "half-open";
    }

    return entry.state;
  }

  function allowRequest(key) {
    const state = getState(key);

    return {
      allowed: state !== "open",
      state
    };
  }

  function recordFailure(key, errorCode) {
    if (!isCircuitBreakerErrorCode(errorCode)) {
      return getState(key);
    }

    const entry = getEntry(key);
    const currentState = getState(key);

    if (currentState === "half-open") {
      entry.state = "open";
      entry.failureCount = failureThreshold;
      entry.openedAt = now();
      return entry.state;
    }

    entry.failureCount += 1;
    if (entry.failureCount >= failureThreshold) {
      entry.state = "open";
      entry.openedAt = now();
    }

    return entry.state;
  }

  function recordSuccess(key) {
    const entry = getEntry(key);
    entry.state = "closed";
    entry.failureCount = 0;
    entry.openedAt = null;
    return entry.state;
  }

  function reset(key) {
    states.delete(key);
  }

  return {
    allowRequest,
    getState,
    recordFailure,
    recordSuccess,
    reset
  };
}
