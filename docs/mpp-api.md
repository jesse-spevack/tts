# PodRead MPP API

## Overview

PodRead converts articles and text into podcast-style audio. The Micropayment Protocol (MPP) lets callers pay $1.00 per conversion using on-chain stablecoin (pathUSD) on the Tempo network, without needing a PodRead account. Authenticated users whose free tier is exhausted can also pay via MPP instead of subscribing. The protocol uses a challenge-response flow: the server returns a 402 with payment instructions, the caller sends stablecoin to a one-time deposit address, and retries the request with a credential proving payment.

## Quick Start

The fastest path uses the `mppx` CLI, which handles the 402 challenge, on-chain payment, and credential construction automatically:

```bash
# Create an MPP wallet (one-time setup)
npx mppx account create

# Fund the wallet with testnet pathUSD
npx mppx account fund --rpc-url https://rpc.testnet.tempo.xyz

# Create a narration — mppx handles the 402 flow automatically
npx mppx http://your-podread-host/api/v1/episodes \
  -X POST -H "Content-Type: application/json" \
  -d '{"source_type":"url","url":"https://example.com/article"}' \
  --rpc-url https://rpc.testnet.tempo.xyz
```

The response contains a `narration_id` you can poll for status.

## Protocol Flow

### Step 1: Request episode creation

```bash
curl -X POST https://verynormal.dev/api/v1/episodes \
  -H "Content-Type: application/json" \
  -d '{"source_type":"url","url":"https://example.com/article"}'
```

Without a Bearer token or Payment credential, the server returns **402 Payment Required**:

**Response headers:**

```
HTTP/1.1 402 Payment Required
WWW-Authenticate: Payment id="<hmac-hex>", realm="verynormal.dev", method="tempo", intent="charge", request="<base64-encoded-json>", expires="2026-04-10T12:05:00+00:00"
```

**Response body:**

```json
{
  "error": "Payment required",
  "challenge": {
    "id": "a1b2c3d4e5f6...",
    "amount": 100,
    "currency": "usd",
    "methods": ["tempo"],
    "realm": "verynormal.dev",
    "expires": "2026-04-10T12:05:00+00:00",
    "deposit_address": "0x1234abcd..."
  }
}
```

The `WWW-Authenticate` header's `request` field is a base64-encoded JSON object containing the on-chain payment parameters:

```json
{
  "amount": "1000000",
  "currency": "0x20c0000000000000000000000000000000000000",
  "recipient": "0x1234abcd..."
}
```

- `amount` is in token base units (pathUSD has 6 decimals, so `1000000` = $1.00)
- `currency` is the pathUSD token contract address on Tempo
- `recipient` is the one-time Stripe-provisioned deposit address

### Step 2: Pay

Send a pathUSD transfer on the Tempo network to the `deposit_address` from the challenge. The transfer must be:

- To the exact `deposit_address` returned in the 402 response
- For exactly `1000000` base units (= $1.00 pathUSD)
- Of the pathUSD token at contract `0x20c0000000000000000000000000000000000000`
- Completed before the challenge `expires` timestamp

### Step 3: Retry with credential

Construct a credential and retry the original request with it in the `Authorization` header.

The credential is a **base64url-encoded** JSON object with two keys:

```json
{
  "challenge": {
    "id": "a1b2c3d4e5f6...",
    "realm": "verynormal.dev",
    "method": "tempo",
    "intent": "charge",
    "request": "<base64-encoded-request-json>",
    "expires": "2026-04-10T12:05:00+00:00"
  },
  "payload": {
    "hash": "0xabc123..."
  }
}
```

The `challenge` object echoes back the fields from the `WWW-Authenticate` header. The `payload` contains either:

- `hash` -- the transaction hash of an already-submitted on-chain transfer, **or**
- `signature` -- a signed raw transaction for the server to submit

Encode this JSON as **base64url** (no padding, using `-` and `_` instead of `+` and `/`) and send it:

```bash
curl -X POST https://verynormal.dev/api/v1/episodes \
  -H "Content-Type: application/json" \
  -H "Authorization: Payment <base64url-encoded-credential>" \
  -d '{"source_type":"url","url":"https://example.com/article"}'
```

On success, the server returns **201 Created**:

```json
{
  "narration_id": "nar_a1b2c3d4e5f6a1b2c3d4e5f6"
}
```

