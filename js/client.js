const toEventPayload = (event) => {
  const raw = String(event?.data || "");
  try {
    const parsed = JSON.parse(raw);
    const envelope = parsed && typeof parsed === "object" ? parsed : null;
    if (envelope && Object.prototype.hasOwnProperty.call(envelope, "data")) {
      return { payload: envelope.data, envelope, raw };
    }
    return { payload: parsed, envelope: null, raw };
  } catch (_error) {
    return { payload: raw, envelope: null, raw };
  }
};

export const createLuckySSE = (config = {}) => {
  const streams = new Map();
  const autoLifecycle = config.autoLifecycle !== false;
  let suspendedByPageLifecycle = false;

  const safeCall = (callback, ...args) => {
    if (typeof callback !== "function") return;
    try {
      callback(...args);
    } catch (_error) {
      // Keep listener failures isolated.
    }
  };

  const addListener = (entry, eventName, handler) => {
    let handlers = entry.eventHandlers.get(eventName);
    if (!handlers) {
      handlers = new Set();
      entry.eventHandlers.set(eventName, handlers);
    }
    handlers.add(handler);
    if (entry.source) {
      entry.source.addEventListener(eventName, handler);
    }
  };

  const removeListener = (entry, eventName, handler) => {
    const handlers = entry.eventHandlers.get(eventName);
    if (!handlers) return;
    handlers.delete(handler);
    if (handlers.size === 0) {
      entry.eventHandlers.delete(eventName);
    }
    if (entry.source) {
      entry.source.removeEventListener(eventName, handler);
    }
  };

  const attachSource = (entry) => {
    if (entry.source) return;

    const source = new EventSource(entry.url);
    entry.source = source;

    source.onopen = (event) => {
      entry.openHandlers.forEach((handler) => safeCall(handler, event));
    };

    source.onerror = (event) => {
      entry.errorHandlers.forEach((handler) => safeCall(handler, event));
    };

    entry.eventHandlers.forEach((handlers, eventName) => {
      handlers.forEach((handler) => source.addEventListener(eventName, handler));
    });
  };

  const detachSource = (entry) => {
    if (!entry.source) return;
    try {
      entry.source.close();
    } catch (_error) {
      // Keep close non-blocking.
    }
    entry.source = null;
  };

  const closeAll = () => {
    streams.forEach((entry) => detachSource(entry));
    suspendedByPageLifecycle = true;
  };

  const reconnectAll = () => {
    streams.forEach((entry) => {
      if (entry.refCount > 0) attachSource(entry);
    });
    suspendedByPageLifecycle = false;
  };

  if (autoLifecycle && typeof window !== "undefined") {
    window.addEventListener("pagehide", () => {
      closeAll();
    });
    window.addEventListener("beforeunload", () => {
      closeAll();
    });
    window.addEventListener("pageshow", (event) => {
      if (event.persisted) reconnectAll();
    });
  }

  const subscribe = ({ key, url }) => {
    const streamKey = String(key || "");
    const streamUrl = String(url || "");
    if (!streamKey || !streamUrl) return null;

    let entry = streams.get(streamKey);
    if (!entry) {
      entry = {
        key: streamKey,
        url: streamUrl,
        source: null,
        refCount: 0,
        openHandlers: new Set(),
        errorHandlers: new Set(),
        eventHandlers: new Map(),
      };
      streams.set(streamKey, entry);
    }

    attachSource(entry);
    entry.refCount += 1;

    let released = false;
    const cleanup = [];

    const release = () => {
      if (released) return;
      released = true;

      cleanup.forEach((fn) => fn());
      cleanup.length = 0;

      entry.refCount = Math.max(0, entry.refCount - 1);
      if (entry.refCount === 0) {
        detachSource(entry);
        streams.delete(streamKey);
      }
    };

    return {
      addEventListener(eventName, handler) {
        if (released || typeof handler !== "function") return;
        const wrapped = (event) => safeCall(handler, event);
        addListener(entry, eventName, wrapped);
        cleanup.push(() => removeListener(entry, eventName, wrapped));
      },

      on(eventName, handler) {
        if (released || typeof handler !== "function") return;
        const wrapped = (event) => {
          const decoded = toEventPayload(event);
          safeCall(handler, decoded.payload, decoded.envelope, event);
        };
        addListener(entry, eventName, wrapped);
        cleanup.push(() => removeListener(entry, eventName, wrapped));
      },

      onOpen(handler) {
        if (released || typeof handler !== "function") return;
        entry.openHandlers.add(handler);
        cleanup.push(() => entry.openHandlers.delete(handler));
      },

      onError(handler) {
        if (released || typeof handler !== "function") return;
        entry.errorHandlers.add(handler);
        cleanup.push(() => entry.errorHandlers.delete(handler));
      },

      readyState() {
        if (entry.source) return entry.source.readyState;
        return suspendedByPageLifecycle ? EventSource.CLOSED : EventSource.CONNECTING;
      },

      release,
    };
  };

  return {
    subscribe,
    closeAll,
    reconnectAll,
  };
};
