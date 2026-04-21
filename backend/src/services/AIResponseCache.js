import { stableHash } from "../lib/requestId.js";

const DEFAULT_TTL_MS = 12 * 60 * 60 * 1000;

class AIResponseCache {
  constructor() {
    this.entries = new Map();
  }

  makeKey(parts) {
    return stableHash(parts.filter(Boolean).join("\u001e"));
  }

  get(key) {
    const entry = this.entries.get(key);
    if (!entry) {
      return null;
    }
    if (entry.expiresAt <= Date.now()) {
      this.entries.delete(key);
      return null;
    }
    return entry.value;
  }

  set(key, value, ttlMs = DEFAULT_TTL_MS) {
    this.entries.set(key, {
      value,
      expiresAt: Date.now() + ttlMs
    });
  }
}

export const aiResponseCache = new AIResponseCache();
