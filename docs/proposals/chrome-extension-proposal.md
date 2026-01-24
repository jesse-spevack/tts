# Chrome Extension Proposal: Send to TTS Podcast

## Bottom Line Up Front

Build a minimal Chrome extension that sends the current page URL to the existing TTS backend API. The extension should live in a `browser_extension/` directory within this repository and use the existing server-side article extraction (`FetchesUrl` + `ExtractsArticle` + LLM processing). This leverages proven infrastructure, avoids duplication, and can ship quickly.

---

## Decision: Where to Extract Content?

| Approach | Description | Pros | Cons |
|----------|-------------|------|------|
| **A. Server-side (Recommended)** | Extension sends URL only; backend does all extraction | Reuses existing `FetchesUrl`, `ExtractsArticle`, LLM pipeline; single source of truth; works on pages requiring cookies/JS via backend fetch | Extension is trivial (~100 LOC); no client-side scraping maintenance |
| **B. Client-side extraction** | Extension scrapes DOM, sends extracted text | Access to fully-rendered page including JS content; no CORS issues | Duplicates extraction logic; must maintain two parsers; larger extension bundle if using Readability.js |
| **C. Hybrid** | Extension extracts if possible, falls back to URL | Best of both worlds for edge cases | Complexity; two code paths to maintain; unclear which path was used |

**Recommendation:** Approach A. The backend already handles extraction well. Client-side extraction adds complexity for marginal gain—most articles render fine server-side.

---

## Decision: Repository Structure

| Option | Pros | Cons |
|--------|------|------|
| **Same repo (`browser_extension/`)** | Shared types/API contracts; atomic deploys; simpler CI | Slightly larger repo |
| **Separate repo** | Independent versioning; cleaner separation | Coordination overhead; API contract drift risk |

**Recommendation:** Same repo. The extension is a thin client to the existing API—tight coupling is appropriate.

---

## Technical Approach

**Language:** TypeScript (type safety, matches modern extension development)

**Extension Functionality:**
1. User clicks extension icon or right-click context menu → "Send to TTS"
2. Extension calls `POST /api/v1/episodes` with `{ url: currentTab.url, source_type: "url" }`
3. Auth via stored API token (generated in user settings, stored in `chrome.storage.sync`)
4. Show success/error toast notification

**API Addition Required:**
- Add `Api::V1::EpisodesController` with token-based auth (simple bearer token, no OAuth complexity)
- Endpoint mirrors existing `EpisodesController#create` logic for URL source type

**Manifest V3 Permissions:**
- `activeTab` (get current URL)
- `storage` (persist API token)
- `host_permissions` for TTS API domain only

---

## Testing Strategy

| Layer | Approach |
|-------|----------|
| Extension unit tests | Jest + jest-chrome for mocking Chrome APIs |
| API integration | Existing Rails request specs extended for `/api/v1/episodes` |
| E2E | Manual testing with Playwright browser extension support (optional) |

---

## Deployment

- **Chrome Web Store:** Standard review process; link from TTS settings page
- **Firefox Add-ons:** Same codebase with minor manifest adjustments
- **Updates:** Chrome auto-updates from store; version bump in manifest triggers review

---

## Alternatives Considered & Rejected

1. **Bookmarklet:** No persistent auth; poor UX; can't show feedback
2. **iOS/Android Share Sheet:** Out of scope; different platform
3. **Using Mozilla Readability in extension:** Adds 50KB bundle; duplicates server logic
4. **OAuth flow:** Overengineered for single-app use case; bearer token sufficient

---

## Open Questions

1. Should the extension show a popup with podcast/voice selection, or use defaults?
2. Rate limiting strategy for API endpoint?
