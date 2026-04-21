import crypto from "node:crypto";

export function normalizeClientRequestID(value) {
  if (typeof value !== "string") {
    return "";
  }

  return value.trim().slice(0, 128);
}

export function resolveRequestID(clientRequestID = "") {
  const normalized = normalizeClientRequestID(clientRequestID);
  if (normalized) {
    return normalized;
  }
  return `srv-${crypto.randomUUID()}`;
}

export function stableHash(value) {
  return crypto.createHash("sha1").update(String(value || "")).digest("hex");
}
