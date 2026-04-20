import test from "node:test";
import assert from "node:assert/strict";

import { createResponseCache } from "../../src/models/responseCache.js";

test("response cache stores and retrieves sentence entries by sentenceID and sentenceTextHash", () => {
  const cache = createResponseCache();
  const value = {
    explanation: "cached sentence"
  };

  cache.setSentence(
    {
      sentenceID: "sentence-1",
      sentenceTextHash: "hash-1"
    },
    value
  );

  assert.deepEqual(
    cache.getSentence({
      sentenceID: "sentence-1",
      sentenceTextHash: "hash-1"
    }),
    value
  );

  assert.equal(
    cache.getSentence({
      sentenceID: "sentence-1",
      sentenceTextHash: "hash-2"
    }),
    null
  );
});

test("response cache stores and retrieves passage entries by documentID and contentHash", () => {
  const cache = createResponseCache();
  const value = {
    overview: "cached passage"
  };

  cache.setPassage(
    {
      documentID: "document-1",
      contentHash: "content-1"
    },
    value
  );

  assert.deepEqual(
    cache.getPassage({
      documentID: "document-1",
      contentHash: "content-1"
    }),
    value
  );

  assert.equal(
    cache.getPassage({
      documentID: "document-2",
      contentHash: "content-1"
    }),
    null
  );
});
