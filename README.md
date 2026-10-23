# CSW (Claude Subscription Worker)

**Turn a flat-rate Claude subscription into a scalable AI processing API.**

[🇰🇷 한국어](./README.ko.md) · [🇯🇵 日本語](./README.ja.md) · [🇨🇳 中文](./README.zh.md)

[Architecture](./architecture/overview.md) | [Worker Mode](./architecture/worker-mode.md) | [API Spec](./reference/api-spec.md) | [Schema](./reference/schema.sql)

> Infrastructure component of [**NSKit**](https://github.com/nskit-io/nskit-io) — *bound by structure, free to combine.* CSW powers the AI processing layer behind NSKit's production services, turning subscription-tier Claude into cost-efficient back-end capability.

---

## The Problem

The Claude API is billed **per token**: every request is metered on its input and output, so the bill grows in step with volume.

A Claude subscription is billed as a **flat monthly fee** and can be used from the CLI (`claude -p`) within the plan's usage limits.

**CSW bridges this gap.** It wraps the Claude CLI into a REST API server, so steady, cacheable back-end workloads can run on a flat-rate subscription instead of a metered bill.

> Current API prices and plan details: [anthropic.com/pricing](https://www.anthropic.com/pricing). Subscription use is subject to Anthropic's usage policies and plan limits. CSW is designed for legitimate processing workloads, not abuse.

## Cost Model

Exact prices change, so this README does not pin numbers. The trade-off is structural:

| | Pay-per-token API | Flat subscription via CSW |
|---|---|---|
| Cost shape | Grows linearly with tokens processed | Fixed per month |
| Throughput | Parallel, limited by API rate tiers | Bounded by plan limits and the number of worker sessions |
| Fits best | Spiky or low volume, strict SLAs | Steady volume, repeatable prompts, cacheable responses |

With response caching enabled, a cache hit does not call Claude at all, so steady workloads get cheaper per request over time.

## Architecture

<img src="https://mermaid.ink/img/Zmxvd2NoYXJ0IFRCCiAgICBDbGllbnRbIkNsaWVudCBBcHBsaWNhdGlvbiJdCiAgICBDU1dbIkNTVyBBUEkgU2VydmVyPGJyLz4oRXhwcmVzcy5qcykiXQogICAgV01bIldvcmtlciBNYW5hZ2VyIl0KICAgIFNNWyJTdGFuZGFyZCBNb2RlPGJyLz5jbGF1ZGUgLXAgcGVyIHJlcXVlc3QiXQogICAgVE1VWFsiV29ya2VyIE1vZGUgdjI8YnIvPnRtdXggcGVyc2lzdGVudCBzZXNzaW9uIl0KICAgIERCWygiTXlTUUw8YnIvPnNlc3Npb25zLCBtZXNzYWdlcyw8YnIvPm1lbW9yeSwgcHJlc2V0cywgY2FjaGUiKV0KICAgIENMQVVERVsiQ2xhdWRlIENMSTxici8-KGNsYXVkZSAtcCkiXQoKICAgIENsaWVudCAtLT58UkVTVCBBUEl8IENTVwogICAgQ1NXIC0tPnxvcHRpb25zLndvcmtlcnwgV00KICAgIENTVyAtLT58bm8gd29ya2VyfCBTTQogICAgV00gLS0-fGluYm94L291dGJveHwgVE1VWAogICAgVE1VWCAtLT4gQ0xBVURFCiAgICBTTSAtLT4gQ0xBVURFCiAgICBDU1cgLS0-IERCCg==" alt="CSW Architecture Overview" />

CSW operates in two modes:

### Standard Mode

Stateless processing. Each request spawns a new `claude -p` process, executes, and returns.

- **Pros**: Simple, reliable, no state management
- **Cons**: Cold-start overhead (~14-40s per request), no conversation context
- **Best for**: One-off processing tasks, batch jobs

### Worker Mode (v2)

Persistent tmux-based sessions. Claude stays running in a tmux session, receiving commands via file-based inbox/outbox.

- **Pros**: 2.5x faster (no cold-start), maintains conversation context, supports `alwaysOn`
- **Cons**: More complex lifecycle management, ~16s initial session creation
- **Best for**: User-facing APIs, conversational workflows, high-frequency requests

See [Worker Mode Architecture](./architecture/worker-mode.md) for the full lifecycle.

## Key Features

### Session Management
Create and resume conversations with full message history. MySQL-backed sessions with automatic message tracking.

### Response Caching
Two strategies for different needs:
- **Simple mode**: 1:1 cache. Same key always returns the same response.
- **Pool mode**: Uses [Growing Pool Cache](https://github.com/nskit-io/growing-pool-cache) -- each cache key grows a pool of diverse AI responses that expands based on demand.

### Preset System
Reusable prompt templates with variable substitution. Define a system prompt, output format, and options once, then invoke by preset ID.

### Prompt Assembly
System prompt + memory entries (rules, properties, actions) + conversation history, all assembled automatically before each request.

### Response Parsing
Supports text, JSON, and structured output with JSON schema validation. Claude's `--output-format json` + `--json-schema` when a schema is provided.

### History Compaction
When conversation messages exceed a threshold, older messages are automatically summarized by a designated general-purpose worker, keeping context windows manageable.

### Replicas and Queueing
A worker can run several replicas (parallel tmux sessions). When every replica is busy, a request waits in a queue (default up to 60s) instead of failing immediately.

### Worker Health Monitoring
30-second health checks, automatic restart on hang detection, staggered recovery on server reboot, and a configurable idle/wake lifecycle.

## API Overview

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/v1/process` | Process an AI request (stateless, new session, or existing session) |
| `GET` | `/api/v1/sessions` | List sessions |
| `GET` | `/api/v1/sessions/:id` | Get session with messages |
| `POST` | `/api/v1/sessions/:id/archive` | Archive a session |
| `GET/POST` | `/api/v1/sessions/:id/memory` | Get/set session memory |
| `GET/POST` | `/api/v1/presets` | List/create presets |
| `GET/PUT/DELETE` | `/api/v1/presets/:id` | CRUD preset (admin) |
| `POST` | `/api/v1/presets/:id/run` | Resolve a preset into a ready-to-send `/process` request body |
| `POST` | `/api/v1/presets/:id/generate-sample` | Regenerate a preset's sample input (admin) |
| `GET` | `/api/v1/jobs` | List recent jobs |
| `GET` | `/api/v1/jobs/:id` | Get a job |
| `GET` | `/api/v1/cache/stats` | Cache statistics |
| `GET/DELETE` | `/api/v1/cache/:key` | Inspect / delete a cache entry (delete = admin) |
| `POST` | `/api/v1/cache/purge` | Purge expired cache (admin) |
| `POST` | `/api/v1/workers` | Create a worker (admin) |
| `GET` | `/api/v1/workers` | List workers |
| `GET` | `/api/v1/workers/:name` | Get a single worker's status |
| `POST` | `/api/v1/workers/:name/wake` | Wake an idle worker |
| `POST` | `/api/v1/workers/:name/scale` | Set a worker's replica count (admin) |
| `POST` | `/api/v1/workers/:name/restart` | Restart a worker (admin) |
| `DELETE` | `/api/v1/workers/:name` | Destroy a worker (admin) |

"Admin" endpoints change server state (workers run processes on the host). Keep the whole API on a private network — see [Security](#security).

See the full [API Specification](./reference/api-spec.md) for request/response schemas and examples.

## Security

CSW drives a CLI and tmux sessions on its host, so treat its API as an administrative surface:

- **Never expose it to the public internet.** Run it on a private network, and put an authenticating proxy or IP allowlist in front of it. The reference server has no built-in authentication.
- **Validate every identifier that reaches the host.** Worker names must match an allowlist pattern (`^[a-z0-9][a-z0-9-]{0,31}$`); anything else is rejected with `400`.
- **Execute with argv, never a shell string.** Pass values to `tmux` and other commands as separate arguments (`execFile`-style), never by interpolating them into a command line.
- **Run workers under an unprivileged account.** A dedicated OS user with no sudo rights and access only to the workers directory.

See [API Specification — Security](./reference/api-spec.md#security) and [Worker Mode — Hardening](./architecture/worker-mode.md#hardening).

## Production Use

CSW powers the AI backend for [NewMyoung](https://newmyoung.com) -- an AI-powered fortune and naming service operating across Korea, Japan, and Chinese-speaking regions (Taiwan, Singapore, Macau, Malaysia, Hong Kong):

- **Per-language presets** handling fortune readings, fortune cookies, and divination queries
- **tmux-based workers** with `alwaysOn` for user-facing endpoints
- **Growing Pool Cache** ensuring diverse AI-generated fortunes (no two users see the same reading)

## Build Your Own

This repository provides the **concept and reference architecture**. The production instance is privately operated on an internal network; the patterns here are general-purpose.

You can:

1. **Use this as a blueprint** to build your own CLI-to-API wrapper for any AI provider with a CLI tool
2. **Adopt the Worker Mode pattern** -- tmux-based persistent sessions with inbox/outbox file communication work for any long-running CLI process
3. **Use the caching strategy** -- install [growing-pool-cache](https://www.npmjs.com/package/growing-pool-cache) from npm for the pool caching pattern
4. **Copy the database schema** -- the [reference schema](./reference/schema.sql) covers sessions, messages, memory, presets, and response caching

### Tech Stack (Reference)

| Component | Technology |
|-----------|-----------|
| API Server | Node.js + Express |
| AI Backend | Claude CLI (`claude -p`) |
| Worker Sessions | tmux |
| Database | MySQL 8 |
| Process Manager | systemd / PM2 |

## Related Projects

- [growing-pool-cache](https://github.com/nskit-io/growing-pool-cache) -- Self-growing cache pool for AI-generated content (npm package)
- [ai-native-design](https://github.com/nskit-io/ai-native-design) -- AI-Native Design philosophy for building AI-collaborative frameworks
- [NSKit](https://nskit.io) -- The AI-native web framework that CSW was built to serve

## License

CC BY-NC-SA 4.0 — see [LICENSE](LICENSE)
