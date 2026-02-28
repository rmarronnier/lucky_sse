# lucky_sse

`lucky_sse` is a Lucky-aware, app-agnostic Server-Sent Events toolkit for Crystal.
It provides:

- A structured event envelope for publishing
- In-memory and Redis adapters
- Stream filtering helpers
- Session management with heartbeat writes
- A small ESM browser client with shared `EventSource` handling

## Requirements

- Crystal `>= 1.19.1`
- Redis shard dependency is hard-required by this shard
- Bun (for JS client setup/tests)

## Installation

Add to your app's `shard.yml`:

```yaml
dependencies:
  lucky_sse:
    github: rmarronnier/lucky_sse
```

Then install:

```bash
shards install
```

## Configuration

```crystal
require "lucky_sse"

Lucky::SSE.configure do |settings|
  settings.default_producer = "my_lucky_app"
  settings.heartbeat_interval = 20.seconds

  # Default is memory adapter. For production, prefer Redis:
  settings.adapter = Lucky::SSE::Adapters::Redis.new(ENV["REDIS_URL"])
end
```

## Publishing Events

### `Lucky::SSE.publish`

```crystal
Lucky::SSE.publish(
  "orders",
  "order.updated",
  {"id" => 42, "status" => "paid"},
  meta: {"tenant" => "acme"}
)
```

Returns the envelope id (`String`).

### `Lucky::SSE.publish_raw`

```crystal
Lucky::SSE.publish_raw("orders", "order.updated", %({"id":42,"status":"paid"}))
Lucky::SSE.publish_raw("orders", "log.message", "plain text payload")
```

If `raw` is valid JSON it is used as JSON data; otherwise it is sent as a string.

### Envelope format

Published payloads use this JSON envelope:

```json
{
  "id": "evt-123",
  "event": "order.updated",
  "occurred_at": "2026-02-28T22:00:00Z",
  "data": {"id": 42, "status": "paid"},
  "meta": {
    "topic": "orders",
    "producer": "my_lucky_app",
    "trace_id": "evt-123",
    "tenant": "acme"
  }
}
```

Reserved metadata keys are always enforced by the library:

- `topic`
- `producer`
- `trace_id`

Caller metadata is merged, but these reserved keys are not overridable.

## Streaming API

`Lucky::SSE::Stream` lets you define stream rules for a topic:

```crystal
stream = Lucky::SSE::Stream.new("orders")
  .allow_events("order.updated", "order.cancelled")
  .filter { |event| event.data_json.try(&.as_h["tenant"]?.try(&.as_s)) == "acme" }
```

- `allow_events` limits accepted event names.
- `filter` adds custom predicates over parsed events.

## Session API

`Lucky::SSE::Session` writes SSE frames to an `HTTP::Server::Response`:

```crystal
session = Lucky::SSE::Session.new(
  response,
  stream,
  adapter: Lucky::SSE.settings.adapter,
  heartbeat_interval: 20.seconds
)

session.run
```

Session behavior:

- Sets SSE headers (`text/event-stream`, `no-cache`, keep-alive)
- Sends a `: connected` comment on open
- Sends periodic `: ping` comments
- Subscribes to stream topic and forwards accepted events
- Cleans up heartbeat and adapter subscription on shutdown

## Adapters

### Memory adapter

`Lucky::SSE::Adapters::Memory` is useful for development and tests.

Characteristics:

- In-process only
- Per-subscriber channels
- Callback failures are isolated from publisher flow

### Redis adapter

`Lucky::SSE::Adapters::Redis` is intended for multi-process production setups.

Characteristics:

- Uses Redis pub/sub
- Reconnect loop with bounded backoff on subscription errors
- `close` is idempotent and closes the active Redis connection

## Browser Client (`js/client.js`)

```js
import { createLuckySSE } from "./client.js";

const sse = createLuckySSE();
const sub = sse.subscribe({ key: "orders", url: "/sse/orders" });

sub.on("order.updated", (payload, envelope, nativeEvent) => {
  console.log(payload, envelope, nativeEvent);
});

sub.onOpen(() => console.log("connected"));
sub.onError((e) => console.error(e));

// Later:
sub.release();
```

Key client rules:

- Subscriptions with same `key` share one `EventSource`.
- Reusing a `key` with a different `url` throws immediately.
- `autoLifecycle` (default `true`) closes streams on `pagehide`/`beforeunload`
  and reconnects active streams on `pageshow`.

## Development

Run Crystal checks:

```bash
crystal tool format --check src/lucky_sse.cr src/lucky_sse/**/*.cr spec/**/*.cr
crystal build src/lucky_sse.cr --no-codegen
crystal spec
```

JS setup (Bun):

```bash
bun install
```

Run JS client tests:

```bash
bun test ./js/client.test.mjs
# or
bun run test:js
```

Run Redis integration spec:

```bash
LUCKY_SSE_REDIS_URL=redis://127.0.0.1:6379 crystal spec spec/lucky_sse_redis_adapter_spec.cr
```

## Long-term Guidance

- Use Redis adapter in production.
- Keep event names stable and versioned (`domain.entity.action.v2` if needed).
- Keep envelopes small; store heavy payloads elsewhere and publish references.
- Keep client handlers resilient; a failed handler should not own stream lifecycle.
