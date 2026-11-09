# Worker Mode v2 Architecture

Worker Mode turns CSW from a stateless CLI wrapper into a persistent AI processing engine. Instead of spawning a new `claude -p` process per request (14-40s cold-start), Worker Mode maintains long-running Claude sessions in tmux, so requests skip that per-request cold start.

## Lifecycle

<img src="https://mermaid.ink/img/c3RhdGVEaWFncmFtLXYyCiAgICBbKl0gLS0-IHN0YXJ0aW5nOiBQT1NUIC93b3JrZXJzCiAgICBzdGFydGluZyAtLT4gb25saW5lOiB0bXV4IHNlc3Npb24gcmVhZHkgKH4xNnMpCiAgICBvbmxpbmUgLS0-IGJ1c3k6IHJlcXVlc3QgYXNzaWduZWQKICAgIGJ1c3kgLS0-IG9ubGluZTogcmVzcG9uc2UgcmV0dXJuZWQKICAgIGJ1c3kgLS0-IHJlY292ZXJpbmc6IG5vIHJlc3BvbnNlIHdpdGhpbiBqb2JUaW1lb3V0ICgzMHMpCiAgICByZWNvdmVyaW5nIC0tPiBvbmxpbmU6IHJlcGxpY2EgcmVzdGFydGVkCiAgICByZWNvdmVyaW5nIC0tPiBvZmZsaW5lOiByZWNvdmVyeSBsaW1pdCBleGNlZWRlZAogICAgb25saW5lIC0tPiBpZGxlOiBpZGxlVGltZW91dCByZWFjaGVkICgxMCBtaW4pCiAgICBpZGxlIC0tPiBzdGFydGluZzogbmV4dCByZXF1ZXN0IG9yIHdha2UKICAgIG9mZmxpbmUgLS0-IHN0YXJ0aW5nOiBuZXh0IHJlcXVlc3QsIHdha2Ugb3IgcmVzdGFydAogICAgb25saW5lIC0tPiBbKl06IERFTEVURSAvd29ya2Vycy86bmFtZQoKICAgIG5vdGUgcmlnaHQgb2Ygb25saW5lCiAgICAgICAgYWx3YXlzT249dHJ1ZSBza2lwcwogICAgICAgIHRoZSBpZGxlIHRyYW5zaXRpb24KICAgIGVuZCBub3RlCg==" alt="Worker Lifecycle State Diagram" />

## State Transitions

A worker is a named group of one or more **replicas**; each replica is its own tmux session running `claude`. Every replica moves through these states: `starting`, `online`, `busy`, `recovering`, `idle`, `offline`. The worker's own status is derived from its replicas (online if any replica is online, then busy, starting, recovering, idle, otherwise offline).

### starting → online (~16s)

When a worker is created via `POST /api/v1/workers`, the system:

