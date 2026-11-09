# Caching Strategy

CSW implements two complementary caching strategies to reduce AI processing costs and improve response times.

## Simple Cache (1:1)

The simplest form: one response per cache key.

```
Request with cacheKey="greeting:en"
  → Cache miss → Call Claude → Store response → Return
  → Cache hit  → Return stored response (~5ms)
```

### When to Use
- Deterministic outputs (translations, classifications, structured extraction)
- Responses that don't need variety
- High-frequency identical requests

### Configuration
```json
{
  "input": "Translate 'hello' to Korean",
  "cacheKey": "translate:hello:ko",
  "cacheTtl": 86400
}
```

- `cacheKey`: Unique identifier for the cached response
- `cacheTtl`: Time-to-live in seconds (optional, omit for permanent cache)

## Pool Cache (Growing Pool)

For AI-generated content where diversity matters -- you don't want every call to return the same fortune text or creative writing.

Pool Cache uses the [Growing Pool Cache](https://github.com/nskit-io/growing-pool-cache) pattern:

```
Request with cacheKey="fortune:love" + cachePool=3
  → Cache miss     → Call Claude → Store Response A (pool size: 1) → Return A
  → Cache hit (1)  → Return A (hit_count: 1)
  → Cache hit (2)  → Return A (hit_count: 2)
  → Cache hit (3)  → Return A, trigger background growth
                     → Call Claude → Store Response B (pool size: 2)
  → Cache hit (4)  → Random pick: A or B
  → ...eventually  → B hits 3 → Store Response C (pool size: 3)
  → Cache hit (N)  → Random pick from growing pool of responses
```

### Why It Works

The pool self-regulates:
- **High-traffic keys** accumulate diverse responses quickly
- **Low-traffic keys** stay small (no wasted AI calls)
- **Growth decelerates** naturally as random distribution spreads hits across more entries

With `poolTarget=3`:

| Pool Size | Avg Requests to Trigger Growth |
|-----------|-------------------------------|
| 1 | 3 |
| 2 | 6 |
| 5 | 15 |
| 10 | 30 |

At 1,000 requests served, a pool makes roughly 25-30 AI calls (with `poolTarget=3`, reaching pool size k takes about 1.5 x k x (k-1) requests). That is **~97% fewer AI calls** than calling the model every time, while maintaining response diversity. (Calculated from the growth rule above, not a measured benchmark.)

### Configuration

```json
{
  "input": "Generate a love fortune for today",
  "cacheKey": "fortune:love:2026-04-08",
  "cachePool": 3,
  "cacheTtl": 86400
}
```

- `cachePool`: The hit threshold (N) before triggering pool growth. Lower = faster growth, higher = more cost-efficient.

### Database Structure

Pool cache uses two tables:

**response_cache** (metadata + simple mode):
```
cache_key    | response      | hit_count | pool_target | pool_size | is_growing
-------------|---------------|-----------|-------------|-----------|----------
fortune:love | "You will..." | 15        | 3           | 4         | 0
```

**response_cache_pool** (individual pool entries):
```
cache_key    | response           | hit_count
-------------|--------------------|---------
fortune:love | "Love awaits..."   | 8
fortune:love | "Your heart..."    | 4
fortune:love | "A new chapter..." | 2
fortune:love | "Stars align..."   | 1
```

## Cache Invalidation

| Method | Endpoint |
|--------|----------|
| Delete specific key | `DELETE /api/v1/cache/:key` |
| Purge expired entries | `POST /api/v1/cache/purge` |
| View stats | `GET /api/v1/cache/stats` |

## Choosing a Strategy

| Use Case | Strategy | poolTarget |
|----------|----------|------------|
| Translation / extraction | Simple | - |
| Fortune readings | Pool | 3-5 |
| Creative writing | Pool | 2-3 |
| Name suggestions | Pool | 3-5 |
| Classification | Simple | - |
| Summarization | Simple | - |

## npm Package

The Growing Pool Cache pattern is available as a standalone npm package for use in any Node.js application:

```bash
npm install growing-pool-cache
```

See [growing-pool-cache on GitHub](https://github.com/nskit-io/growing-pool-cache) for full documentation.
