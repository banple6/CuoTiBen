function buildSentenceKey(identity = {}) {
  const sentenceID = String(identity.sentenceID || "").trim();
  const sentenceTextHash = String(identity.sentenceTextHash || "").trim();

  if (!sentenceID || !sentenceTextHash) {
    return null;
  }

  return `sentence:${sentenceID}:${sentenceTextHash}`;
}

function buildPassageKey(identity = {}) {
  const documentID = String(identity.documentID || "").trim();
  const contentHash = String(identity.contentHash || "").trim();

  if (!documentID || !contentHash) {
    return null;
  }

  return `passage:${documentID}:${contentHash}`;
}

export function createResponseCache({
  now = Date.now,
  ttlMs = 10 * 60 * 1000
} = {}) {
  const store = new Map();

  function read(key) {
    if (!key) {
      return null;
    }

    const entry = store.get(key);
    if (!entry) {
      return null;
    }

    if (entry.expiresAt <= now()) {
      store.delete(key);
      return null;
    }

    return entry.value;
  }

  function write(key, value) {
    if (!key) {
      return value;
    }

    store.set(key, {
      value,
      expiresAt: now() + ttlMs
    });

    return value;
  }

  return {
    getSentence(identity) {
      return read(buildSentenceKey(identity));
    },
    setSentence(identity, value) {
      return write(buildSentenceKey(identity), value);
    },
    getPassage(identity) {
      return read(buildPassageKey(identity));
    },
    setPassage(identity, value) {
      return write(buildPassageKey(identity), value);
    }
  };
}
