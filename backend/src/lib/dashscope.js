import OpenAI from "openai";
import { getDashScopeConfig } from "../config/env.js";

let client;
let cachedKey;
let cachedBaseURL;

export function getDashScopeClient() {
  const { apiKey, baseURL } = getDashScopeConfig();

  if (!apiKey || !baseURL) {
    return null;
  }

  if (!client || cachedKey !== apiKey || cachedBaseURL !== baseURL) {
    client = new OpenAI({
      apiKey,
      baseURL
    });
    cachedKey = apiKey;
    cachedBaseURL = baseURL;
  }

  return client;
}