1. Validates the worker name (see [Hardening](#hardening)) and creates a worker directory at `$CSW_WORKERS_DIR/{name}/` (additional replicas use `r2/`, `r3/`, … subdirectories)
2. Writes a `CLAUDE.md` file with the worker's system prompt and configuration
3. Writes a `worker.json` with metadata (name, preset, options)
4. Spawns a tmux session running `claude` in the worker directory
5. Claude reads `CLAUDE.md` and becomes ready for input

The ~16s startup time is Claude initializing and loading its context.

### online → busy → online

The core request cycle:

```
1. Request arrives at CSW API with options.worker = "{name}"
2. Worker Manager picks a free (online) replica; if none is free, the
   request waits up to queueTimeout (default 60s) instead of failing
3. Worker Manager writes job to {replicaDir}/inbox/{jobId}.json
4. tmux send-keys (invoked with an argv array, not a shell string)
   tells Claude to read the inbox file
5. Worker Manager polls {replicaDir}/outbox/{jobId}.json
   (100ms polling interval)
6. Claude processes the request and writes response to outbox
7. Worker Manager reads the outbox file
8. Worker Manager sends /clear to the tmux session (resets for next request)
9. Response returned to client
```

### busy → recovering → online

If Claude doesn't respond within `jobTimeout` (default 30 seconds):

1. The job is marked as `timeout`
2. That replica's tmux session is killed (`tmux kill-session`); other replicas keep serving
3. An error response is returned to the client
4. The replica moves to `recovering` and a new tmux session is spawned

This handles cases where Claude hangs, enters an unexpected state, or hits a rate limit.

### online → idle → starting → online

Resource management for workers that aren't `alwaysOn`:

1. **Idle detection**: If a replica receives no requests within `idleTimeout` (default 10 minutes), its tmux session is destroyed to free resources
2. **Wake**: When the next request arrives (or `POST /workers/:name/wake` is called), a sleeping replica is started again (~16s), then the request is processed
3. This is transparent to the client -- they just see a slightly slower response for the first request after idle

### alwaysOn Workers

For latency-sensitive (interactive) endpoints where the ~16s wake penalty is unacceptable, workers can be configured with `alwaysOn: true`. These workers:

- Never enter the `idle` state
- Survive server reboots (auto-restored from `worker.json`)
- Are restarted with staggered 10-second intervals to avoid thundering herd

## File-Based Communication

The inbox/outbox pattern was chosen for its simplicity and debuggability:

```
$CSW_WORKERS_DIR/{name}/      (e.g. /var/lib/csw/workers/{name}/)
├── CLAUDE.md           ← System prompt + instructions
├── worker.json         ← Worker metadata + config
├── inbox/
│   └── {jobId}.json    ← Request (written by CSW, read by Claude)
├── outbox/
│   └── {jobId}.json    ← Response (written by Claude, read by CSW)
└── r2/, r3/, …         ← Additional replicas (same layout)
```

### Inbox Format

```json
{
  "jobId": "uuid",
  "input": "User's request text",
  "memory": [
    { "category": "property", "key": "userName", "value": "Alice" }
  ],
  "outputFormat": null
}
```

### Outbox Format

```json
{
  "jobId": "uuid",
  "response": "Claude's response text",
  "error": null
}
```

## Health Monitoring

A health check runs every 30 seconds for each active worker:

1. **tmux session check**: Is the tmux session still alive?
2. **Process check**: Is the Claude process still running inside the session?
3. **Recovery**: If the session is dead, the replica is restarted, with at least 60 seconds between attempts; after 5 failed attempts it is marked `offline` until the next request, wake or restart

## Server Reboot Recovery

On server start, CSW:

1. Scans `$CSW_WORKERS_DIR` for `worker.json` files
2. Sorts workers by priority (alwaysOn first)
3. Spawns tmux sessions with 10-second staggered intervals between workers (3 seconds between replicas of one worker)
4. Logs recovery status for each worker

This ensures all workers are restored without overwhelming the system.

## Configuration

Workers are configured via the `options` object in the process request or preset:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `worker` | string | null | Worker name (enables Worker Mode) |
| `alwaysOn` | boolean | false | Prevent idle shutdown |
| `idleTimeout` | number | 600000 | Milliseconds before idle shutdown (10 min) |
| `replicas` | number | 1 | Parallel tmux sessions for this worker (change at runtime with `POST /workers/:name/scale`) |
| `queueTimeout` | number | 60000 | Milliseconds a request waits for a free replica |
| `jobTimeout` | number | 30000 | Milliseconds before a request is treated as hung |
| `model` | string | "sonnet" | Claude model for the worker |
| `effort` | string | "low" | Claude effort level (server default `CLAUDE_EFFORT`) |

## Hardening

Worker Mode starts processes on the host from API input, so the following are requirements, not options:

- **Private network only.** The reference server has no built-in authentication. Keep the API off the public internet and put an authenticating proxy or IP allowlist in front of it.
- **Allowlist worker names.** Names must match `^[a-z0-9][a-z0-9-]{0,31}$`. Validate on creation and on every route that takes `:name` (and again before building any path), and reject anything else with `400`.
- **argv, never shell strings.** Call `tmux` (and anything else) with an argument array (`execFile`-style). Never interpolate a name, path or input into a command string.
- **Unprivileged worker account.** Run tmux sessions as a dedicated OS user (`CSW_WORKER_USER`) with no sudo rights and access limited to the workers directory.

## When to Use Worker Mode

| Scenario | Recommended Mode |
|----------|-----------------|
| One-off text processing | Standard |
| Batch processing (100+ items) | Standard |
| Interactive local tool (< 5s expected) | Worker (alwaysOn) |
| Conversational AI features | Worker |
| Background cron jobs | Standard |
| High-frequency same-preset calls | Worker |

## Limitations

- **One request per replica**: Each replica handles one request at a time. A worker can run N replicas (`replicas`, `POST /workers/:name/scale`); requests wait up to `queueTimeout` (60s) for a free replica.
- **Cold-start on wake**: ~16 seconds for session recreation after idle. Use `alwaysOn` for latency-sensitive endpoints.
- **tmux dependency**: Worker Mode requires tmux installed on the server.
- **Single-machine**: Workers are bound to the machine they're created on. No cross-machine distribution (yet).
