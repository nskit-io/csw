# CSW (Claude Subscription Worker)

**Turn a $200/month Claude subscription into a scalable AI processing API.**

[🇰🇷 한국어](./README.ko.md) · [🇯🇵 日本語](./README.ja.md) · [🇨🇳 中文](./README.zh.md)

[Architecture](./architecture/overview.md) | [Worker Mode](./architecture/worker-mode.md) | [API Spec](./reference/api-spec.md) | [Schema](./reference/schema.sql)

> Infrastructure component of [**NSKit**](https://github.com/nskit-io/nskit-io) — *bound by structure, free to combine.* CSW powers the AI processing layer behind NSKit's production services, turning subscription-tier Claude into cost-efficient back-end capability.

---

## The Problem

Claude API pricing is pay-per-token:

| Model | Input | Output |
|-------|-------|--------|
| Opus | $15/M tokens | $75/M tokens |
| Sonnet | $3/M tokens | $15/M tokens |
| Haiku | $0.25/M tokens | $1.25/M tokens |

A Claude Max subscription costs **$200/month** for unlimited\* usage via the CLI (`claude -p`).

**CSW bridges this gap.** It wraps the Claude CLI into a REST API server, turning your subscription into a production AI backend.

> \*Subject to Anthropic's fair use policy. CSW is designed for legitimate processing workloads, not abuse.

## Cost Comparison

Real-world math for a service handling **1,000 requests/day** (~30,000/month), averaging ~2,000 tokens per request:

| Approach | Monthly Cost | Cost/Request |
|----------|-------------|--------------|
| Claude API (Opus) | ~$4,500 | ~$0.15 |
| Claude API (Sonnet) | ~$900 | ~$0.03 |
| **CSW (subscription)** | **$200** | **~$0.007** |

That's **4.5-22x cheaper** for equivalent work. With response caching enabled, effective cost drops even further since cached responses cost nothing.

<img src="https://mermaid.ink/img/eHljaGFydC1iZXRhCiAgICB0aXRsZSAiTW9udGhseSBDb3N0OiBBUEkgdnMgQ1NXICgxMDAwIHJlcS9kYXkpIgogICAgeC1heGlzIFsiQ2xhdWRlIEFQSTxici8-T3B1cyIsICJDbGF1ZGUgQVBJPGJyLz5Tb25uZXQiLCAiQ1NXPGJyLz5TdGFuZGFyZCIsICJDU1c8YnIvPldvcmtlciJdCiAgICB5LWF4aXMgIk1vbnRobHkgQ29zdCAoJCkiIDAgLS0-IDUwMDAKICAgIGJhciBbNDUwMCwgOTAwLCAyMDAsIDIwMF0K" alt="Monthly Cost: API vs CSW" />

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
When conversation messages exceed a threshold, older messages are automatically summarized using a lightweight model (Haiku), keeping context windows manageable.

### Worker Health Monitoring
30-second health checks, automatic restart on hang detection, staggered recovery on server reboot, and configurable idle/awake lifecycle.

## API Overview

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/v1/process` | Process an AI request (stateless, new session, or existing session) |
| `GET` | `/api/v1/sessions` | List sessions |
| `GET` | `/api/v1/sessions/:id` | Get session with messages |
| `POST` | `/api/v1/sessions/:id/archive` | Archive a session |
| `GET/POST` | `/api/v1/sessions/:id/memory` | Get/set session memory |
| `GET/POST` | `/api/v1/presets` | List/create presets |
| `GET/PUT/DELETE` | `/api/v1/presets/:id` | CRUD preset |
| `GET` | `/api/v1/cache/stats` | Cache statistics |
| `POST` | `/api/v1/cache/purge` | Purge expired cache |
| `POST` | `/api/v1/workers` | Create a worker (Worker Mode) |
| `GET` | `/api/v1/workers` | List workers |
| `DELETE` | `/api/v1/workers/:name` | Destroy a worker |

See the full [API Specification](./reference/api-spec.md) for request/response schemas and examples.

## Production Use

CSW powers the AI backend for [NewMyoung](https://newmyoung.com) -- an AI-powered fortune and naming service operating across Korea, Japan, and Chinese-speaking regions (Taiwan, Singapore, Macau, Malaysia, Hong Kong):

- **9 presets** handling fortune readings, fortune cookies, and divination queries
- **tmux-based workers** with `alwaysOn` for user-facing endpoints
- **Growing Pool Cache** ensuring diverse AI-generated fortunes (no two users see the same reading)
- **17,000+ requests/month** served at ~$0.01/request effective cost

## Build Your Own

This repository provides the **concept and reference architecture**. The production CSW runs at csw.nskit.io, but the patterns here are general-purpose.

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
