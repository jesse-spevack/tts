# MPP Payments Design Brief

## Overview

Add Machine Payments Protocol (MPP) support to PodRead's episode creation API. MPP allows any caller — authenticated or anonymous — to pay per episode via HTTP 402 challenges, without needing an account or subscription.

## Goals

- Open episode creation to machine-to-machine callers (AI agents, scripts, services) who pay per request
- Give authenticated non-subscribers a paid path to create episodes without committing to a subscription
- Integrate with existing Stripe infrastructure via Shared Payment Tokens (SPTs)
- Keep the existing subscription flow unchanged

## Non-Goals

- Replacing subscriptions or credit packs
- Building a standalone TTS-as-a-service API (raw audio without episodes)
- Crypto/Tempo payment support (future consideration)

## Authorization Model

Three paths to create an episode, all through the existing `POST /api/v1/episodes` endpoint:

| Caller | Auth Header | Payment | Episode Ownership |
|---|---|---|---|
| Subscriber | `Authorization: Bearer <token>` | Subscription covers it | User's podcast feed |
| Authenticated non-subscriber | `Authorization: Bearer <token>` + MPP credential | Pay per episode via MPP | User's podcast feed |
| Anonymous agent | MPP credential only | Pay per episode via MPP | Ephemeral (no feed) |

Decision logic:

```
Request arrives at POST /api/v1/episodes
  |
  |- Bearer token present?
  |    |- Yes -> Authenticate user
  |    |    |- User is subscriber? -> Allow (no payment needed)
  |    |    |- Not subscriber? -> Require MPP payment
  |    |
  |    |- No -> Require MPP payment
  |
  |- MPP credential present?
       |- Yes -> Verify credential, process Stripe payment
       |    |- Payment succeeds -> Create episode
       |    |- Payment fails -> 402
       |
       |- No -> Return 402 challenge
```

## MPP Protocol Flow

MPP is an HTTP-based protocol. No Ruby SDK exists, so we implement the protocol directly using `OpenSSL::HMAC` and Stripe's API.

### Step 1: Client sends request (no credential)

```http
POST /api/v1/episodes HTTP/1.1
Content-Type: application/json

{"source_type": "url", "url": "https://example.com/article"}
```

### Step 2: Server returns 402 with challenge

```http
HTTP/1.1 402 Payment Required
WWW-Authenticate: PaymentRequired challenge="<base64-encoded-challenge>"
Content-Type: application/json

{
  "type": "https://paymentauth.org/problems/payment-required",
  "title": "Payment Required",
  "status": 402,
  "detail": "Payment is required to create an episode.",
  "challengeId": "ch_abc123",
  "request": {
    "amount": "1.00",
    "currency": "usd",
    "decimals": 2,
    "description": "Create podcast episode"
  },
  "methods": [
    {
      "type": "stripe.charge",
      "networkId": "internal",
      "paymentMethodTypes": ["card", "link"]
    }
  ]
}
```

The challenge is HMAC-signed with a server-side secret, binding the price to the request so it cannot be tampered with.

### Step 3: Client pays and retries

```http
POST /api/v1/episodes HTTP/1.1
Content-Type: application/json
Authorization: PaymentRequired credential="<base64-credential-containing-SPT>"

{"source_type": "url", "url": "https://example.com/article"}
```

### Step 4: Server processes payment and creates episode

The server:
1. Extracts the SPT from the credential
2. Verifies the HMAC signature matches the original challenge
3. Creates a Stripe PaymentIntent using the SPT
4. On success, creates the episode and enqueues processing
5. Returns 201 with episode ID and Payment-Receipt header

```http
HTTP/1.1 201 Created
Payment-Receipt: receipt="<base64-receipt>"
Content-Type: application/json

{
  "id": "ep_abc123",
  "status": "processing",
  "estimated_seconds": 25
}
```

The episode then follows the normal async processing pipeline (LLM extraction, TTS synthesis, GCS upload). The client polls `GET /api/v1/episodes/:id` for status — same as today.

## Pricing

Flat rate per episode: **$1.00 USD**

Matches existing credit pack unit economics ($4.99 / 5 episodes). A single price keeps the protocol flow simple — no need to estimate content length before generating the challenge.

## Endpoint Changes

### Modified: `POST /api/v1/episodes`

- Currently requires `Bearer` token authentication
- Will also accept `PaymentRequired` MPP credentials
- Returns `402` instead of `401` when no valid auth is provided

### Unchanged: `GET /api/v1/episodes/:id`

- Authenticated callers poll this as usual
- Anonymous MPP callers use a short-lived access token returned in the 201 response (design TBD)

### Unchanged: All other endpoints

No changes to subscriptions, credit packs, web UI, MCP, or any other endpoint.

## Architecture

### New Files

