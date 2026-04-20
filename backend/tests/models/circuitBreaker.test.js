import test from "node:test";
import assert from "node:assert/strict";

import { createCircuitBreaker } from "../../src/models/circuitBreaker.js";

test("circuit breaker opens after three 503 failures and short-circuits requests", () => {
  let now = 0;
  const breaker = createCircuitBreaker({
    now: () => now,
    failureThreshold: 3,
    openDurationMs: 30000
  });
  const key = "claude:claude-opus-4-6";

  breaker.recordFailure(key, "UPSTREAM_503");
  breaker.recordFailure(key, "UPSTREAM_503");
  breaker.recordFailure(key, "UPSTREAM_503");

  const gate = breaker.allowRequest(key);

  assert.equal(gate.allowed, false);
  assert.equal(gate.state, "open");
  assert.equal(breaker.getState(key), "open");
});

test("circuit breaker transitions to half-open and closes after a successful probe", () => {
  let now = 0;
  const breaker = createCircuitBreaker({
    now: () => now,
    failureThreshold: 3,
    openDurationMs: 30000
  });
  const key = "claude:claude-opus-4-6";

  breaker.recordFailure(key, "UPSTREAM_TIMEOUT");
  breaker.recordFailure(key, "UPSTREAM_TIMEOUT");
  breaker.recordFailure(key, "UPSTREAM_TIMEOUT");

  now = 30001;

  const probe = breaker.allowRequest(key);
  assert.equal(probe.allowed, true);
  assert.equal(probe.state, "half-open");

  breaker.recordSuccess(key);

  assert.equal(breaker.getState(key), "closed");
});
