# System Architecture

## Overview

CSW (Claude Subscription Worker) is a Node.js API server that wraps the Claude CLI (`claude -p`) into a REST API. It manages sessions, caching, presets, and worker lifecycles to turn a flat-rate Claude subscription into a production AI processing backend.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     Client Applications                  │
│              (Backend services, admin tools)              │
└──────────────────────┬──────────────────────────────────┘
                       │ REST API (HTTPS)
                       ▼
┌─────────────────────────────────────────────────────────┐
│                   CSW API Server                         │
│                   (Express.js)                           │
│                                                         │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌───────────┐ │
│  │  Prompt   │ │ Response │ │  Cache   │ │  Preset   │ │
│  │ Builder   │ │  Parser  │ │ Manager  │ │  Manager  │ │
│  └──────────┘ └──────────┘ └──────────┘ └───────────┘ │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌───────────┐ │
│  │ Session  │ │  Memory  │ │   Job    │ │ Compactor │ │
│  │ Manager  │ │  Manager │ │  Manager │ │           │ │
│  └──────────┘ └──────────┘ └──────────┘ └───────────┘ │
└──────────┬───────────────────────────┬──────────────────┘
           │                           │
    ┌──────▼──────┐            ┌───────▼──────┐
    │  Standard   │            │  Worker Mode │
    │    Mode     │            │     (v2)     │
    │             │            │              │
    │ claude -p   │            │ tmux session │
    │ per request │            │ + inbox/     │
    │             │            │   outbox     │
    └──────┬──────┘            └───────┬──────┘
           │                           │
           └─────────┬─────────────────┘
                     ▼
              ┌──────────────┐
              │  Claude CLI  │
              │  (claude -p) │
              └──────────────┘
                     │
           ┌─────────▼──────────┐
           │      MySQL DB      │
           │                    │
           │  sessions          │
           │  messages          │
           │  memory            │
           │  jobs              │
           │  presets           │
           │  response_cache    │
           │  response_cache_pool│
           └────────────────────┘
```

## Request Flow

### Standard Mode (stateless)

```
1. Client sends POST /api/v1/process
2. Prompt Builder assembles: system prompt + memory + history + user input
3. Cache Manager checks for cached response
   → Cache hit: return immediately (~5ms)
   → Cache miss: continue
4. Claude Executor spawns: claude -p "assembled prompt" --output-format text
5. Response Parser extracts text/JSON/structured output
6. Cache Manager stores response (if cacheKey provided)
7. Session Manager saves messages (if session mode)
8. Return response to client
```

### Worker Mode (persistent session)

```
1. Client sends POST /api/v1/process with options.worker
2. Worker Manager finds or creates tmux worker
3. Job written to inbox/{jobId}.json
4. tmux send-keys triggers Claude to read inbox
5. Worker Manager polls outbox/{jobId}.json (100ms interval)
6. Claude writes response to outbox
7. Worker Manager reads outbox, sends /clear to reset
8. Return response to client
```

## Module Responsibilities

### Prompt Builder
Assembles the final prompt from multiple sources:
- **System prompt**: From request, preset, or session default
- **Memory**: Key-value pairs in 3 categories (rule, property, action) injected as context
- **History**: Previous conversation messages (excluding compacted ones)
- **User input**: The actual request content

### Response Parser
Handles three output formats:
- **Text**: Raw text response (default)
- **JSON**: Parsed JSON from `--output-format json`
- **Structured**: JSON schema-validated output via `--json-schema`

### Cache Manager
Two caching strategies:
- **Simple**: One response per cache key. First call generates, subsequent calls return cached.
- **Pool**: Growing pool of responses per key. Uses the [Growing Pool Cache](https://github.com/nskit-io/growing-pool-cache) pattern where the pool expands based on hit frequency.

### Session Manager
- Creates UUID-based sessions
- Tracks messages with roles (user/assistant/system)
- Supports session archival
- Provides message history for prompt assembly

### Memory Manager
Per-session key-value store with categories:
- **rule**: Instructions the AI should follow ("Always respond in Korean")
- **property**: Context about the user/environment ("User's birth year: 1990")
- **action**: Behavioral directives ("When asked about health, add a disclaimer")

### Compactor
When a session's message count exceeds the threshold (default: 20), older messages are summarized using a lightweight model (Haiku). The summary replaces the original messages, keeping the context window manageable while preserving essential information.

### Job Manager
Tracks every processing request with status (queued/processing/completed/failed/timeout), request/response bodies, duration, and error details.

## Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `PORT` | Server port | `5900` |
| `DB_HOST` | MySQL host | `localhost` |
| `DB_PORT` | MySQL port | `3306` |
| `DB_USER` | MySQL user | `csw` |
| `DB_PASSWORD` | MySQL password | `***` |
| `DB_NAME` | Database name | `csw` |
| `CLAUDE_MODEL` | Default model | `sonnet` |
| `CSW_WORKER_USER` | OS user for tmux workers | `nskit` |

## Key Design Decisions

### Why `claude -p` instead of the API?

Cost. A $200/month subscription handles the same workload that would cost $900-4,500/month via API. The tradeoff is throughput (sequential CLI calls vs parallel API calls), but for most use cases, CSW's caching and worker mode compensate for this.

### Why tmux for Worker Mode?

tmux provides process persistence without custom IPC. The inbox/outbox file-based communication is dead simple to debug (just `cat` the files), survives network interruptions, and requires zero dependencies beyond tmux itself.

### Why MySQL instead of Redis/SQLite?

Sessions and messages need durability. Redis is used by the host application (NSKit) for ephemeral session data, but CSW's conversation history and presets need to survive restarts. MySQL also provides the JSON column type used for structured preset options and output formats.

### Why strip the CLAUDECODE env var?

When CSW runs inside a Claude Code session, the `CLAUDECODE` environment variable causes `claude -p` to try connecting to the parent session instead of starting fresh. Removing it prevents nested session conflicts.