```
app/services/mpp/
  generates_challenge.rb      # HMAC-signed 402 challenge with pricing
  verifies_credential.rb      # Parse + validate MPP credential, verify HMAC
  processes_payment.rb        # Create Stripe PaymentIntent from SPT
  generates_receipt.rb        # Payment-Receipt header for 201 response

app/controllers/concerns/
  mpp_payable.rb              # Shared before_action logic for MPP auth

app/models/
  mpp_payment.rb              # Tracks MPP transactions

db/migrate/
  xxx_create_mpp_payments.rb  # Migration
```

### Modified Files

```
config/routes.rb              # No URL changes needed
app/models/app_config.rb      # Add Mpp config (secret key, price)
app/controllers/api/v1/
  episodes_controller.rb      # Add MPP authorization path
  base_controller.rb          # Extract bearer auth to allow override
```

### Reused As-Is (No Changes)

```
app/services/creates_url_episode.rb
app/services/creates_paste_episode.rb
app/services/synthesizes_audio.rb
app/services/generates_episode_audio.rb
app/services/tts/*
```

The entire episode processing pipeline (LLM, TTS, GCS, RSS) is unchanged. MPP only affects the authorization layer at the entry point.

## Data Model

### `mpp_payments` table

| Column | Type | Description |
|---|---|---|
| `id` | integer | Primary key |
| `public_id` | string | Prefixed ID for external reference (e.g. `mpp_abc123`) |
| `stripe_payment_intent_id` | string | Stripe PI ID |
| `amount_cents` | integer | Amount charged (e.g. 100 for $1.00) |
| `currency` | string | Currency code (e.g. "usd") |
| `status` | string | pending / completed / failed |
| `episode_id` | integer | FK to episodes (nullable, set after episode creation) |
| `user_id` | integer | FK to users (nullable, null for anonymous) |
| `challenge_id` | string | Challenge ID for correlation |
| `created_at` | datetime | |
| `updated_at` | datetime | |

## Anonymous Episode Handling

When an MPP payment comes without a Bearer token:

- No `User` or `Podcast` record exists
- Episode is created with `user_id: nil`
- No RSS feed is generated or updated
- The 201 response includes the episode ID
- Polling `GET /api/v1/episodes/:id` requires a short-lived token returned in the 201 (prevents enumeration)
- Ephemeral episodes are cleaned up after 24 hours

**Open question:** Should we offer anonymous callers a way to claim their episode into an account later (e.g. "provide an email to add this to your feed")?

## Configuration

```ruby
# app/models/app_config.rb
module Mpp
  SECRET_KEY = ENV.fetch("MPP_SECRET_KEY")
  PRICE_CENTS = 100  # $1.00
  CURRENCY = "usd"
  CHALLENGE_TTL_SECONDS = 300  # 5 minutes
end
```

## Environment Variables

| Variable | Description | Required |
|---|---|---|
| `MPP_SECRET_KEY` | HMAC secret for signing challenges | Yes |
| `STRIPE_SECRET_KEY` | Already exists, used for PaymentIntent creation | Already set |

## Security Considerations

- **Challenge binding:** HMAC signature binds price, currency, and timestamp to the challenge. Prevents replay and tampering.
- **Challenge expiry:** Challenges expire after 5 minutes (configurable).
- **Rate limiting:** The MPP endpoint should be rate-limited to prevent challenge flooding (requests that trigger 402s without paying). Rack::Attack rules on the 402 response path.
- **Anonymous episode access:** Short-lived tokens prevent episode ID enumeration by unauthenticated callers.
- **No new secrets in code:** MPP secret key comes from environment variable, same pattern as existing Stripe keys.

## Testing Strategy

- **Unit tests:** Each `Mpp::` service tested in isolation (challenge generation, credential verification, payment processing, receipt generation)
- **Controller tests:** Test the three authorization paths (subscriber, authenticated + MPP, anonymous + MPP) and the 402 challenge response
- **Integration test:** Full round-trip with mocked Stripe API (request → 402 → credential → 201)
- **Manual test:** `npx mppx` CLI tool can hit the endpoint for end-to-end verification

## Open Questions

1. **Anonymous episode polling:** How does an anonymous caller poll for their episode? Options: short-lived JWT in 201 response, or unguessable episode ID as implicit auth.
2. **Episode cleanup:** How long do anonymous episodes persist before cleanup? 24 hours? 7 days?
3. **Authenticated non-subscriber choice:** When a logged-in free user has remaining free episodes, should they still see the MPP option, or only when at their limit?
4. **Ruby MPP implementation:** Build from scratch (~200 lines) or wrap a thin Node.js sidecar? Recommend building from scratch — the protocol is just HMAC + JSON + HTTP headers.

## Future Considerations

- **Crypto/Tempo payments:** MPP supports on-chain stablecoin payments. Could add as a second payment method alongside SPT.
- **MCP transport:** MPP has native MCP transport support. Could wire into the existing `/mcp` endpoint.
- **Variable pricing:** Price by content length or voice quality instead of flat rate.
- **Session-based billing:** MPP supports payment sessions for high-frequency callers (pay-as-you-go with lower per-request overhead).
