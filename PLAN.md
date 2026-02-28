# lucky_sse Stabilization Plan

## Goals
- Raise the shard to production-grade reliability for Lucky applications.
- Keep Redis as a hard dependency and first-class adapter.
- Provide strong regression protection with meaningful specs.
- Deliver complete documentation for maintainers and users.

## Findings and Remediation Plan

### 1) Memory adapter can block publishers after subscriber callback crashes
- **Issue**: A callback exception kills the subscriber fiber while the channel stays registered, which can eventually block `publish` when channel buffers fill.
- **Changes**:
  - Make callback execution fault-tolerant in memory subscription loop.
  - Ensure channel/listener cleanup is deterministic when subscriber loop exits.
  - Add idempotent close behavior in memory subscription.
- **Specs**:
  - Reproduce callback failure and assert publishing remains non-blocking.
  - Verify closed subscriptions are removed and no stale listeners remain.

### 2) SSE writer allows field injection via newline/control chars in `id`/`event`
- **Issue**: Raw `id` and `event` values are written directly into SSE fields.
- **Changes**:
  - Sanitize SSE field values by removing CR/LF and NUL where applicable.
  - Enforce non-empty event name fallback to `message` after sanitization.
- **Specs**:
  - Assert emitted frames do not contain injected headers/events from malicious values.

### 3) Redis subscription can silently die on transport/runtime errors
- **Issue**: Errors inside Redis subscription loop are swallowed; stream can stall permanently.
- **Changes**:
  - Add reconnect loop with bounded backoff.
  - Build subscription object that can close active connection and stop retries.
  - Keep shutdown idempotent and thread-safe.
- **Specs**:
  - Unit test close idempotency and lifecycle behavior where feasible.
  - Add optional integration spec hooks for real Redis (env-gated).

### 4) Reserved envelope metadata (`topic`, `producer`, `trace_id`) can be overridden
- **Issue**: User `meta` can overwrite reserved envelope semantics.
- **Changes**:
  - Merge custom metadata first, then force reserved keys.
  - Document reserved key behavior clearly.
- **Specs**:
  - Assert reserved keys are always correct in published payload.

### 5) JS client reuses stream by key even when URL differs
- **Issue**: Reusing a key with another URL silently keeps the original URL.
- **Changes**:
  - Detect key/URL mismatch and fail fast with explicit error.
- **Specs**:
  - Add Node tests with mocked `EventSource` to verify key-url guard and lifecycle behavior.

### 6) Missing automated spec coverage
- **Issue**: No `spec/` coverage exists.
- **Changes**:
  - Add broad unit coverage for parser, writer, stream filters, publish envelope behavior, memory adapter, and session.
  - Add optional Redis integration specs behind env guard.
- **Target**:
  - Cover critical behavior and previously identified regression paths.

### 7) README incomplete / stale
- **Issue**: README doesn’t match published shard maturity expectations.
- **Changes**:
  - Replace with complete user guide:
    - install/setup
    - adapters/configuration
    - publishing API
    - stream/session integration
    - JS client API
    - operational notes and recommended patterns
    - testing and development workflow

## Execution Order
1. Implement core code fixes in Crystal + JS.
2. Add/expand specs for all remediations.
3. Rewrite README with production guidance.
4. Run format + build + full spec suite.

## Definition of Done
- `crystal tool format --check` passes.
- `crystal build src/lucky_sse.cr --no-codegen` passes.
- `crystal spec` passes with meaningful coverage.
- README documents all public APIs and behavior.
- All findings above are addressed in code and covered by tests where practical.