The response includes a `Payment-Receipt` header:

```
Payment-Receipt: tx=0xabc123..., payment=mpp_a1b2c3d4e5f6a1b2c3d4e5f6, sig=<hmac-hex>
```

> **Note:** The `mppx` CLI handles Steps 2 and 3 automatically. If you are building your own client, you must construct the credential yourself.

### Step 4: Poll for status

Audio generation is asynchronous. Poll the narration endpoint:

```bash
curl https://verynormal.dev/api/v1/narrations/nar_a1b2c3d4e5f6a1b2c3d4e5f6
```

**Pending:**

```json
{
  "public_id": "nar_a1b2c3d4e5f6a1b2c3d4e5f6",
  "status": "pending",
  "title": "Example Article",
  "author": "Jane Doe",
  "duration_seconds": null
}
```

**Processing:**

```json
{
  "public_id": "nar_a1b2c3d4e5f6a1b2c3d4e5f6",
  "status": "processing",
  "title": "Example Article",
  "author": "Jane Doe",
  "duration_seconds": null
}
```

### Step 5: Get audio

When status is `"complete"`, the response includes an `audio_url`:

```json
{
  "public_id": "nar_a1b2c3d4e5f6a1b2c3d4e5f6",
  "status": "complete",
  "title": "Example Article",
  "author": "Jane Doe",
  "duration_seconds": 342,
  "audio_url": "https://storage.googleapis.com/verynormal-tts-podcast/narrations/abc123.mp3"
}
```

Narrations expire **24 hours** after creation. After expiration, the narration endpoint returns 404.

## Authentication Paths

The `POST /api/v1/episodes` endpoint supports three authentication paths:

### 1. Subscriber (Bearer token) -- no payment needed

Authenticated users with an active subscription or remaining credits bypass MPP entirely. The existing authorization flow handles them.

```bash
curl -X POST https://verynormal.dev/api/v1/episodes \
  -H "Authorization: Bearer <api-token>" \
  -H "Content-Type: application/json" \
  -d '{"source_type":"url","url":"https://example.com/article"}'
```

Returns a standard `201 Created` with `{"id": "ep_abc123"}`.

### 2. Authenticated non-subscriber (Bearer + Payment) -- creates Episode for user

Users with a valid Bearer token who have exhausted their free tier and have no credits receive a 402 challenge. They can pay via MPP and include both tokens:

```bash
curl -X POST https://verynormal.dev/api/v1/episodes \
  -H "Authorization: Bearer <api-token>, Payment <credential>" \
  -H "Content-Type: application/json" \
  -d '{"source_type":"url","url":"https://example.com/article"}'
```

This creates an **Episode** attached to the user's account (appears in their episode list, added to their podcast feed).

Returns `201 Created` with `{"id": "ep_abc123"}` and a `Payment-Receipt` header.

### 3. Anonymous (Payment only) -- creates Narration

Requests with no Bearer token (or an invalid one) and a valid Payment credential create a **Narration** -- a standalone audio file not attached to any user account.

```bash
curl -X POST https://verynormal.dev/api/v1/episodes \
  -H "Authorization: Payment <credential>" \
  -H "Content-Type: application/json" \
  -d '{"source_type":"url","url":"https://example.com/article"}'
```

Returns `201 Created` with `{"narration_id": "nar_abc123"}` and a `Payment-Receipt` header.

Narrations expire after 24 hours.

## Request/Response Reference

### POST /api/v1/episodes

**Request body parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `source_type` | string | Yes | One of `"url"`, `"text"`, or `"extension"` |
| `url` | string | For `url`/`extension` | URL of the article to convert |
| `text` | string | For `text` | Raw text to convert |
| `content` | string | For `extension` | HTML content from browser extension |
| `title` | string | No | Episode title (defaults to `"Untitled"`) |
| `author` | string | No | Author name |
| `description` | string | No | Episode description |

**402 Payment Required response:**

Headers:
```
WWW-Authenticate: Payment id="<hmac-hex>", realm="verynormal.dev", method="tempo", intent="charge", request="<base64>", expires="<iso8601>"
```

Body:
```json
{
  "error": "Payment required",
  "challenge": {
    "id": "<hmac-hex-string>",
    "amount": 100,
    "currency": "usd",
    "methods": ["tempo"],
    "realm": "verynormal.dev",
    "expires": "<iso8601-timestamp>",
    "deposit_address": "<0x-ethereum-address>"
  }
}
```

