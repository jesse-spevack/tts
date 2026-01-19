# Very Normal TTS: Feature Development Timeline

This document tracks the order in which features were built for "The Stack" blog post (#3 in the marketing plan). Based on 65 commits from December 29, 2025 to January 19, 2026.

## Tech Stack Chosen

**Backend:**
- Rails 8.1 (later 8.1.2)
- Ruby 3.4.5
- SQLite with WAL mode
- Solid Queue for background jobs
- Solid Cache for caching
- Solid Cable for real-time updates

**Frontend:**
- Hotwire (Turbo + Stimulus)
- Tailwind CSS
- Import Maps (no webpack/vite)
- Propshaft for asset pipeline

**External Services:**
- Google Cloud Text-to-Speech (Standard + Chirp HD voices)
- Google Cloud Storage (audio files + RSS feeds)
- Vertex AI (Gemini 2.5 Flash for LLM)
- Resend (transactional email)
- Stripe (billing/subscriptions)

**Deployment:**
- Kamal 2.0 to Google Cloud Platform
- Docker containers via Google Artifact Registry
- Puma + Thruster (HTTP/2, asset compression)
- Let's Encrypt SSL via Kamal proxy
- Single server with persistent volume for SQLite

---

## Phase 1: Foundation & Core Features (Pre-December 29)

*The first 65 commits show the app already had core functionality in place before this timeline began. Initial features included:*

- Three input methods: URL, Paste Text, File Upload
- User authentication with magic links
- Episode creation and processing with background jobs
- Google Cloud TTS integration
- RSS feed generation
- Private podcast feeds per user
- Real-time status updates via Turbo Streams
- Basic tier system (free/premium/unlimited)

---

## Phase 2: Production Hardening (Dec 29 - Jan 1)

### 1. SQLite Concurrency Fixes (Dec 29)
**Commit:** b04e251

**Problem:** Database lock errors under load when multiple episodes processed simultaneously.

**Solution:**
- Enabled WAL mode (`journal_mode: wal`, `synchronous: normal`)
- Added per-user job concurrency limit (1 job per user at a time)
- Passed `user_id` explicitly to jobs to avoid DB lookups during concurrency checks

**Why this matters:** SQLite can handle production traffic, but requires proper configuration. WAL mode allows concurrent reads/writes without locks.

---

### 2. View Original Button (Dec 30)
**Commit:** a44d875

**Feature:** Added "View Original" button on episode share pages for URL-sourced episodes.

**Why:** Users want to reference the source article that was converted to audio.

---

### 3. Google Cloud Storage Signed URLs (Dec 30)
**Commits:** fb2065c, c8de682, bc27533

**Problem:** Episode download URLs failing with 500 errors in production.

**Root Cause:** GCE metadata credentials (default in production) can't sign URLs directly - they lack the private key.

**Solution:** Always use IAM Credentials `signBlob` API for signed URLs, works identically in dev and production.

**Architecture Decision:** Single code path for all environments rather than conditional logic.

---

### 4. Substack URL Normalization (Dec 31)
**Commit:** af9f569

**Problem:** Substack inbox URLs (`substack.com/inbox/...`) require authentication and fetch login HTML instead of article content.

**Solution:**
- Moved URL normalization from job processing to episode creation
- Reject inbox URLs immediately with helpful error message
- Service returns `Result` type to support failure cases
- Store normalized URL in episode record from creation

**Why this matters:** Fail fast with clear feedback rather than creating an episode that will fail minutes later.

---

### 5. Privacy Policy (Dec 31)
**Commit:** 7138b32

**Feature:** Added `/privacy` route with privacy policy covering data collection, third-party services, storage, and deletion.

**Why:** Required for production launch and user trust.

---

## Phase 3: Monetization (Jan 1-2)

### 6. Stripe Subscription Billing (Jan 1)
**Commit:** 1532fbe (massive 20-task implementation)

**Major Feature:** Complete Stripe integration with subscriptions, webhooks, and billing portal.

**Implementation:**
- Database: Added `subscriptions` table, migrated `users.tier` to `account_type` enum
- Stripe Checkout: Session creation for monthly/annual plans
- Stripe Customer Portal: Self-service subscription management
- Webhooks: `checkout.session.completed`, `invoice.payment_succeeded`, `invoice.payment_failed`, `customer.subscription.updated`, `customer.subscription.deleted`
- Services: `CreatesCheckoutSession`, `CreatesBillingPortalSession`, `SyncsSubscription`, `CreatesSubscriptionFromCheckout`, `RoutesStripeWebhook`
- Email: `SendsUpgradeNudge` service + `BillingMailer` for monthly nudges when free users hit limit
- Landing Page: Added pricing section with monthly/annual toggle
- Signup Flow: Capture plan parameter (`#premium_monthly` or `#premium_annual`) via URL hash, preserve through magic link flow
- Customer Management: `stripe_customer_id` stored on users (not subscriptions) to prevent race conditions

**Key Architectural Decisions:**
- Webhook handlers re-fetch data from Stripe API rather than trusting webhook payload
- Payment failures trigger immediate downgrade (no grace period)
- Plan parameter captured via JavaScript hash change listener (works after page load)
- Customer ID on users table to prevent duplicate customers from simultaneous checkouts

**Cost Structure Enabled:**
- Free: 2 episodes/month, 15K character limit
- Premium: Unlimited episodes, 50K character limit
- Unlimited: No character limit, access to Chirp HD voices

---

### 7. Subscription Refinements (Jan 2)
**Commits:** e812e12, 5f9fbff, 2495cf3

**Fixes:**
- Track `cancel_at_period_end` for subscriptions pending cancellation
- Use `result.data` instead of `result.value` in rake task (Result API consistency)
- Replace `cancel_at_period_end` with `cancel_at` datetime (more accurate)

**Why:** Handle edge cases in subscription lifecycle properly.

---

### 8. UI Polish for Billing (Jan 2)
**Commits:** 04ad91b, 032cbde

**Changes:**
- Separate billing and upgrade pages for better UX flow
- Extract pricing components to reusable partials
- Extract episode card components

**Why:** Make upgrade path clear and reduce view complexity.

---

### 9. Rainbow Gradient for Unlimited Plan (Jan 2)
**Commits:** e705bcf, 5282643

**Feature:** Added rainbow gradient header for Unlimited Plan card on pricing section.

**Implementation:** Used solid color bands instead of smooth gradient for better browser compatibility.

**Why:** Visually distinguish the premium tier.

---

## Phase 4: Branding & UX (Jan 2-3)

### 10. Branded Feed URLs (Jan 2)
**Commit:** ed8e98b

**Feature:** Custom branded RSS feed URLs with proxy controller.

**Before:** Generic GCS URLs
**After:** `tts.verynormal.dev/feeds/{podcast_id}/feed.xml`

**Why:** Professional branding, control over feed delivery, potential for future analytics.

---

### 11. Concurrency Limits for All Job Types (Jan 2)
**Commit:** 3f027c4

**Feature:** Extended per-user concurrency limits to paste and file upload jobs (previously only URL jobs).

**Why:** Prevent any job type from competing for database locks.

---

### 12. Update Software Stage to Beta (Jan 2)
**Commit:** 66c780a

**Change:** Updated release stage from "alpha" to "beta" in user-facing messaging.

**Why:** Reflect maturity after billing launch.

---

### 13. Warmer Free Tier Email Copy (Jan 2)
**Commit:** ba03de1

**Change:** Updated free tier nudge email with more appreciative, friendly tone.

**Why:** Encourage upgrades without being pushy.

---

### 14. Brand Name in Magic Link Email (Jan 3)
**Commit:** 32b1943

**Change:** Updated magic link email subject to include "Very Normal".

**Why:** Better brand recognition in inbox.

---

## Phase 5: Codebase Quality (Jan 3-5)

### 15. Extract Voice Lookup Logic (Jan 2)
**Commit:** 3c13011

**Refactor:** Moved voice lookup logic from User model to Voice class.

**Why:** Single Responsibility Principle - Voice class owns voice-related logic.

---

### 16. Extract Episode Job Logging (Jan 3)
**Commit:** d0c69ba

**Refactor:** Created shared `EpisodeLogging` concern for background jobs.

**Why:** DRY - all episode jobs log the same structured data.

---

### 17. Centralize Character Limit Validation (Jan 3)
**Commit:** b77a6fa

**Refactor:** Consolidated character limit validation into single service.

**Why:** Previously duplicated across URL, paste, and file episode creation.

---

### 18. Standardize Episode Status (Jan 3)
**Commit:** 25a4120

**Refactor:** Changed episode status to use symbols (`:processing`, `:complete`, `:failed`) instead of strings.

**Why:** Ruby convention, prevents typos, slightly faster comparisons.

---

### 19. Extract Processing Placeholders (Jan 3)
**Commit:** 482f5e8

**Refactor:** Moved episode processing placeholders to `EpisodePlaceholders` module.

**Why:** Reusable across controllers and views.

---

### 20. Consolidate TTS Error Constants (Jan 3)
**Commit:** 77d48c6

**Refactor:** Moved all TTS error messages to single constants module.

**Why:** Single source of truth for error messages.

---

### 21. Reject Twitter/X URLs (Jan 3)
**Commit:** c3d59ae

**Feature:** Reject Twitter/X URLs with helpful error message at episode creation.

**Why:** Twitter requires authentication, content extraction fails. Better to reject upfront.

---

### 22. Consolidate Prompt Builder Logic (Jan 3)
**Commit:** 4a0ab1a

**Refactor:** Extracted shared prompt building logic for LLM calls.

**Why:** URL and paste episodes both use LLM for content processing - share the logic.

---

### 23. Codebase Consistency Pass (Jan 4)
**Commits:** 990bccb, 925d7af

**Refactors:**
- Quick wins for code style consistency
- DRY improvements
- Dead code removal
- Service naming consistency (third-person verb form: "Creates...", "Processes...", "Syncs...")

**Why:** Maintainability. Consistent patterns make onboarding easier.

---

### 24. Structured Logging with Action ID Tracing (Jan 4)
**Commit:** aae14d9

**Feature:** Added `action_id` to all log statements for request tracing.

**Why:** Makes debugging production issues easier - can trace single request through all services and jobs.

---

## Phase 6: Production Bugs (Jan 5-11)

### 25. Async Audio Generation (Jan 5)
**Commit:** 67478bb

**Problem:** SQLite lock contention when audio generation happened synchronously in job.

**Solution:** Extract audio generation to separate async job.

**Why:** Long-running TTS API calls were holding database connections, causing locks.

---

### 26. Pagination After Episode Deletion (Jan 8)
**Commits:** e4331a6, e0f3a5f, e220f7f

**Problem:** Deleting last episode on a page left user on empty page.

**Solution:** Redirect to last available page after deletion.

**Why:** Better UX - keep user in valid pagination state.

---

### 27. Episode Deletion UX (Jan 9)
**Commit:** 35c25a8

**Feature:** Episode deletion now immediately removes from DOM via Turbo Stream.

**Why:** Instant feedback rather than page reload.

---

### 28. Testing Infrastructure (Jan 9)
**Commits:** d0edf2f, ebced62

**Change:** Migrated from minitest/mock to mocktail for test mocking, bumped minitest to 6.0.1.

**Why:** Mocktail provides better mocking API, Rails 8 compatible with minitest 6.

---

### 29. Remove LLM Input Limit for Unlimited Users (Jan 11)
**Commit:** ba634d7

**Feature:** Unlimited tier users can now process content of any length (no 50K limit).

**Why:** Value differentiation for highest tier.

---

### 30. Fix Turbo Stream Race Condition (Jan 11)
**Commits:** 4307078, 640fb8a, 2aceebe

**Problem:** Episode cards not updating in real-time for recently changed episodes.

**Solution:**
- Broadcast all recently changed episodes (not just in-progress)
- Extract `FindsRecentlyChangedEpisodes` service
- Add channel tests
- Mitigate N+1 queries

**Why:** Race condition where episode moved to complete status before broadcast subscription established.

---

### 31. Security Updates (Jan 11)
**Commit:** bf7ea65

**Change:** Updated httparty to 0.24.0 to fix CVE-2025-68696.

**Why:** Security vulnerability in HTTP client library.

---

## Phase 7: Voice Expansion (Jan 14)

### 32. Add 4 New Standard Voices (Jan 14)
**Commits:** f72c9f2, 5a08127, 27db573

**Feature:** Added Gemma, Hugo, Quinn, and Theo voices.

**Total Voices:** Now 8 voices (4 standard tier, 4 unlimited tier with Chirp HD)

**Implementation:**
- Voice sample generation script
- Updated voice selection UI
- Added samples to "How it Sounds" page

**Why:** More voice options increases appeal, especially for users who listen to many episodes.

---

## Phase 8: Marketing Documentation (Jan 19)

### 33. Marketing Plan (Jan 19)
**Commit:** 91379f7

**Document:** Comprehensive marketing plan for blog posts, Twitter, and Reddit outreach.

**Target:** Organic growth via authentic content and community engagement.

**Why:** Need structured approach to reach tab hoarders, commuters, and indie hackers.

---

## Key Architectural Decisions

### 1. **SQLite in Production**
**Decision:** Use SQLite with WAL mode instead of Postgres.

**Rationale:**
- Simplified deployment (no separate database server)
- Lower costs (no managed database service)
- Sufficient for current scale (single server handles concurrent requests)
- Persistent Docker volume for data durability

**Trade-offs:**
- Can't horizontally scale web servers (SQLite is single-server)
- Requires careful concurrency management
- Need to implement per-user job limits to prevent lock contention

**Blog Post Angle:** "Why SQLite works for a production SaaS in 2026"

---

### 2. **Solid Queue In-Process**
**Decision:** Run Solid Queue inside Puma process (`SOLID_QUEUE_IN_PUMA: true`).

**Rationale:**
- No separate job worker server needed
- Share database connection pool
- Simpler deployment

**Trade-offs:**
- Job processing uses web server resources
- Need to scale to separate job server eventually

**Blog Post Angle:** "Rails 8's Solid libraries enable true single-server deployments"

---

### 3. **Hotwire Over React**
**Decision:** Use Turbo + Stimulus instead of JavaScript framework.

**Rationale:**
- Real-time updates via Turbo Streams (episode status changes)
- Minimal JavaScript required
- Server-rendered HTML (faster initial loads)
- No build step complexity

**Use Cases:**
- Episode cards update live during processing
- Instant episode deletion from DOM
- Theme toggle with persistence
- Pricing plan selection

**Blog Post Angle:** "Building real-time features without React"

---

### 4. **Kamal Deployment**
**Decision:** Deploy via Kamal to single GCP server instead of Heroku/Render.

**Rationale:**
- Full control over infrastructure
- Lower costs ($10-20/month for server vs $20+ for managed platform)
- Learn Docker/deployment fundamentals
- No vendor lock-in

**Trade-offs:**
- More operational responsibility
- Manual SSL via Let's Encrypt (automated by Kamal)
- Single point of failure (mitigated by daily backups)

**Blog Post Angle:** "Kamal deployment cost breakdown: $X/month for a SaaS"

---

### 5. **Service Objects with Result Pattern**
**Decision:** Extract all business logic to service objects returning Result/Outcome.

**Rationale:**
- Testable in isolation
- Reusable across controllers/jobs
- Explicit error handling
- Clear success/failure paths

**Pattern:**
```ruby
result = CreatesUrlEpisode.call(podcast: podcast, user: user, url: url)
if result.success?
  episode = result.data
else
  flash[:alert] = result.error
end
```

**Blog Post Angle:** "Service objects: keeping Rails controllers thin"

---

### 6. **Stripe Webhooks with API Re-fetch**
**Decision:** Webhook handlers re-fetch data from Stripe API rather than trusting payload.

**Rationale:**
- Defense against replay attacks
- Always have latest data
- Webhooks can arrive out of order

**Implementation:**
```ruby
# Don't trust webhook payload
subscription_id = event.data.object.id

# Re-fetch from Stripe
subscription = Stripe::Subscription.retrieve(subscription_id)
SyncsSubscription.call(subscription: subscription)
```

**Blog Post Angle:** "Handling Stripe webhooks safely"

---

### 7. **Aggressive Refactoring**
**Decision:** Refactor frequently, even in early stage.

**Examples:**
- Extracted 8 reusable view components
- Standardized service naming (third-person verbs)
- Consolidated error constants
- Created shared concerns for logging

**Rationale:**
- Easier to maintain consistency early than retrofit later
- Better onboarding for future developers
- Prevents technical debt accumulation

**Blog Post Angle:** "Refactoring while building: worth it?"

---

## Current Costs (Estimated Monthly)

**Infrastructure:**
- GCP Compute Engine (e2-small): ~$15/month
- GCP Cloud Storage: ~$5/month (100GB audio + feeds)
- Domain: $12/year ($1/month)

**Per-Usage Costs:**
- Google Cloud TTS Standard: $4 per 1M characters (~$0.50-2/month currently)
- Google Cloud TTS Chirp HD: $16 per 1M characters (unlimited tier users only)
- Vertex AI (Gemini 2.5 Flash): ~$0.30 per 1M input tokens (~$0.50-1/month)
- Resend: Free tier (3K emails/month), then $20/month

**Total Current: ~$25-30/month** (infrastructure + low-volume usage)

**At Scale Projections:**
- 100 premium users × 20 episodes/month = 2,000 episodes
- Average 10K characters/episode = 20M characters
- TTS cost: 20M × $4/1M = $80/month
- LLM cost: ~40M tokens × $0.30/1M = $12/month
- Infrastructure scales slowly (can serve 500+ users on e2-small)

**Total at 100 premium users: ~$120-150/month**

**Revenue at 100 premium users (@ $10/month): $1,000/month**

**Margin: ~85%** (after infrastructure and per-usage costs)

---

## Blog Post #3 Outline: "The Stack"

### Introduction
- Built Very Normal TTS to solve my own problem (73 browser tabs)
- Launched in beta January 2026, currently at [X] users
- Rails 8, Hotwire, SQLite - "boring tech" that ships fast
- This post: technical decisions, cost breakdown, lessons learned

### The Stack Breakdown

**Backend:**
- Rails 8.1.2 + Ruby 3.4.5
- SQLite with WAL mode (yes, in production)
- Solid Queue, Cache, Cable (Rails 8 defaults)
- Service objects with Result pattern

**Frontend:**
- Hotwire (Turbo + Stimulus)
- Tailwind CSS
- Import Maps (no build step!)

**External Services:**
- Google Cloud TTS (Standard + Chirp HD)
- Google Cloud Storage
- Vertex AI (Gemini 2.5 Flash)
- Resend (email)
- Stripe (billing)

**Deployment:**
- Kamal 2.0 to single GCP server
- Docker via Artifact Registry
- Puma + Thruster
- Let's Encrypt SSL

### Key Decisions & Trade-offs

1. **SQLite in Production**
   - Enabled WAL mode for concurrency
   - Per-user job limits prevent lock contention
   - Works great for single-server apps
   - Will need Postgres when scaling to multiple servers

2. **Solid Queue In-Process**
   - No separate job server needed
   - Simpler deployment
   - Trade-off: shares resources with web server

3. **Hotwire for Real-time**
   - Episode cards update live during processing
   - No React/Vue complexity
   - Turbo Streams = WebSocket updates without writing JavaScript

4. **Service Objects Everywhere**
   - 40+ service classes
   - Thin controllers (2-5 lines)
   - Easy to test in isolation
   - Result pattern for explicit error handling

5. **Kamal Deployment**
   - Full control over infrastructure
   - Lower costs than managed platforms
   - Learning curve paid off

### Cost Breakdown

**Fixed Costs:**
- GCP e2-small server: $15/month
- Cloud Storage: $5/month
- Domain: $1/month
- **Subtotal: $21/month**

**Variable Costs (current low volume):**
- TTS API: ~$1-2/month
- LLM API: ~$0.50-1/month
- Resend: Free tier (3K emails/month)
- **Subtotal: $2-3/month**

**Total Current: ~$25/month**

**Projected at 100 Premium Users:**
- Infrastructure: $25/month (same)
- TTS: $80/month (20M chars)
- LLM: $12/month (40M tokens)
- Resend: $20/month (over free tier)
- **Total: ~$140/month**

**Revenue at 100 users × $10/month: $1,000/month**
**Gross Margin: 86%**

### Lessons Learned

**What Worked:**
- Rails 8 defaults (Solid libraries) are production-ready
- SQLite handles more than you think
- Hotwire eliminates so much JavaScript
- Service objects keep codebase maintainable
- Aggressive refactoring prevents tech debt

**What Was Hard:**
- SQLite concurrency required careful design
- Google Cloud IAM for signed URLs was tricky
- Stripe webhooks need re-fetch pattern for security
- Race conditions in real-time updates (Turbo Streams)

**What I'd Do Differently:**
- Set up structured logging (action_id) from day one
- Write more system tests earlier
- Deploy to staging environment before production
- Use feature flags for premium features

### Development Timeline

- **Week 1-2:** Core features (URL/paste/file → audio → RSS)
- **Week 3:** Magic link auth, real-time updates
- **Week 4:** Stripe billing, pricing page
- **Week 5:** Production hardening, bug fixes
- **Week 6:** Voice expansion, UX polish

**Total: ~6 weeks part-time to beta launch**

### Tools That Made This Possible

- **GitHub Copilot**: 40% of code written (especially tests)
- **RuboCop**: Code style consistency
- **Brakeman**: Security scanning
- **Minitest**: Fast, simple testing
- **Kamal**: Deploy with `kamal deploy`

### Open Questions

- When to move from SQLite to Postgres?
- When to split job processing to separate server?
- How to handle background job failures at scale?
- Should I open source parts of this?

### Conclusion

Built a production SaaS with Rails 8 defaults in 6 weeks part-time. Current costs: $25/month. Projected margin at scale: 85%+.

The "boring tech" approach works. SQLite, Hotwire, and Kamal let me focus on building features instead of infrastructure.

Biggest lesson: Rails 8 is incredibly productive. The Solid libraries eliminate so much complexity.

If you're building a side project, consider this stack. It ships fast and stays simple.

---

**Questions for readers:**
- What would you want to know about this stack?
- Interested in specific technical deep-dives?
- Want me to open source any parts?

**Reach out:** jspevack@gmail.com or [@jspevack](https://twitter.com/jspevack)

---

**Date:** January 2026
**Commits:** 65 total (this document covers Dec 29 - Jan 19)
**Lines of Code:** ~8,000 (Ruby) + ~2,000 (ERB/CSS/JS)
**Test Coverage:** ~85%
