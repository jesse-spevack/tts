# MPP Integration Scope for Podread

## Overview

This document scopes what would be needed to integrate the [Machine Payments Protocol (MPP)](https://mpp.dev) into Podread, enabling machine-to-machine payments for the `/api/v1/` endpoints. MPP would allow AI agents and programmatic clients to pay per-episode without needing a user account, API key, or Stripe subscription.

## Why MPP?

Podread's current monetization requires users to:
1. Create an account (magic link)
2. Subscribe via Stripe or buy credit packs
3. Use a Bearer token for API access

MPP removes this friction for programmatic clients. An agent discovers the price via HTTP 402, pays inline, and gets the resource — no signup, no API key management. This opens Podread to the emerging agent economy where AI agents autonomously consume paid services.

## What MPP Would Enable

| Use Case | Flow |
|---|---|
| Agent creates an episode | `POST /api/v1/episodes` returns 402 with price → agent pays → episode created |
| Agent lists voices | `GET /api/v1/voices` — could remain free or be gated |
| Agent checks episode status | `GET /api/v1/episodes/:id` — likely free once paid for creation |

The primary monetizable endpoint is **episode creation** (`POST /api/v1/episodes`), which maps cleanly to MPP's `charge` intent (one-time payment per request).

## Key Technical Challenges

### 1. No Ruby SDK

MPP provides official SDKs for TypeScript, Python, and Rust — **not Ruby**. This is the single largest integration challenge. Options:

**Option A: Build a Ruby gem (recommended)**
- Implement MPP core primitives: Challenge, Credential, Receipt serialization/deserialization
- Implement HTTP transport (header parsing/writing for `WWW-Authenticate` and `Payment-Credential`)
- Implement Tempo charge verification (on-chain payment proof validation)
- Estimated effort: ~2-3 weeks for a minimal viable gem
- Benefit: Native Rails middleware, idiomatic Ruby

**Option B: Sidecar proxy in TypeScript/Python**
- Run an `mppx` proxy alongside the Rails app
- Proxy intercepts requests, handles 402 challenge/credential flow, forwards paid requests to Rails
- Rails app receives pre-authenticated requests with a payment receipt header
- Estimated effort: ~1 week
- Downside: Added infrastructure complexity, another process to manage, latency overhead

**Option C: Rack middleware with FFI to Rust SDK**
- Use the `mpp` Rust crate via Ruby FFI
- Wrap core verification logic in a thin Ruby layer
- Estimated effort: ~2 weeks
- Downside: Build complexity, cross-compilation for deployment

**Recommendation:** Option B (sidecar proxy) for initial launch, migrate to Option A (Ruby gem) if MPP adoption warrants it.

### 2. Payment Method Selection

MPP supports multiple payment methods. For Podread:

| Method | Fit | Notes |
|---|---|---|
| **Tempo** (stablecoins) | Good for agents | Low-cost, instant settlement, testnet available |
| **Stripe** | Good for existing users | Bridges to existing Stripe infrastructure |
| **Lightning** | Niche | Bitcoin-native agents |

**Recommendation:** Start with Tempo charge (simplest, best agent UX), add Stripe charge later to leverage existing Stripe account.

### 3. Pricing Model

Current pricing:
- Free tier: 2 episodes/month
- Premium: $8/month unlimited
- Credits: $4.99 for 5 episodes ($1/episode)

MPP pricing for per-episode charges:
- **$1.00 per episode** (matches credit pack pricing)
- Could offer volume discounts via session-based billing later
- No account required — pure pay-per-use

### 4. Authentication Coexistence

The API currently requires Bearer token auth. MPP would need to work **alongside** existing auth:

```
Request arrives at /api/v1/episodes
  ├─ Has Bearer token? → Existing auth flow (account-based billing)
  └─ No Bearer token? → MPP flow (402 challenge → payment → resource)
```

This means the `before_action :authenticate_token!` in `Api::V1::BaseController` needs to be conditional: skip authentication for MPP-enabled endpoints when no Bearer token is present but a Payment-Credential header is.

### 5. User/Account Model for MPP Payments

MPP requests are anonymous — no user account. Options:
- Create a system "anonymous" user for MPP episodes
- Create ephemeral users per wallet address (enables history if same wallet returns)
- Store MPP episodes without a user association (new column/model)

**Recommendation:** Create ephemeral users keyed by wallet address. This enables repeat customers to see their history and naturally fits the existing data model.

## Implementation Plan

### Phase 1: Proof of Concept (1-2 weeks)

1. **Set up mppx TypeScript proxy** as a sidecar
   - Configure it to front the Rails API
   - Set up Tempo charge method with recipient address
   - Configure pricing: $1.00 per `POST /api/v1/episodes`
2. **Add proxy to deployment** (Docker Compose / Kamal accessory)
3. **Modify Rails API** to accept requests forwarded by the proxy
   - Read `Payment-Receipt` header to confirm payment
   - Skip Bearer token auth when valid receipt is present
   - Create/find ephemeral user for the wallet address
4. **Test end-to-end** with `npx mppx` CLI

### Phase 2: Production Hardening (1-2 weeks)

1. **Receipt verification** — Verify receipts server-side (don't just trust the proxy)
2. **Idempotency** — Ensure duplicate payment credentials don't create duplicate episodes
3. **Rate limiting** — Apply Rack::Attack rules for MPP requests
4. **Monitoring** — Track MPP payments alongside Stripe revenue
5. **Error handling** — Return proper Problem Details (RFC 9457) for payment failures

### Phase 3: Native Ruby Integration (2-3 weeks, optional)

1. **Build `mpp-ruby` gem** with core primitives
2. **Replace proxy** with Rack middleware
3. **Add Stripe payment method** to accept cards via MPP (reuse existing Stripe account)
4. **Add multiple payment methods** via `Mppx.compose`

## Files That Would Change

| File | Change |
|---|---|
| `app/controllers/api/v1/base_controller.rb` | Conditional auth: Bearer OR MPP receipt |
| `app/controllers/api/v1/episodes_controller.rb` | Handle anonymous MPP users, skip permission checks for paid requests |
| `config/routes.rb` | Possibly add MPP-specific routes or version namespace |
| `app/models/user.rb` | Support ephemeral/anonymous users or MPP wallet association |
| `app/services/checks_episode_creation_permission.rb` | Bypass tier limits for MPP-paid episodes |
| `config/deploy.yml` | Add mppx proxy as Kamal accessory |
| `Gemfile` | Add any new dependencies (e.g., JWT parsing, receipt verification) |
| `config/initializers/rack_attack.rb` | Rate limiting rules for MPP endpoints |

## New Files

| File | Purpose |
|---|---|
| `app/controllers/concerns/mpp_authentication.rb` | MPP receipt verification concern |
| `app/services/finds_or_creates_mpp_user.rb` | Ephemeral user management for MPP wallets |
| `app/services/verifies_mpp_receipt.rb` | Receipt validation logic |
| `config/mpp_proxy/` | Proxy configuration (if using sidecar approach) |

## Open Questions

1. **Should free endpoints (voices, episode show) require payment?** Probably not — only gate episode creation.
2. **Should MPP users get the same voice selection as premium?** Paying $1/episode is more than the premium per-episode cost, so arguably yes.
3. **How to handle long-running episode processing?** MPP payment happens at creation time, but audio generation is async. The receipt confirms payment; the client polls for completion. This is fine — MPP doesn't require synchronous delivery.
4. **Refunds?** If episode processing fails, how to refund? MPP receipts are proof of delivery. We could issue credits or handle via Tempo's dispute mechanism (if available).
5. **Which Tempo network?** Testnet for development, mainnet for production. Need a Tempo wallet for receiving payments.
6. **Revenue reconciliation?** Need to track MPP revenue alongside Stripe revenue for accounting.

## Dependencies

- Tempo wallet address for receiving payments
- Decision on proxy vs. native approach
- MPP Ruby SDK availability (check if community gem exists)
- Testnet USDC for development testing

## Estimated Total Effort

| Phase | Effort | Dependency |
|---|---|---|
| Phase 1: PoC with proxy | 1-2 weeks | Tempo wallet |
| Phase 2: Production hardening | 1-2 weeks | Phase 1 |
| Phase 3: Native Ruby gem | 2-3 weeks | Optional, Phase 2 |

**Minimum viable integration: 2-4 weeks** (Phases 1+2)
