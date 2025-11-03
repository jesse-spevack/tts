# Multi-User Architecture

**Status:** Design Phase
**Date:** 2025-11-02
**Context:** Enabling multi-user support with web UI and API access

## Overview

The TTS Podcast system is split into two services to support both web-based and API-based podcast creation:

- **Hub**: Rails web application handling user accounts, billing, and episode management
- **Generator**: Ruby TTS service handling audio generation and podcast feed management

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                         Users                                │
└────┬────────────────────────────────────────────────┬───────┘
     │                                                 │
     │ (Web Browser)                          (curl + API Key)
     │                                                 │
     ▼                                                 ▼
┌─────────────────────────────────────────────────────────────┐
│                          HUB                                 │
│                    (Rails + SQLite)                          │
│                                                              │
│  • OAuth Authentication (Firebase)                           │
│  • Stripe Billing                                            │
│  • Episode CRUD (Web + API)                                  │
│  • API Key Management                                        │
│  • User/Podcast/Episode Database                             │
└────────────┬────────────────────────────────────────────────┘
             │
             │ (1) Upload markdown to GCS staging
             │ (2) Enqueue Cloud Task (IAM auth)
             │
             ▼
┌─────────────────────────────────────────────────────────────┐
│                      GENERATOR                               │
│                  (Ruby TTS Service)                          │
│                                                              │
│  • Download markdown from GCS                                │
│  • Generate TTS audio                                        │
│  • Upload audio to GCS                                       │
│  • Update RSS feed                                           │
│  • Callback to Hub (shared secret)                           │
└─────────────────────────────────────────────────────────────┘
             │
             │ Store audio/feed
             ▼
┌─────────────────────────────────────────────────────────────┐
│              Google Cloud Storage (GCS)                      │
│                                                              │
│  podcasts/{podcast_id}/                                      │
│    ├── episodes/{episode_id}.mp3                             │
│    ├── feed.xml                                              │
│    ├── manifest.json                                         │
│    └── staging/{filename}.md                                 │
└─────────────────────────────────────────────────────────────┘
```

## Service Responsibilities

### Hub (Rails Application)

**Technology Stack:**
- Ruby on Rails 8+
- SQLite (database)
- Firebase Authentication (OAuth)
- Stripe (billing)
- Google Cloud Storage SDK (staging file uploads)
- Google Cloud Tasks SDK (job enqueuing)

**Responsibilities:**
1. User authentication via OAuth (Google, etc.)
2. Subscription management via Stripe
3. Podcast and episode CRUD operations
4. API key generation and validation
5. Rate limiting (1 request/min per API key)
6. Upload markdown to GCS staging
7. Enqueue processing jobs to Generator
8. Receive status callbacks from Generator
9. Display episode list and RSS feed URL

**Does NOT:**
- Generate audio (delegated to Generator)
- Manage RSS feeds (delegated to Generator)
- Store audio files (uses GCS)

### Generator (Ruby TTS Service)

**Technology Stack:**
- Ruby 3.4
- Sinatra 4.0
- Google Cloud TTS API
- Google Cloud Storage SDK
- Google Cloud Tasks (receives jobs)

**Responsibilities:**
1. Receive processing tasks from Hub via Cloud Tasks
2. Download markdown from GCS staging
3. Convert markdown to plain text
4. Generate TTS audio
5. Upload audio to GCS
6. Update episode manifest
7. Regenerate RSS feed
8. Clean up staging files
9. Callback to Hub with completion status

**Does NOT:**
- Authenticate end users (Hub handles this)
- Manage billing (Hub handles this)
- Store episode metadata in database (stateless)

## Communication Patterns

### Hub → Generator (Job Enqueuing)

**Protocol:** Google Cloud Tasks with OIDC authentication

**Flow:**
1. Hub creates episode record (status: `pending`)
2. Hub uploads markdown to GCS: `podcasts/{podcast_id}/staging/{filename}.md`
3. Hub enqueues Cloud Task to Generator `/process` endpoint
4. Cloud Task includes OIDC token (service account identity)
5. Generator verifies token via Google's OIDC verification

**Payload:**
```json
{
  "episode_id": "123",
  "podcast_id": "podcast_abc123",
  "title": "Episode Title",
  "author": "Author Name",
  "description": "Episode description",
  "staging_path": "staging/episode-title-20251102.md"
}
```

**Authentication:** IAM service account with Cloud Run Invoker role

### Generator → Hub (Status Callback)

**Protocol:** HTTP POST with shared secret

**Flow:**
1. Generator completes processing
2. Generator calls Hub: `POST /api/internal/episodes/{episode_id}/complete`
3. Request includes `X-Generator-Secret` header
4. Hub verifies secret matches `GENERATOR_CALLBACK_SECRET` env var
5. Hub updates episode status to `complete`

**Payload:**
```json
{
  "episode_id": "123",
  "status": "complete",
  "gcs_episode_id": "episode-abc123",
  "audio_size_bytes": 5242880,
  "duration_seconds": 600
}
```

**Authentication:** Shared secret in header

**Error Handling:**
- If callback fails, Generator logs error but doesn't retry
- Hub can detect stale "processing" episodes and mark as failed after timeout

## Data Models

### Hub Database (SQLite)

**users**
```sql
CREATE TABLE users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  email TEXT NOT NULL UNIQUE,
  oauth_provider TEXT NOT NULL, -- 'google', 'github', etc.
  oauth_uid TEXT NOT NULL,
  stripe_customer_id TEXT,
  stripe_subscription_id TEXT,
  subscription_status TEXT, -- 'active', 'canceled', 'past_due'
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  UNIQUE(oauth_provider, oauth_uid)
);
```

**podcasts**
```sql
CREATE TABLE podcasts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  podcast_id TEXT NOT NULL UNIQUE, -- 'podcast_abc123' (GCS identifier)
  title TEXT,
  description TEXT,
  author TEXT,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
