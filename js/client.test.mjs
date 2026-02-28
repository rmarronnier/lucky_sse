import { afterEach, beforeEach, expect, test } from "bun:test";
import { createLuckySSE } from "./client.js";

class MockEventSource {
  static CONNECTING = 0;
  static OPEN = 1;
  static CLOSED = 2;
  static instances = [];

  constructor(url) {
    this.url = url;
    this.readyState = MockEventSource.CONNECTING;
    this.listeners = new Map();
    this.closed = false;
    this.onopen = null;
    this.onerror = null;
    MockEventSource.instances.push(this);
  }

  addEventListener(eventName, handler) {
    let handlers = this.listeners.get(eventName);
    if (!handlers) {
      handlers = new Set();
      this.listeners.set(eventName, handlers);
    }
    handlers.add(handler);
  }

  removeEventListener(eventName, handler) {
    const handlers = this.listeners.get(eventName);
    if (!handlers) return;
    handlers.delete(handler);
    if (handlers.size === 0) this.listeners.delete(eventName);
  }

  emit(eventName, event) {
    const handlers = this.listeners.get(eventName);
    if (!handlers) return;
    handlers.forEach((handler) => handler(event));
  }

  close() {
    this.closed = true;
    this.readyState = MockEventSource.CLOSED;
  }
}

const createWindowMock = () => {
  const handlers = new Map();
  return {
    addEventListener(eventName, handler) {
      let items = handlers.get(eventName);
      if (!items) {
        items = new Set();
        handlers.set(eventName, items);
      }
      items.add(handler);
    },
    dispatch(eventName, event = {}) {
      const items = handlers.get(eventName);
      if (!items) return;
      items.forEach((handler) => handler(event));
    },
  };
};

beforeEach(() => {
  MockEventSource.instances = [];
  globalThis.EventSource = MockEventSource;
  globalThis.window = createWindowMock();
});

afterEach(() => {
  delete globalThis.EventSource;
  delete globalThis.window;
});

test("throws when the same stream key is reused with another URL", () => {
  const client = createLuckySSE({ autoLifecycle: false });
  const subscription = client.subscribe({ key: "orders", url: "/sse/orders" });
  expect(subscription).toBeTruthy();

  expect(() => client.subscribe({ key: "orders", url: "/sse/other" })).toThrow(/already maps/);

  subscription.release();
});

test("shares one EventSource for identical key+url and closes only after last release", () => {
  const client = createLuckySSE({ autoLifecycle: false });
  const one = client.subscribe({ key: "orders", url: "/sse/orders" });
  const two = client.subscribe({ key: "orders", url: "/sse/orders" });
  const source = MockEventSource.instances[0];

  expect(MockEventSource.instances.length).toBe(1);
  expect(source.closed).toBe(false);

  one.release();
  expect(source.closed).toBe(false);

  two.release();
  expect(source.closed).toBe(true);
});

test("decodes Lucky envelope payload in .on handlers", () => {
  const client = createLuckySSE({ autoLifecycle: false });
  const subscription = client.subscribe({ key: "orders", url: "/sse/orders" });
  const source = MockEventSource.instances[0];
  let received = null;

  subscription.on("order.updated", (payload, envelope) => {
    received = { payload, envelope };
  });

  source.emit("order.updated", {
    data: JSON.stringify({
      id: "evt-1",
      event: "order.updated",
      data: { id: 42, status: "paid" },
    }),
  });

  expect(received.payload).toEqual({ id: 42, status: "paid" });
  expect(received.envelope.id).toBe("evt-1");
  expect(received.envelope.event).toBe("order.updated");

  subscription.release();
});

test("auto lifecycle closes and reconnects active streams", () => {
  const client = createLuckySSE();
  const subscription = client.subscribe({ key: "orders", url: "/sse/orders" });
  const first = MockEventSource.instances[0];

  globalThis.window.dispatch("pagehide");
  expect(first.closed).toBe(true);

  globalThis.window.dispatch("pageshow", { persisted: true });
  expect(MockEventSource.instances.length).toBe(2);
  expect(MockEventSource.instances[1].closed).toBe(false);

  subscription.release();
});
