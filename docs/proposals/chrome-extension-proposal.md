# Chrome Extension Proposal: Send Articles to TTS Podcast Feed

## Bottom Line Up Front

Build a lightweight Chrome extension using vanilla JavaScript that sends the current page URL to the existing `/episodes` endpoint. Authentication via API tokens stored in Chrome's secure storage. **Recommended approach: server-side extraction** (reuse existing `ExtractsArticle` service) rather than client-side scraping. Ship as a separate repository with automated Chrome Web Store deployment.

---

## Approaches Considered

### 1. Server-Side Extraction (Recommended)

Extension sends only the URL; server fetches and extracts content using existing `FetchesUrl` → `ExtractsArticle` pipeline.

| Pros | Cons |
|------|------|
| Reuses battle-tested extraction logic | Blocked by paywalls the user can access |
| Consistent behavior across clients | Extra network hop (server fetches page) |
| Extension stays simple (~200 LOC) | Cannot access reader-mode content |
| SSRF protections already in place | |

### 2. Client-Side Extraction with Library (e.g., Readability.js)

Extension extracts article content in-browser using Mozilla's Readability, sends text to server.

| Pros | Cons |
|------|------|
| Bypasses paywalls user has access to | Duplicates extraction logic |
| Works on authenticated/dynamic pages | Larger extension bundle (~50KB) |
| Reduces server load | Security review burden (submitted content) |
| | Version drift between client/server extraction |

### 3. LLM-Based Extraction (Client or Server)

Use an LLM to extract and clean article content from raw HTML.

| Pros | Cons |
|------|------|
| Handles complex layouts better | Expensive per-request LLM calls |
| Already using Gemini for processing | Slower extraction time |
| | Overkill—Nokogiri handles 95% of cases |

---

## Recommendation: Hybrid with Server-Side Default

Ship **server-side extraction** as v1. Add optional client-side extraction (Readability.js) in v2 for paywalled content, gated behind a "Send page content" toggle.

---

## Technical Decisions

| Decision | Recommendation | Rationale |
|----------|----------------|-----------|
| **Repository** | Separate repo (`tts-chrome-extension`) | Different release cadence, CI/CD, and language; avoids bloating Rails app |
| **Language** | Vanilla JS + Manifest V3 | No build step, smallest bundle, Chrome's current standard |
| **Auth** | API tokens (new `api_tokens` table) | Session cookies don't work cross-origin; tokens are extension-friendly |
| **API Endpoint** | New `POST /api/v1/episodes` | Versioned, returns JSON, proper CORS headers for extension origin |
| **Testing** | Jest for unit tests, Puppeteer for e2e | Standard extension testing stack; run in CI |
| **Deployment** | GitHub Actions → Chrome Web Store API | Automated publish on tagged releases |

---

## Extension Behavior

1. User clicks extension icon or right-clicks → "Send to TTS"
2. Popup shows extracted title (fetched via `HEAD` or page metadata)
3. User confirms → extension `POST`s URL to `/api/v1/episodes`
4. Server processes async; extension polls for status or shows "Processing..."
5. Badge icon updates when episode is ready

---

## Required Backend Changes

1. **Add `api_tokens` table**: `user_id`, `token_hash`, `name`, `last_used_at`
2. **Add `Api::V1::EpisodesController`**: JSON responses, token auth via `Authorization: Bearer`
3. **CORS configuration**: Allow `chrome-extension://<extension-id>`
4. **Rate limiting**: 10 requests/minute per token (prevent abuse)

---

## Testing Strategy

| Layer | Tool | Coverage |
|-------|------|----------|
| Unit (JS) | Jest | Token storage, URL validation, API calls |
| Integration | Puppeteer + test server | Full submit flow, auth flow |
| Backend | RSpec | New API endpoint, token auth |
| Manual | Chrome beta channel | Pre-release validation |

---

## Open Questions

1. Should the extension support Firefox (WebExtensions API is compatible)?
2. Allow submitting selected text in addition to full articles?
3. Paid-tier upsell UI in extension when limits are hit?
