# API Contracts

**Version:** 1.0
**Last Updated:** 2025-11-02

This document defines the API contracts between Hub and Generator services, as well as the public API exposed to end users.

## Table of Contents

1. [Hub → Generator (Internal)](#hub--generator-internal)
2. [Generator → Hub (Callback)](#generator--hub-callback)
3. [Public API (Users → Hub)](#public-api-users--hub)

---

## Hub → Generator (Internal)

### Process Episode

**Endpoint:** `POST /process`

**Authentication:** OIDC token via Cloud Tasks

**Description:** Triggers episode processing in Generator service

**Request Headers:**
```
Authorization: Bearer {OIDC_TOKEN}
Content-Type: application/json
```

**Request Body:**
```json
{
  "episode_id": 123,
  "podcast_id": "podcast_abc123",
  "title": "Episode Title",
  "author": "Author Name",
  "description": "Episode description",
  "staging_path": "staging/episode-title-20251102.md"
}
```

**Request Fields:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `episode_id` | integer | No | Hub's database ID for the episode. If provided, Generator will callback to Hub on completion/failure. If omitted, no callback is made (backward compatible with direct API usage). |
| `podcast_id` | string | Yes | GCS podcast identifier (e.g., `podcast_abc123`) |
| `title` | string | Yes | Episode title |
| `author` | string | Yes | Episode author |
| `description` | string | Yes | Episode description |
| `staging_path` | string | Yes | Path to markdown file in GCS (relative to podcast directory) |

**Success Response (200 OK):**
```json
{
  "status": "success",
  "message": "Episode processing started"
}
```

**Error Responses:**

**401 Unauthorized:**
```json
{
  "status": "error",
  "message": "Invalid or missing OIDC token"
}
```

**400 Bad Request:**
```json
{
  "status": "error",
  "message": "Missing required field: podcast_id"
}
```

**500 Internal Server Error:**
```json
{
  "status": "error",
  "message": "Failed to download staging file from GCS"
}
```

**Processing Flow:**
1. Validate OIDC token
2. Validate request payload
3. Download markdown from GCS staging path
4. Convert markdown to plain text
5. Generate TTS audio
6. Upload audio to GCS
7. Update manifest.json
8. Regenerate feed.xml
9. Delete staging file
10. Callback to Hub with completion status

**Retry Behavior:**
- Cloud Tasks automatically retries on 5xx errors
- Max retries: 3
- Backoff: Exponential (1s, 2s, 4s)

---

## Generator → Hub (Callback)

### Mark Episode Complete

**Endpoint:** `POST /api/internal/episodes/:episode_id/complete`

**Authentication:** Shared secret

**Description:** Notifies Hub that episode processing is complete

**Request Headers:**
```
X-Generator-Secret: {GENERATOR_CALLBACK_SECRET}
Content-Type: application/json
```

**Request Body:**
```json
{
  "gcs_episode_id": "episode-abc123",
  "audio_size_bytes": 5242880
}
```

**Request Fields:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `gcs_episode_id` | string | Yes | Episode identifier in GCS (used in filename) |
| `audio_size_bytes` | integer | Yes | Size of generated MP3 file |
| `duration_seconds` | integer | No | **Not currently implemented.** Reserved for future MP3 duration parsing. |

**Success Response (200 OK):**
```json
{
  "status": "success",
  "message": "Episode marked as complete"
}
```

**Error Responses:**

**401 Unauthorized:**
```json
{
  "status": "error",
  "message": "Invalid or missing generator secret"
}
```

**404 Not Found:**
```json
{
  "status": "error",
  "message": "Episode not found"
}
```

**422 Unprocessable Entity:**
```json
{
  "status": "error",
  "message": "Episode is not in processing state"
}
```

**Processing Flow:**
1. Validate `X-Generator-Secret` header
2. Find episode by `episode_id`
3. Update episode:
   - `status` = `complete`
   - `gcs_episode_id` = from request
   - `audio_size_bytes` = from request
4. Return success

**Retry Behavior:**
- Generator does NOT retry on failure
- Hub can detect stale "processing" episodes via timeout

### Mark Episode Failed

**Endpoint:** `POST /api/internal/episodes/:episode_id/failed`

**Authentication:** Shared secret

**Description:** Notifies Hub that episode processing failed

**Request Headers:**
```
X-Generator-Secret: {GENERATOR_CALLBACK_SECRET}
Content-Type: application/json
```

**Request Body:**
```json
{
  "episode_id": 123,
  "status": "failed",
  "error_message": "TTS API rate limit exceeded"
}
```

**Request Fields:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `episode_id` | integer | Yes | Hub's database ID for the episode |
| `status` | string | Yes | Always "failed" |
| `error_message` | string | Yes | Human-readable error description |

**Success Response (200 OK):**
```json
{
  "status": "success",
  "message": "Episode marked as failed"
}
```

---

## Public API (Users → Hub)

### Authentication

All API endpoints require authentication via API key:

```
Authorization: Bearer {API_KEY}
```

API keys are generated from the Hub web UI.

### Rate Limiting

- **Limit:** 1 request per minute per API key
- **Header:** `X-RateLimit-Remaining: 0` (included in responses)
- **Error (429):** Returned when rate limit exceeded

---

### Create Episode

**Endpoint:** `POST /api/v1/episodes`

**Authentication:** API Key (Bearer token)

**Description:** Submit a new episode for processing

**Request Headers:**
```
Authorization: Bearer {API_KEY}
Content-Type: multipart/form-data
```

**Request Body (multipart/form-data):**
```
title: Episode Title
author: Author Name
description: Episode description
content: @file.md (file upload)
```

**Request Fields:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `title` | string | Yes | Episode title (max 255 chars) |
| `author` | string | Yes | Episode author (max 255 chars) |
| `description` | string | Yes | Episode description (max 1000 chars) |
| `content` | file | Yes | Markdown file upload (max 10MB) |

**Success Response (201 Created):**
```json
{
  "episode": {
    "id": 123,
    "title": "Episode Title",
    "author": "Author Name",
    "description": "Episode description",
    "status": "pending",
    "created_at": "2025-11-02T10:30:00Z"
  }
}
```

**Error Responses:**

**401 Unauthorized:**
```json
{
  "error": "Invalid or missing API key"
}
```

**422 Unprocessable Entity:**
```json
{
  "error": "Validation failed",
  "details": {
    "title": ["can't be blank"],
    "content": ["file too large (max 10MB)"]
  }
}
```

**429 Too Many Requests:**
```json
{
  "error": "Rate limit exceeded",
  "retry_after": 45
}
```

**Example curl:**
```bash
curl -X POST https://hub.example.com/api/v1/episodes \
  -H "Authorization: Bearer pk_live_abc123..." \
  -F "title=My Episode" \
  -F "author=John Doe" \
  -F "description=An interesting episode" \
  -F "content=@article.md"
```

---

### Get Episode

**Endpoint:** `GET /api/v1/episodes/:id`

**Authentication:** API Key (Bearer token)

**Description:** Retrieve episode details and status

**Request Headers:**
```
Authorization: Bearer {API_KEY}
```

**Success Response (200 OK):**
```json
{
  "episode": {
    "id": 123,
    "title": "Episode Title",
    "author": "Author Name",
    "description": "Episode description",
    "status": "complete",
    "audio_size_bytes": 5242880,
    "duration_seconds": 600,
    "audio_url": "https://storage.googleapis.com/.../episodes/episode-abc123.mp3",
    "created_at": "2025-11-02T10:30:00Z",
    "completed_at": "2025-11-02T10:35:00Z"
  }
}
```

**Status Values:**
- `pending`: Episode created, not yet processing
- `processing`: Currently generating audio
- `complete`: Audio generated and published to feed
- `failed`: Processing failed (see `error_message`)

**Error Responses:**

**401 Unauthorized:**
```json
{
  "error": "Invalid or missing API key"
}
```

**404 Not Found:**
```json
{
  "error": "Episode not found"
}
```

**Example curl:**
```bash
curl https://hub.example.com/api/v1/episodes/123 \
  -H "Authorization: Bearer pk_live_abc123..."
```

---

### List Episodes

**Endpoint:** `GET /api/v1/episodes`

**Authentication:** API Key (Bearer token)

**Description:** List all episodes for the authenticated user's podcast

**Request Headers:**
```
Authorization: Bearer {API_KEY}
```

**Query Parameters:**
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `page` | integer | No | 1 | Page number |
| `per_page` | integer | No | 20 | Results per page (max 100) |
| `status` | string | No | all | Filter by status: `pending`, `processing`, `complete`, `failed` |

**Success Response (200 OK):**
```json
{
  "episodes": [
    {
      "id": 123,
      "title": "Episode Title",
      "status": "complete",
      "created_at": "2025-11-02T10:30:00Z"
    }
  ],
  "pagination": {
    "current_page": 1,
    "total_pages": 3,
    "total_count": 42,
    "per_page": 20
  }
}
```

**Example curl:**
```bash
curl "https://hub.example.com/api/v1/episodes?status=complete&per_page=10" \
  -H "Authorization: Bearer pk_live_abc123..."
```

---

### Get Podcast Feed URL

**Endpoint:** `GET /api/v1/podcast`

**Authentication:** API Key (Bearer token)

**Description:** Get RSS feed URL for the authenticated user's podcast

**Request Headers:**
```
Authorization: Bearer {API_KEY}
```

**Success Response (200 OK):**
```json
{
  "podcast": {
    "id": "podcast_abc123",
    "title": "My Podcast",
    "description": "Podcast description",
    "author": "John Doe",
    "feed_url": "https://storage.googleapis.com/bucket/podcasts/podcast_abc123/feed.xml",
    "episode_count": 42
  }
}
```

**Example curl:**
```bash
curl https://hub.example.com/api/v1/podcast \
  -H "Authorization: Bearer pk_live_abc123..."
```

---

## Error Response Format

All API errors follow this format:

```json
{
  "error": "Human-readable error message",
  "details": {
    "field_name": ["error reason"]
  }
}
```

**HTTP Status Codes:**
- `200 OK`: Success
- `201 Created`: Resource created successfully
- `400 Bad Request`: Invalid request format
- `401 Unauthorized`: Missing or invalid authentication
- `403 Forbidden`: Authenticated but not authorized
- `404 Not Found`: Resource not found
- `422 Unprocessable Entity`: Validation errors
- `429 Too Many Requests`: Rate limit exceeded
- `500 Internal Server Error`: Server error

---

## Webhook Events (Future)

Not implemented in v1, but reserved for future use:

**Endpoint:** User-provided webhook URL

**Events:**
- `episode.processing`: Episode processing started
- `episode.complete`: Episode processing completed
- `episode.failed`: Episode processing failed

**Payload:**
```json
{
  "event": "episode.complete",
  "episode_id": 123,
  "podcast_id": "podcast_abc123",
  "timestamp": "2025-11-02T10:35:00Z"
}
```

---

## Versioning

API versions are specified in the URL path:
- `/api/v1/...` - Current version
- `/api/v2/...` - Future version

**Deprecation Policy:**
- Old versions supported for 12 months after new version release
- Deprecation warnings in response headers: `X-API-Deprecated: true`

---

## Testing Endpoints

### Health Check (Hub)

**Endpoint:** `GET /health`

**Authentication:** None

**Response:**
```json
{
  "status": "healthy",
  "version": "1.0.0",
  "timestamp": "2025-11-02T10:30:00Z"
}
```

### Health Check (Generator)

**Endpoint:** `GET /health`

**Authentication:** None

**Response:**
```json
{
  "status": "healthy"
}
```

---

## Rate Limit Headers

All API responses include rate limit information:

```
X-RateLimit-Limit: 1
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1698854400
```

Where:
- `X-RateLimit-Limit`: Requests allowed per minute
- `X-RateLimit-Remaining`: Requests remaining in current window
- `X-RateLimit-Reset`: Unix timestamp when limit resets
