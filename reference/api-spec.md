# API Specification

Base URL: `https://your-csw-instance/api/v1`

All requests and responses use `Content-Type: application/json`.

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
    "effort": "medium",
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
| `options.effort` | string | No | Processing effort: `"low"`, `"medium"`, `"high"` (default: `"medium"`) |
| `options.worker` | string | No | Worker name to use Worker Mode |

**Response:**

```json
{
  "success": true,
  "jobId": "550e8400-e29b-41d4-a716-446655440000",
  "sessionId": "660e8400-e29b-41d4-a716-446655440001",
  "response": "Claude's response text",
  "cached": false,
  "duration": 8542
}
```

| Field | Type | Description |
|-------|------|-------------|
| `success` | boolean | Whether the request succeeded |
| `jobId` | string | Unique job identifier |
| `sessionId` | string/null | Session ID (if session mode) |
| `response` | string/object | The AI response (text or parsed JSON) |
| `cached` | boolean | Whether the response came from cache |
| `duration` | number | Processing time in milliseconds |

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

Update a preset.

### DELETE /presets/:id

Delete a preset.

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

Delete a specific cache entry and its pool entries.

### POST /cache/purge

Remove all expired cache entries.

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

Create a new worker.

**Request Body:**
```json
{
  "name": "fortune-kr",
  "presetId": "c5f32e25-...",
  "alwaysOn": true,
  "idleTimeout": 300,
  "model": "sonnet"
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
      "status": "ready",
      "presetId": "c5f32e25-...",
      "alwaysOn": true,
      "requestCount": 542,
      "lastRequestAt": "2026-04-08T09:30:00.000Z",
      "createdAt": "2026-04-07T00:00:00.000Z"
    }
  ]
}
```

### DELETE /workers/:name

Destroy a worker and its tmux session.

---

## Health

### GET /health

Server health check.

**Response:**
```json
{
  "status": "ok",
  "uptime": 864000,
  "workers": {
    "total": 9,
    "ready": 8,
    "processing": 1,
    "idle": 0
  },
  "db": "connected",
  "version": "2.0.0"
}
```
