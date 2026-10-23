# API Specification

Base URL: `http://<private-host>:<port>/api/v1`

All requests and responses use `Content-Type: application/json`.

---

## Security

CSW has **no built-in authentication**, and several endpoints start or stop processes on the host. Treat the whole API as an administrative surface:

- **Never expose it to the public internet.** Run it on a private network, behind an authenticating proxy or an IP allowlist.
- **Input validation.** Worker names must match `^[a-z0-9][a-z0-9-]{0,31}$` (lowercase letters, digits and hyphens, max 32 characters). This is enforced on `POST /workers` and on every `/workers/:name` route; any other value returns `400`.
- **No shell strings.** Any value that reaches tmux or another command must be passed as a separate argv element, never interpolated into a command string.
- **Least privilege.** Run worker sessions under a dedicated unprivileged OS account (no sudo).

Endpoints marked **(admin)** below change server state; restrict them further if your proxy allows per-route rules.

---

## Process

The core endpoint. Handles all AI processing requests.

### POST /process

**Request Body:**

```json
{
  "input": "Your prompt or question",
  "sessionId": null,
  "systemPrompt": "Optional system prompt",
  "outputFormat": null,
  "presetId": null,
  "cacheKey": null,
  "cachePool": null,
  "cacheTtl": null,
  "options": {
    "model": "sonnet",
    "effort": "low",
    "worker": null
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `input` | string | Yes | The user's prompt or input text |
| `sessionId` | string/null | No | `null` = stateless, `"new"` = create session, `"uuid"` = resume session |
| `systemPrompt` | string | No | System-level instructions for Claude |
| `outputFormat` | object | No | JSON schema for structured output |
| `presetId` | string | No | UUID of a preset to use (overrides systemPrompt/options) |
| `cacheKey` | string | No | Cache key for response caching |
| `cachePool` | number | No | Pool target for Growing Pool Cache mode |
| `cacheTtl` | number | No | Cache TTL in seconds (omit for permanent) |
| `options.model` | string | No | Claude model: `"opus"`, `"sonnet"`, `"haiku"` (default: `"sonnet"`) |
| `options.effort` | string | No | Processing effort: `"low"`, `"medium"`, `"high"` (default: `"low"`, server setting `CLAUDE_EFFORT`) |
| `options.worker` | string | No | Worker name to use Worker Mode |

**Response:**

```json
{
  "success": true,
  "jobId": "550e8400-e29b-41d4-a716-446655440000",
  "sessionId": "660e8400-e29b-41d4-a716-446655440001",
  "result": "Claude's response text",
  "meta": {
    "durationMs": 8542,
    "model": "sonnet",
    "cached": false,
    "compacted": false,
    "worker": false
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `success` | boolean | Whether the request succeeded |
| `jobId` | string | Unique job identifier |
| `sessionId` | string/null | Session ID (if session mode) |
| `result` | string/object | The AI response (text or parsed JSON) |
| `meta.durationMs` | number | Processing time in milliseconds |
| `meta.model` | string | Model that served the request |
| `meta.cached` | boolean | Whether the response came from cache |
| `meta.compacted` | boolean | Whether conversation history was compacted for this request |
| `meta.worker` | boolean/string | Worker Mode flag (`false` for Standard Mode, otherwise the worker name) |

**Error Response:**

```json
{
  "success": false,
  "error": "Error description",
  "jobId": "550e8400-e29b-41d4-a716-446655440000"
}
```

### Usage Examples

**Stateless (one-off):**
```bash
curl -X POST /api/v1/process \
  -H "Content-Type: application/json" \
  -d '{
    "input": "Summarize the key points of quantum computing",
    "options": { "model": "haiku", "effort": "low" }
  }'
```

**With session (conversational):**
```bash
# Start a new session
curl -X POST /api/v1/process \
  -d '{
    "sessionId": "new",
    "systemPrompt": "You are a helpful coding assistant.",
    "input": "How do I sort an array in JavaScript?"
  }'
# Response includes sessionId: "abc-123..."

# Continue the conversation
curl -X POST /api/v1/process \
  -d '{
    "sessionId": "abc-123...",
    "input": "Now show me how to do it in Python"
  }'
```

**With structured output:**
```bash
curl -X POST /api/v1/process \
  -d '{
    "input": "Extract entities from: John works at Google in NYC",
    "outputFormat": {
      "type": "object",
      "properties": {
        "person": { "type": "string" },
        "company": { "type": "string" },
        "location": { "type": "string" }
      },
      "required": ["person", "company", "location"]
    }
  }'
# Response: { "person": "John", "company": "Google", "location": "NYC" }
```

**With caching (simple):**
```bash
curl -X POST /api/v1/process \
  -d '{
    "input": "Translate hello to Korean",
    "cacheKey": "translate:hello:ko",
    "cacheTtl": 86400
  }'
# First call: ~15s (AI processing)
# Subsequent calls: ~5ms (cached)
```

**With caching (pool):**
```bash
curl -X POST /api/v1/process \
  -d '{
    "input": "Generate a creative fortune about love",
    "cacheKey": "fortune:love:2026-04-08",
    "cachePool": 3,
    "cacheTtl": 86400
  }'
# Returns diverse responses from a growing pool
```

**With preset:**
```bash
curl -X POST /api/v1/process \
  -d '{
    "presetId": "c5f32e25-...",
    "input": "{ \"name\": \"Alice\", \"birthYear\": 1990 }"
  }'
```

**With Worker Mode:**
```bash
curl -X POST /api/v1/process \
  -d '{
    "input": "Analyze this code for bugs",
    "options": { "worker": "code-reviewer" }
  }'
```

---

## Sessions

### GET /sessions

List all sessions.

**Query Parameters:**
- `status` (string): Filter by status (`active`, `archived`). Default: `active`
- `limit` (number): Max results. Default: `50`
- `offset` (number): Pagination offset. Default: `0`

**Response:**
```json
{
  "success": true,
  "sessions": [
    {
      "id": "uuid",
      "name": "Session name",
      "status": "active",
      "messageCount": 12,
      "model": "sonnet",
      "createdAt": "2026-04-08T10:00:00.000Z",
      "updatedAt": "2026-04-08T10:30:00.000Z"
    }
  ],
  "total": 42
}
```

### GET /sessions/:id

Get a session with its message history.

**Response:**
```json
{
  "success": true,
  "session": {
    "id": "uuid",
    "name": "Session name",
    "summary": "Auto-generated summary",
    "status": "active",
    "messageCount": 12,
    "systemPrompt": "You are...",
    "model": "sonnet",
    "messages": [
      {
        "id": 1,
        "role": "user",
        "content": "Hello",
        "createdAt": "2026-04-08T10:00:00.000Z"
      },
      {
        "id": 2,
        "role": "assistant",
        "content": "Hi! How can I help?",
        "createdAt": "2026-04-08T10:00:15.000Z"
      }
    ]
  }
}
```

### POST /sessions/:id/archive

Archive a session. Archived sessions are retained but excluded from active queries.

**Response:**
```json
{
  "success": true,
  "message": "Session archived"
}
```

---

## Memory

Per-session key-value store injected into prompts as context.

### GET /sessions/:id/memory

Get all active memory entries for a session.

**Response:**
```json
{
  "success": true,
  "memory": [
    {
      "id": 1,
      "category": "rule",
      "keyName": "language",
      "value": "Always respond in Korean",
      "priority": 10,
      "isActive": true
    },
    {
      "id": 2,
      "category": "property",
      "keyName": "userName",
      "value": "Alice",
      "priority": 0,
      "isActive": true
    }
  ]
}
```

### POST /sessions/:id/memory

Create or update a memory entry (upsert on session + category + key).

**Request Body:**
```json
{
  "category": "rule",
  "keyName": "language",
  "value": "Always respond in Korean",
  "priority": 10
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `category` | string | Yes | `"rule"`, `"property"`, or `"action"` |
| `keyName` | string | Yes | Unique key within the category |
| `value` | string | Yes | The memory value |
| `priority` | number | No | Higher priority = injected first (default: `0`) |

---

## Presets

Reusable prompt templates with variable substitution.

### GET /presets

List all presets.

**Response:**
```json
{
  "success": true,
  "presets": [
    {
      "id": "uuid",
      "name": "Fortune Premium KR",
      "description": "Korean premium fortune reading",
      "tags": "fortune,kr,premium",
      "usageCount": 1542,
      "lastUsedAt": "2026-04-08T09:00:00.000Z"
    }
  ]
}
```

### POST /presets

Create a new preset.

**Request Body:**
```json
{
  "name": "Fortune Premium KR",
  "description": "Korean premium fortune reading",
  "systemPrompt": "You are a Korean fortune teller. Use the following birth data to generate a detailed fortune reading...",
  "outputFormat": null,
  "sampleInput": "{ \"name\": \"홍길동\", \"birthYear\": 1990 }",
  "sampleMemory": [
    { "category": "rule", "keyName": "style", "value": "Warm and encouraging" }
  ],
  "options": {
    "model": "sonnet",
    "effort": "high",
    "worker": "fortune-kr"
  },
  "tags": "fortune,kr,premium",
  "cachePoolTarget": 3
}
```

### GET /presets/:id

Get a single preset with full details.

### PUT /presets/:id

Update a preset. **(admin)**

### DELETE /presets/:id

Delete a preset. **(admin)**

### POST /presets/:id/run

Resolve a preset into a ready-to-send `/process` request body. Fields in the request body (`input`, `systemPrompt`, `outputFormat`, `memory`, `options`, `sessionId`) override the preset's values. Increments the preset's usage count. It does not call Claude itself; send the returned `request` to `POST /process`.

**Response:**
```json
{
  "success": true,
  "message": "Use /api/v1/process with the preset data below",
  "request": {
    "sessionId": null,
    "input": "...",
    "systemPrompt": "...",
    "outputFormat": null,
    "memory": [],
    "options": { "model": "sonnet", "worker": "fortune-kr" }
  }
}
```

### POST /presets/:id/generate-sample

Regenerate the preset's sample input with Claude and return the updated preset. **(admin)**

---

## Jobs

Every `/process` call is recorded as a job.

### GET /jobs

List recent jobs, newest first.

**Query Parameters:**
- `limit` (number): Max results. Default: `20`

**Response:**
```json
{
  "success": true,
  "jobs": [
    {
      "id": "uuid",
      "session_id": null,
      "status": "completed",
      "duration_ms": 8542,
      "created_at": "2026-04-08T10:00:00.000Z",
      "completed_at": "2026-04-08T10:00:08.542Z",
      "request_body": "{...}"
    }
  ]
}
```

### GET /jobs/:id

Get a single job. Returns `404` if it does not exist.

---

## Cache

### GET /cache/stats

Get cache statistics.

**Response:**
```json
{
  "success": true,
  "stats": {
    "totalKeys": 156,
    "simpleKeys": 42,
    "poolKeys": 114,
    "totalPoolEntries": 487,
    "totalHits": 12843,
    "expiredKeys": 3
  }
}
```

### GET /cache/:key

Get a specific cache entry.

### DELETE /cache/:key

Delete a specific cache entry and its pool entries. **(admin)**

### POST /cache/purge

Remove all expired cache entries. **(admin)**

**Response:**
```json
{
  "success": true,
  "purged": 3
}
```

---

## Workers

### POST /workers

Create a new worker. **(admin)**

**Request Body:**
```json
{
  "name": "fortune-kr",
  "presetId": "c5f32e25-...",
  "alwaysOn": true,
  "idleTimeout": 600000,
  "jobTimeout": 30000,
  "model": "sonnet",
  "effort": "low"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Must match `^[a-z0-9][a-z0-9-]{0,31}$`. Anything else returns `400` |
| `presetId` | string | No | Preset whose system prompt and options the worker uses |
| `alwaysOn` | boolean | No | Never idle out (default `false`) |
| `idleTimeout` | number | No | Milliseconds before an idle replica is stopped (default `600000`) |
| `jobTimeout` | number | No | Milliseconds before a request is treated as hung (default `30000`) |
| `model` / `effort` | string | No | Override the preset's model / effort |

Replica count and queue wait come from the preset options (`replicas`, default `1`; `queueTimeout`, default `60000` ms). Change the replica count later with `POST /workers/:name/scale`.

**Error Response (invalid name):**
```json
{
  "success": false,
  "error": "invalid worker name: must match ^[a-z0-9][a-z0-9-]{0,31}$"
}
```

### GET /workers

List all workers with their status.

**Response:**
```json
{
  "success": true,
  "workers": [
    {
      "name": "fortune-kr",
      "status": "online",
      "model": "sonnet",
      "alwaysOn": true,
      "replicaCount": 2,
      "busyReplicas": 1,
      "totalJobs": 542
    }
  ]
}
```

Worker `status` is one of `starting`, `online`, `busy`, `recovering`, `idle`, `offline`, derived from its replicas.

### GET /workers/:name

Get a single worker's status and details.

**Response:**
```json
{
  "success": true,
  "worker": {
    "name": "fortune-kr",
    "status": "online",
    "model": "sonnet",
    "effort": "low",
    "alwaysOn": true,
    "idleTimeout": 600000,
    "jobTimeout": 30000,
    "queueTimeout": 60000,
    "replicaCount": 2,
    "busyReplicas": 1,
    "replicas": [
      { "idx": 1, "status": "busy", "currentJobId": "uuid", "recoveryAttempts": 0 },
      { "idx": 2, "status": "online", "currentJobId": null, "recoveryAttempts": 0 }
    ],
    "totalJobs": 542,
    "totalErrors": 3
  }
}
```

### POST /workers/:name/wake

Wake an idle worker, restarting its sleeping replicas so it is ready to serve the next request. If the worker is already `online` or `busy`, nothing changes.

**Response:**
```json
{
  "success": true,
  "message": "Worker fortune-kr: 2 replica(s) waking up"
}
```

### POST /workers/:name/scale

Set the number of replicas (parallel tmux sessions) for a worker. Scaling up starts new replicas (staggered by 3 seconds); scaling down stops replicas from the tail. **(admin)**

**Request Body:**
```json
{ "replicas": 3 }
```

`replicas` must be `>= 1`, otherwise `400`.

**Response:**
```json
{
  "success": true,
  "replicas": 3,
  "changed": true
}
```

### POST /workers/:name/restart

Restart a worker (tear down and recreate the tmux sessions of all its replicas). Used to recover a hung or errored worker. **(admin)**

**Response:**
```json
{
  "success": true,
  "message": "Worker fortune-kr restart initiated"
}
```

### DELETE /workers/:name

Destroy a worker and the tmux sessions of all its replicas. **(admin)**

---

## Health

### GET /health

Server health check. `status` is `ok` when the Claude CLI responds to a version check, and `degraded` when it does not: the server is up, but requests that need Claude will fail.

**Response:**
```json
{
  "status": "ok",
  "service": "csw",
  "timestamp": "2026-04-08T10:00:00.000Z",
  "claude": {
    "ok": true,
    "checkedAt": "2026-04-08T09:59:30.000Z",
    "error": null,
    "version": "x.y.z"
  }
}
```
