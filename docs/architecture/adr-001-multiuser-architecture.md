# ADR 001: Multi-User Architecture with Hub and Generator Services

**Status:** Proposed
**Date:** 2025-11-02
**Deciders:** Jesse (Product), Claude (Technical Advisor)

## Context

The TTS podcast system currently operates as a single-user application with:
- Local CLI (`generate.rb`) for episode creation
- API endpoint for programmatic access
- `podcast_id` environment variable for isolation
- No user authentication or billing

We need to support multiple users creating and managing their own podcasts through both web UI and API access, with subscription-based billing.

## Decision Drivers

1. **User Experience:** Non-technical users need a simple web interface
2. **Developer Experience:** Technical users want API access with curl/CLI
3. **Billing:** Need to track users and charge subscriptions
4. **Separation of Concerns:** Web/billing logic separate from TTS processing
5. **Scalability:** TTS processing is CPU-intensive and should scale independently
6. **Existing Investment:** Preserve existing TTS service code
7. **Simplicity:** Minimize infrastructure complexity

## Considered Options

### Option 1: Monolithic Rails Application
**Architecture:** Single Rails app handling everything (web UI, API, TTS generation, billing)

**Pros:**
- Simple deployment (one service)
- Easy local development
- Single codebase
- No service-to-service communication

**Cons:**
- TTS processing blocks web requests
- CPU-intensive TTS workload on same service as web UI
- Hard to scale TTS independently
- Mixing concerns (billing, auth, audio generation)
- Would require rewriting existing TTS service

### Option 2: Rails + Separate TTS Service (CHOSEN)
**Architecture:** Rails handles web/API/billing, dedicated TTS service handles audio generation

**Pros:**
- Separation of concerns (web vs. processing)
- TTS service can scale independently
- Preserves existing TTS codebase
- Non-blocking web requests (async processing)
- Clear boundaries and responsibilities
- Can optimize each service separately

**Cons:**
- More complex deployment (two services)
- Service-to-service communication required
- Need to manage authentication between services
- Slightly more operational overhead

### Option 3: Microservices (Rails + Auth + TTS + Billing)
**Architecture:** Separate services for auth, billing, TTS, web UI

**Pros:**
- Maximum separation of concerns
- Each service can use optimal tech stack
- Ultra-scalable

**Cons:**
- Massive operational overhead for small team
- Complex service mesh
- Distributed tracing required
- Over-engineered for current scale

## Decision

**Option 2: Rails + Separate TTS Service**

We will build two services:
- **Hub** (Rails): Web UI, authentication, billing, episode CRUD, API endpoints
- **Generator** (existing Ruby TTS): Audio generation, GCS management, RSS feeds

## Rationale

1. **Preserves Existing Work:** Generator service is already built and working
2. **Clear Boundaries:** Web concerns vs. processing concerns are naturally separate
3. **Independent Scaling:** Can scale Generator for TTS load without scaling Hub
4. **Async Processing:** Long TTS jobs don't block web requests
5. **Right-Sized:** Two services is manageable complexity for a small team
6. **Future-Proof:** Can add more services later if needed (e.g., analytics)

## Consequences

### Positive
- Clean separation of web UI and processing logic
- Async episode processing improves UX (no waiting for TTS)
- Generator can be scaled independently during high load
- Easy to add features to either service without affecting the other
- Existing TTS service code is preserved

### Negative
- Need to manage two deployments
- Service-to-service authentication required
- Callbacks needed for status updates
- Slightly more complex local development setup

### Neutral
- Need Cloud Tasks for job queue (already using it)
- Need shared GCS bucket (already using it)

## Related Decisions

### Service Names
- **Hub:** Rails application (web UI, API, billing)
- **Generator:** TTS service (audio generation)

Rationale: "Hub" suggests central coordination, "Generator" clearly indicates audio generation.

### Database Choice: SQLite for Hub

**Decision:** Use SQLite (not PostgreSQL) for Hub database

