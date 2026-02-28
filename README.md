# lucky_sse

Lucky-aware, app-agnostic SSE toolkit for Lucky projects.

## Features

- SSE publishing with default envelope (`id`, `event`, `occurred_at`, `data`, `meta`)
- `meta` defaults: `topic`, `producer`, `trace_id`
- Memory adapter (dev/test)
- Redis adapter (`jgaskins/redis`)
- SSE stream session helper with heartbeat + filters
- ESM browser client with shared EventSource management and page lifecycle handling

## Status

Hosted temporarily inside the app repository. Planned extraction to standalone repository after stabilization.