```

**episodes**
```sql
CREATE TABLE episodes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  podcast_id INTEGER NOT NULL,
  title TEXT NOT NULL,
  author TEXT NOT NULL,
  description TEXT NOT NULL,
  status TEXT NOT NULL, -- 'pending', 'processing', 'complete', 'failed'
  gcs_episode_id TEXT, -- Episode ID in GCS (e.g., 'episode-abc123')
  error_message TEXT, -- If status is 'failed'
  audio_size_bytes INTEGER,
  duration_seconds INTEGER,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  FOREIGN KEY (podcast_id) REFERENCES podcasts(id) ON DELETE CASCADE
);
```

**api_keys**
```sql
CREATE TABLE api_keys (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  key_hash TEXT NOT NULL UNIQUE, -- bcrypt hash of API key
  key_prefix TEXT NOT NULL, -- First 8 chars for display (e.g., 'pk_live_')
  name TEXT, -- User-provided name (e.g., 'Production Server')
  last_used_at DATETIME,
  created_at DATETIME NOT NULL,
  revoked_at DATETIME,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
```

### Generator Storage (GCS)

**Structure:**
```
podcasts/{podcast_id}/
  ├── episodes/{gcs_episode_id}.mp3
  ├── feed.xml
  ├── manifest.json
  └── staging/{filename}.md (temporary)
```

**manifest.json:**
```json
{
  "podcast_id": "podcast_abc123",
  "episodes": [
    {
      "id": "episode-abc123",
      "title": "Episode Title",
      "description": "Episode description",
      "author": "Author Name",
      "mp3_url": "https://storage.googleapis.com/.../episodes/episode-abc123.mp3",
      "file_size_bytes": 5242880,
      "published_at": "2025-11-02T10:30:00Z",
      "guid": "episode-abc123"
    }
  ]
}
```

## User Flows

### Flow 1: Non-Developer User (Web UI)

1. **Signup**
   - User visits Hub homepage
   - Clicks "Sign Up"
   - Authenticates via OAuth (Google)
   - Redirected to Stripe Checkout for subscription
   - Stripe webhook confirms payment

2. **Podcast Creation**
   - Hub creates user record and podcast record
   - Generates unique `podcast_id` (e.g., `podcast_abc123`)
   - User redirected to `/episodes/new`

3. **Episode Creation**
   - User fills form: title, author, description
   - User uploads markdown file
   - Clicks "Create Episode"

4. **Processing**
   - Hub saves episode (status: `pending`)
   - Hub uploads markdown to GCS staging
   - Hub enqueues Cloud Task to Generator
   - User redirected to `/episodes` (sees "Processing..." status)

5. **Completion**
   - Generator processes episode
   - Generator calls Hub callback
   - Hub updates episode status to `complete`
   - User refreshes page, sees "Complete" status
   - User copies RSS feed URL

### Flow 2: Developer User (API)

1. **Signup**
   - Same as Flow 1 (OAuth → Stripe → podcast created)

2. **API Key Generation**
   - User navigates to "Developer" section in Hub
   - Clicks "Generate API Key"
   - Hub creates API key, shows it once
   - User copies key

3. **Episode Creation via API**
   - Developer makes curl request:
     ```bash
     curl -X POST https://hub.example.com/api/v1/episodes \
       -H "Authorization: Bearer API_KEY" \
       -F "title=Episode Title" \
       -F "author=Author Name" \
       -F "description=Description" \
       -F "content=@article.md"
     ```

4. **Processing**
   - Hub validates API key
   - Hub looks up user's podcast_id
   - Hub checks rate limit (1/min)
   - Same flow as web: staging → Cloud Task → Generator
   - Hub returns: `{"episode_id": 123, "status": "pending"}`

5. **Checking Status**
   - Developer polls: `GET /api/v1/episodes/123`
   - Returns: `{"id": 123, "status": "complete", "title": "..."}`

## Authentication & Authorization

### User Authentication (Hub)

**OAuth via Firebase:**
- User authenticates with Firebase (client-side)
- Firebase returns ID token
- Rails verifies token on each request using Firebase Admin SDK
- Extracts `user_id` from verified token
- Loads user from database

### API Key Authentication (Hub)

**API Key Format:** `pk_live_xxxxxxxxxxxx` (32 random characters)

**Flow:**
1. Extract key from `Authorization: Bearer {key}` header
2. Hash key with bcrypt
3. Look up `api_keys` table by `key_hash`
4. Check `revoked_at IS NULL`
5. Load associated `user_id`
6. Check rate limit (last_used_at within 1 minute → reject)
7. Update `last_used_at`
8. Load user's podcast

### Service-to-Service Authentication

**Hub → Generator:**
- OIDC token from Hub's service account
- Generator verifies via Google's token verification
- No shared secrets needed (IAM handles it)

**Generator → Hub:**
- Shared secret in `X-Generator-Secret` header
- Both services have `GENERATOR_CALLBACK_SECRET` env var
- Hub rejects if header doesn't match

## Rate Limiting

**API Keys:** 1 request per minute per key

**Implementation:**
```ruby
# In Hub
def check_rate_limit!(api_key)
  if api_key.last_used_at && api_key.last_used_at > 1.minute.ago
    raise RateLimitExceeded, "Rate limit: 1 request per minute"
  end
  api_key.update!(last_used_at: Time.current)
end
```

**Future:** Move to Redis for distributed rate limiting

## Deployment

### Hub
- **Platform:** Google Cloud Run
- **Region:** us-west3
- **Environment Variables:**
  - `DATABASE_URL` (SQLite path or future Postgres)
  - `FIREBASE_PROJECT_ID`
  - `FIREBASE_CREDENTIALS` (JSON)
  - `STRIPE_API_KEY`
  - `STRIPE_WEBHOOK_SECRET`
  - `GOOGLE_CLOUD_BUCKET`
  - `GOOGLE_CLOUD_PROJECT`
  - `CLOUD_TASKS_QUEUE`
  - `GENERATOR_SERVICE_URL`
  - `GENERATOR_CALLBACK_SECRET`

### Generator
- **Platform:** Google Cloud Run
- **Region:** us-west3
- **Environment Variables:**
  - `GOOGLE_CLOUD_BUCKET`
  - `GOOGLE_CLOUD_PROJECT`
  - `HUB_CALLBACK_URL`
  - `GENERATOR_CALLBACK_SECRET`

## Migration Path

### Phase 1: Build Hub
1. Scaffold Rails app
2. Add Firebase authentication
3. Add Stripe integration
4. Build episode CRUD (web + API)
5. Implement Cloud Tasks enqueuing

### Phase 2: Update Generator
1. Rename service from `tts` to `generator`
2. Update `/process` endpoint to accept `episode_id`
3. Add callback to Hub on completion
4. Remove Firestore dependency
5. Deploy updated service

### Phase 3: Integration
1. Test Cloud Tasks flow end-to-end
2. Test callback authentication
3. Test web UI episode creation
4. Test API episode creation
5. Load testing

### Phase 4: Migration
1. Migrate existing users (if any)
2. Update DNS/URLs
3. Deploy to production
4. Monitor

## Security Considerations

1. **API Keys:** Store only bcrypt hashes, never plaintext
2. **Secrets:** Rotate `GENERATOR_CALLBACK_SECRET` periodically
3. **CORS:** Hub API should restrict origins for web requests
4. **Rate Limiting:** Prevent abuse of free tier / API
5. **Input Validation:** Sanitize markdown uploads (future: add content moderation)
6. **Service Accounts:** Use minimal IAM permissions (Cloud Run Invoker only)

## Cost Considerations

1. **TTS API:** ~$16 per 1M characters (primary cost)
2. **Cloud Storage:** ~$0.02/GB/month
3. **Cloud Run:** ~$0.00002400/vCPU-second
4. **Cloud Tasks:** First 1M invocations free
5. **Stripe:** 2.9% + $0.30 per transaction

**Tracking:** Hub logs TTS character count per episode for cost attribution

## Open Questions

1. Should we support multiple podcasts per user in v1, or enforce 1:1?
   - **Decision:** Support multiple (1:N) in schema, but UI can start simple
2. How long should episodes stay in "processing" before marking as failed?
   - **Recommendation:** 10 minutes timeout
3. Should API support webhook callbacks for completion?
   - **Future enhancement:** Not in v1
4. Should we support episode editing/deletion?
   - **Future enhancement:** Not in v1

## References

- [Wave 2 Implementation Plan](../plans/2025-11-02-wave-2-podcast-isolation.md)
- [Current Deployment Docs](../deployment.md)
- [Firebase Auth + Rails Guide](https://firebase.google.com/docs/auth/admin)
- [Stripe Webhooks](https://stripe.com/docs/webhooks)
