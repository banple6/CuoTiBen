import {
  AI_PREWARM_CONCURRENCY,
  AI_PREWARM_MAX_SENTENCES_PER_DOCUMENT,
  getServerConfig
} from "../config/env.js";
import { getAIPersistentCacheStore } from "./AIPersistentCacheStore.js";
import { DocumentExplainPrewarmQueue } from "./DocumentExplainPrewarmQueue.js";
import { explainSentence } from "./explainSentenceService.js";

let queueSingleton = null;
let queueOverrideForTests = null;

async function explainPrewarmSentence(payload) {
  return explainSentence(payload);
}

export function getDocumentExplainPrewarmQueue() {
  if (queueOverrideForTests) {
    return queueOverrideForTests;
  }

  if (!queueSingleton) {
    const { modelName } = getServerConfig();
    queueSingleton = new DocumentExplainPrewarmQueue({
      store: getAIPersistentCacheStore(),
      modelName,
      explainSentence: explainPrewarmSentence,
      concurrency: AI_PREWARM_CONCURRENCY,
      maxSentencesPerDocument: AI_PREWARM_MAX_SENTENCES_PER_DOCUMENT,
      autoStart: true
    });
  }

  return queueSingleton;
}

export function setDocumentExplainPrewarmQueueForTests(queue) {
  queueOverrideForTests = queue;
}

export function resetDocumentExplainPrewarmQueueForTests() {
  queueOverrideForTests = null;
  queueSingleton = null;
}
