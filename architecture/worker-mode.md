# Worker Mode v2 Architecture

Worker Mode turns CSW from a stateless CLI wrapper into a persistent AI processing engine. Instead of spawning a new `claude -p` process per request (14-40s cold-start), Worker Mode maintains long-running Claude sessions in tmux, cutting response time by 2.5x.

## Lifecycle

<img src="https://mermaid.ink/img/c3RhdGVEaWFncmFtLXYyCiAgICBbKl0gLS0-IENyZWF0ZWQ6IFBPU1QgL3dvcmtlcnMKICAgIENyZWF0ZWQgLS0-IFJlYWR5OiB0bXV4IHNlc3Npb24gc3Bhd25lZCAofjE2cykKICAgIFJlYWR5IC0tPiBQcm9jZXNzaW5nOiByZXF1ZXN0IHJlY2VpdmVkCiAgICBQcm9jZXNzaW5nIC0tPiBSZWFkeTogcmVzcG9uc2UgcmV0dXJuZWQKICAgIFByb2Nlc3NpbmcgLS0-IFRpbWVkT3V0OiAzMHMgbm8gcmVzcG9uc2UKICAgIFRpbWVkT3V0IC0tPiBSZWFkeTogYXV0by1yZXN0YXJ0CiAgICBSZWFkeSAtLT4gSWRsZTogaWRsZVRpbWVvdXQgcmVhY2hlZAogICAgSWRsZSAtLT4gQXdha2U6IG5leHQgcmVxdWVzdAogICAgQXdha2UgLS0-IFJlYWR5OiBzZXNzaW9uIHJlY3JlYXRlZCAofjE2cykKICAgIFJlYWR5IC0tPiBbKl06IERFTEVURSAvd29ya2VycwoKICAgIG5vdGUgcmlnaHQgb2YgUmVhZHkKICAgICAgICBhbHdheXNPbj10cnVlIHNraXBzCiAgICAgICAgSWRsZSB0cmFuc2l0aW9uCiAgICBlbmQgbm90ZQo=" alt="Worker Lifecycle State Diagram" />

## State Transitions

### Created → Ready (~16s)

When a worker is created via `POST /api/v1/workers`, the system:

1. Creates a worker directory at `/opt/csw-workers/{name}/`
2. Writes a `CLAUDE.md` file with the worker's system prompt and configuration
3. Writes a `worker.json` with metadata (name, preset, options)
4. Spawns a tmux session running `claude` in the worker directory
5. Claude reads `CLAUDE.md` and becomes ready for input

The ~16s startup time is Claude initializing and loading its context.

### Ready → Processing → Ready

The core request cycle:

```
1. Request arrives at CSW API with options.worker = "{name}"
2. Worker Manager writes job to /opt/csw-workers/{name}/inbox/{jobId}.json
3. tmux send-keys sends a command telling Claude to read the inbox file
4. Worker Manager polls /opt/csw-workers/{name}/outbox/{jobId}.json
   (100ms polling interval)
5. Claude processes the request and writes response to outbox
6. Worker Manager reads the outbox file
7. Worker Manager sends /clear to the tmux session (resets for next request)
8. Response returned to client
```

### Processing → TimedOut → Ready

If Claude doesn't respond within 30 seconds:

1. The job is marked as `timeout`
2. The tmux session is killed (`tmux kill-session`)
3. An error response is returned to the client
4. The worker automatically restarts (new tmux session spawned)

This handles cases where Claude hangs, enters an unexpected state, or hits a rate limit.

### Ready → Idle → Awake → Ready

Resource management for workers that aren't `alwaysOn`:

1. **Idle detection**: If no requests arrive within `idleTimeout` (configurable), the tmux session is destroyed to free resources
2. **Awake**: When the next request arrives for an idle worker, a new tmux session is spawned (~16s), then the request is processed
3. This is transparent to the client -- they just see a slightly slower response for the first request after idle

### alwaysOn Workers

For user-facing endpoints where the ~16s awake penalty is unacceptable, workers can be configured with `alwaysOn: true`. These workers:

- Never enter the Idle state
- Survive server reboots (auto-restored from `worker.json`)
- Are restarted with staggered 10-second intervals to avoid thundering herd

## File-Based Communication

The inbox/outbox pattern was chosen for its simplicity and debuggability:

```
/opt/csw-workers/{name}/
├── CLAUDE.md           ← System prompt + instructions
├── worker.json         ← Worker metadata + config
├── inbox/
│   └── {jobId}.json    ← Request (written by CSW, read by Claude)
└── outbox/
    └── {jobId}.json    ← Response (written by Claude, read by CSW)
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
3. **Recovery**: If the session is dead, it's automatically restarted (max 5 consecutive failures before giving up)

## Server Reboot Recovery

On server start, CSW:

1. Scans `/opt/csw-workers/` for `worker.json` files
2. Sorts workers by priority (alwaysOn first)
3. Spawns tmux sessions with 10-second staggered intervals
4. Logs recovery status for each worker

This ensures all workers are restored without overwhelming the system.

## Configuration

Workers are configured via the `options` object in the process request or preset:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `worker` | string | null | Worker name (enables Worker Mode) |
| `alwaysOn` | boolean | false | Prevent idle shutdown |
| `idleTimeout` | number | 300 | Seconds before idle shutdown |
| `model` | string | "sonnet" | Claude model for the worker |
| `effort` | string | "medium" | Claude effort level |

## When to Use Worker Mode

| Scenario | Recommended Mode |
|----------|-----------------|
| One-off text processing | Standard |
| Batch processing (100+ items) | Standard |
| User-facing API (< 5s expected) | Worker (alwaysOn) |
| Conversational AI features | Worker |
| Background cron jobs | Standard |
| High-frequency same-preset calls | Worker |

## Limitations

- **Sequential processing**: Each worker handles one request at a time. For parallelism, create multiple workers.
- **Cold-start on awake**: ~16 seconds for session recreation after idle. Use `alwaysOn` for latency-sensitive endpoints.
- **tmux dependency**: Worker Mode requires tmux installed on the server.
- **Single-machine**: Workers are bound to the machine they're created on. No cross-machine distribution (yet).