**201 Created response (anonymous/MPP):**

```json
{
  "narration_id": "nar_<24-hex-chars>"
}
```

**201 Created response (authenticated/MPP):**

```json
{
  "id": "ep_<prefix-id>"
}
```

**201 Created response (subscriber, no MPP):**

```json
{
  "id": "ep_<prefix-id>"
}
```

**422 Unprocessable Entity:**

```json
{
  "error": "source_type is required. Use 'url', 'text', or 'extension'."
}
```

**503 Service Unavailable (Stripe provisioning failure):**

```json
{
  "error": "Payment provisioning failed: <stripe-error-message>"
}
```

### GET /api/v1/narrations/:public_id

No authentication required. The `public_id` is the `narration_id` returned from the creation endpoint.

**Response body:**

| Field | Type | Description |
|-------|------|-------------|
| `public_id` | string | The narration identifier |
| `status` | string | One of: `pending`, `preparing`, `processing`, `complete`, `failed` |
| `title` | string | Narration title |
| `author` | string or null | Author name |
| `duration_seconds` | integer or null | Audio duration (populated when complete) |
| `audio_url` | string | Audio file URL (only present when status is `complete`) |

**404 Not Found:**

Returned when the narration does not exist or has expired (narrations expire 24 hours after creation). The response body is empty.

## Pricing

Each episode or narration costs **$1.00 USD**, charged as **1,000,000 base units** of pathUSD on the Tempo network.

- Token: pathUSD at `0x20c0000000000000000000000000000000000000`
- Decimals: 6 (so 1 USD = 1,000,000 base units)
- Network: Tempo (testnet RPC: `https://rpc.testnet.tempo.xyz`)

The `amount` in the 402 response body is in **cents** (100 = $1.00). The `amount` in the `WWW-Authenticate` header's `request` field is in **token base units** (1000000 = $1.00).

If narration processing fails, the payment is automatically refunded.

## Rate Limits

| Endpoint | Limit | Window | Key |
|----------|-------|--------|-----|
| `POST /api/v1/episodes` | 20 requests | 1 hour | Bearer token |
| `GET /api/v1/narrations/:public_id` | 60 requests | 1 minute | IP address |

Throttled requests return **429 Too Many Requests** with a `Retry-After` header:

```json
{
  "error": "Rate limit exceeded. Please try again later."
}
```

## Error Codes

| Status | Meaning | When |
|--------|---------|------|
| 201 | Created | Episode or narration created successfully |
| 402 | Payment Required | No valid subscription/credits and no Payment credential |
| 404 | Not Found | Narration does not exist or has expired |
| 422 | Unprocessable Entity | Invalid or missing `source_type`, or content error |
| 429 | Too Many Requests | Rate limit exceeded |
| 503 | Service Unavailable | Stripe failed to provision a deposit address |

## Environment / Configuration

For self-hosting, the following environment variables configure MPP:

| Variable | Default | Description |
|----------|---------|-------------|
| `MPP_SECRET_KEY` | Random hex (generated at boot) | HMAC key for signing challenges and receipts. **Must be stable across deploys.** |
| `MPP_PRICE_CENTS` | `100` | Price per episode/narration in USD cents |
| `MPP_CURRENCY` | `usd` | Currency code |
| `MPP_CHALLENGE_TTL_SECONDS` | `300` | How long a 402 challenge is valid (seconds) |
| `TEMPO_RPC_URL` | `https://rpc.testnet.tempo.xyz` | Tempo JSON-RPC endpoint for on-chain verification |
| `TEMPO_CURRENCY_TOKEN` | `0x20c0000000000000000000000000000000000000` | pathUSD token contract address |
| `TEMPO_TOKEN_DECIMALS` | `6` | Decimal places for the stablecoin |
| `TEMPO_RPC_OPEN_TIMEOUT_SECONDS` | `5` | TCP connect timeout for RPC calls |
| `TEMPO_RPC_READ_TIMEOUT_SECONDS` | `10` | Read timeout for RPC calls |
| `APP_HOST` | `localhost:3000` | Used as the `realm` in challenges |

Stripe must also be configured (standard `STRIPE_SECRET_KEY` etc.) since deposit addresses are provisioned via Stripe's crypto PaymentIntent API.