**Rationale:**
- Simple deployment (no separate database server)
- Rails 8 has excellent SQLite support
- Sufficient for expected scale (hundreds of users)
- Easy local development
- Can migrate to Postgres later if needed

**Tradeoff:** Less scalable than Postgres, but suitable for v1

### Authentication: Firebase Auth (not custom)

**Decision:** Use Firebase Authentication for user login

**Rationale:**
- OAuth providers out-of-box (Google, GitHub, etc.)
- Works seamlessly with Rails via Firebase Admin SDK
- No need to build password reset, email verification, etc.
- Integrates well with GCP ecosystem

**Tradeoff:** Vendor lock-in to Firebase, but provides significant time savings

### No Firestore

**Decision:** Do NOT use Firestore for user/podcast mapping

**Rationale:**
- Hub's SQLite database is source of truth
- Generator receives podcast_id in every request (no lookup needed)
- Firestore would be redundant synchronization layer
- Simpler to maintain single database

**Previous Design:** Wave 2 plan included Firestore, but that was before Hub existed

### Service Communication

**Hub → Generator:** Cloud Tasks with IAM authentication
- Already using Cloud Tasks
- Built-in retry and error handling
- Proper GCP-native authentication

**Generator → Hub:** HTTP callback with shared secret
- Simple and sufficient
- No need for IAM in reverse direction
- Stateless Generator doesn't need service account

### API Keys over OAuth for API

**Decision:** Use API keys (not OAuth tokens) for programmatic access

**Rationale:**
- Simpler for CLI/curl usage
- No token refresh logic needed
- Long-lived keys suitable for automation
- Rate limiting easier with keys

**Tradeoff:** Less secure than short-lived OAuth tokens, mitigated by rate limiting

### Rate Limiting: 1 request/minute

**Decision:** API keys limited to 1 request per minute

**Rationale:**
- TTS generation is expensive (~$16 per 1M chars)
- Prevents abuse and runaway costs
- Sufficient for typical podcast creation cadence
- Can increase for paid tiers later

**Implementation:** Database-based (check `last_used_at` on `api_keys` table)

## Implementation Plan

### Phase 1: Hub Development (4-6 weeks)
1. Scaffold Rails 8 app
2. Implement Firebase authentication
3. Integrate Stripe billing
4. Build episode CRUD (web UI)
5. Build API endpoints
6. Implement API key generation
7. Add Cloud Tasks enqueuing to Generator

### Phase 2: Generator Updates (1-2 weeks)
1. Rename service from `tts` to `generator`
2. Update `/process` endpoint to accept `episode_id`
3. Add callback endpoints to notify Hub
4. Remove Firestore dependency
5. Update deployment scripts

### Phase 3: Integration & Testing (1-2 weeks)
1. End-to-end testing
2. Load testing
3. Security audit
4. Deploy to staging
5. User acceptance testing

### Phase 4: Production Launch
1. Deploy Hub to Cloud Run
2. Deploy updated Generator
3. Configure DNS
4. Monitor metrics
5. Gradual rollout

## Monitoring & Success Metrics

### Key Metrics
- Episode creation rate (web vs. API)
- Processing time (median, p95)
- Error rate (Generator failures)
- API rate limit violations
- User signups and churn
- Revenue (MRR from Stripe)

### Alerts
- Generator processing failures > 5%
- Hub response time > 500ms (p95)
- API error rate > 1%
- Database connection failures

## References

- [Multi-User Architecture](./multiuser-architecture.md)
- [API Contracts](./api-contracts.md)
- [Wave 2 Implementation Plan](../plans/2025-11-02-wave-2-podcast-isolation.md)
- [Rails 8 SQLite Guide](https://guides.rubyonrails.org/configuring.html#configuring-a-sqlite3-database)
- [Firebase Auth Admin SDK](https://firebase.google.com/docs/auth/admin)
- [Cloud Tasks Documentation](https://cloud.google.com/tasks/docs)

## Revision History

- 2025-11-02: Initial decision (Jesse + Claude)
