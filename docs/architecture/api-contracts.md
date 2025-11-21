# API Contracts

**Version:** 1.1
**Last Updated:** 2025-11-21

This document defines the API contracts between Hub and Generator services.

## Table of Contents

1. [Hub → Generator (Internal)](#hub--generator-internal)
2. [Generator → Hub (Callback)](#generator--hub-callback)
3. [Health Checks](#health-checks)

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
  "staging_path": "staging/123-1699012345.md"
}
```

**Request Fields:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `episode_id` | integer | Yes | Hub's database ID for the episode (used for callback) |
| `podcast_id` | string | Yes | GCS podcast identifier (e.g., `podcast_abc123`) |
| `title` | string | Yes | Episode title |
| `author` | string | Yes | Episode author |
| `description` | string | Yes | Episode description |
| `staging_path` | string | Yes | Path to markdown file in GCS (relative to podcast directory) |

**Success Response (200 OK):**
```json
{
  "status": "success",
  "message": "Episode processed successfully"
}
```

**Error Responses:**

**400 Bad Request:**
```json
{
  "status": "error",
  "message": "Missing podcast_id"
}
```

**500 Internal Server Error:**
```json
{
  "status": "error",
  "message": "Internal server error"
}
```

**Processing Flow:**
1. Validate request payload
2. Download markdown from GCS staging path
3. Convert markdown to plain text
4. Generate TTS audio
5. Upload audio to GCS
6. Update manifest.json
7. Regenerate feed.xml
8. Delete staging file
9. Callback to Hub with completion status

**Retry Behavior:**
- Cloud Tasks automatically retries on 5xx errors
- Configurable via Cloud Tasks queue settings

---

## Generator → Hub (Callback)

### Update Episode Status

**Endpoint:** `PATCH /api/internal/episodes/:episode_id`

**Authentication:** Shared secret

**Description:** Updates episode status after processing (complete or failed)

**Request Headers:**
```
X-Generator-Secret: {GENERATOR_CALLBACK_SECRET}
Content-Type: application/json
```

**Request Body (Success):**
```json
{
  "status": "complete",
  "gcs_episode_id": "episode-abc123",
  "audio_size_bytes": 5242880
}
```

**Request Body (Failure):**
```json
{
  "status": "failed",
  "error_message": "TTS API rate limit exceeded"
}
```

**Request Fields:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `status` | string | Yes | Episode status: `complete` or `failed` |
| `gcs_episode_id` | string | For complete | Episode identifier in GCS (used in MP3 filename) |
| `audio_size_bytes` | integer | For complete | Size of generated MP3 file in bytes |
| `error_message` | string | For failed | Human-readable error description |

**Success Response (200 OK):**
```json
{
  "status": "success"
}
```

**Error Responses:**

**401 Unauthorized:**
```json
{
  "status": "error",
  "message": "Unauthorized"
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
  "errors": ["Status is not included in the list"]
}
```

**Processing Flow:**
1. Validate `X-Generator-Secret` header against `GENERATOR_CALLBACK_SECRET`
2. Find episode by `episode_id`
3. Update episode attributes based on status
4. Broadcast status change via Turbo Streams (for real-time UI updates)
5. Return success

**Retry Behavior:**
- Generator does NOT retry on callback failure
- Generator logs errors but continues

**Idempotency:**
- Multiple PATCH requests with same data return 200 OK
- Safe to retry if network issues occur

---

## Health Checks

### Hub Health Check

**Endpoint:** `GET /up`

**Authentication:** None

**Description:** Rails health check endpoint

**Success Response (200 OK):**
Returns HTML page indicating the app is running.

### Generator Health Check

**Endpoint:** `GET /health`

**Authentication:** None

**Description:** Validates required environment variables are set

**Success Response (200 OK):**
```json
{
  "status": "healthy"
}
```

**Error Response (500):**
```json
{
  "status": "unhealthy",
  "missing_vars": ["GOOGLE_CLOUD_PROJECT", "GOOGLE_CLOUD_BUCKET"]
}
```
