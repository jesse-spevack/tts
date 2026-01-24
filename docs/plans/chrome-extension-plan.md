# Chrome Extension Implementation Plan

## Overview

Build a Chrome extension that lets users send any webpage to their TTS podcast feed with one click, using client-side article extraction.

---

## Decisions Summary

| Decision | Choice |
|----------|--------|
| Trigger | Icon click only (no context menu) |
| Feedback | Icon state changes (no toasts) |
| Podcast selection | Use first/primary podcast |
| Voice/settings | Use account defaults |
| Extraction | Client-side with Readability.js |
| Extraction fallback | None — show error if fails |
| Auth mechanism | Bearer token (ApiToken model) |
| Token visibility | User never sees token |
| Repository structure | Monorepo (`browser_extension/` directory) |
| Language | TypeScript |
| Distribution | Unlisted initially, public later |

---

## Out of Scope

- Firefox support
- Mobile share sheet
- Batch URL submission
- Context menu trigger
- Popup for podcast/voice selection

---

## User Flows

### Flow 1: First-time Connect

```
1. User clicks extension icon
2. Not connected → auto-opens TTS auth page
3a. If already logged in → backend generates token, redirects with token
3b. If not logged in → magic link flow → then generates token
4. Extension captures token, stores in chrome.storage.sync
5. Extension shows success state
```

### Flow 2: Send Article (Happy Path)

```
1. User is on an article page
2. Clicks extension icon
3. Extension runs pre-check (is this article-like?)
4. Readability.js extracts: title, content, author, description
5. Extension sends to POST /api/v1/episodes
6. Backend creates episode, returns { id: "..." }
7. Icon shows success state (checkmark) briefly
```

### Flow 3: Non-Article Page

```
1. User clicks icon on non-article page (e.g., Google homepage)
2. Pre-check detects "not article-like"
3. Icon shows error state
4. No request sent to backend
```

### Flow 4: Extraction Failure

```
1. User clicks icon on article page
2. Pre-check passes
3. Readability.js fails to extract
4. Extension sends failure log to backend (URL, error reason)
5. Icon shows error state
```

### Flow 5: Disconnect

**From extension:**
```
1. User opens extension popup/options
2. Clicks "Disconnect"
3. Extension clears token from chrome.storage.sync
4. Icon returns to "not connected" state
```

**From web:**
```
1. User goes to Settings → Extensions
2. Clicks "Disconnect extension"
3. Backend revokes token (sets revoked_at)
4. Next extension request gets 401
5. Extension clears local token, prompts reconnect
```

---

## Error States

| Condition | Icon State | Behavior |
|-----------|------------|----------|
| Not connected | Neutral/dimmed | Auto-opens Connect flow on click |
| Sending | Loading spinner | — |
| Success | Checkmark (brief) | Returns to neutral |
| Network offline | Offline icon | — |
| Backend down | Error icon | — |
| Rate limit hit | Slow-down icon | — |
| Account suspended | Error icon | Clears token, prompts reconnect |
| Not an article | Error icon | — |
| Extraction failed | Error icon | Logs to backend |

---

## API Design

### Endpoint: Create Episode from Extension

```
POST /api/v1/episodes
Authorization: Bearer <token>
Content-Type: application/json

{
  "title": "Article Title",
  "content": "Extracted article text...",
  "url": "https://example.com/article",
  "author": "Author Name",
  "description": "Short excerpt/summary"
}
```

**Success Response (201):**
```json
{
  "id": "episode_abc123"
}
```

**Error Responses:**
- `401 Unauthorized` — Invalid/revoked token
- `422 Unprocessable Entity` — Validation errors
- `429 Too Many Requests` — Rate limit exceeded

### Endpoint: Log Extension Failure

```
POST /api/v1/extension_logs
Authorization: Bearer <token>
Content-Type: application/json

{
  "url": "https://example.com/weird-page",
  "error_type": "extraction_failed",
  "error_message": "Readability could not parse content"
}
```

**Response (201):**
```json
{
  "logged": true
}
```

### Endpoint: Generate Token (for Connect flow)

```
GET /api/v1/auth/extension_token
(requires existing session cookie)
```

**Response (200):**
```json
{
  "token": "tts_ext_abc123..."
}
```

Or redirects to: `chrome-extension://<extension-id>/callback?token=tts_ext_abc123...`

---

## Data Model

### ApiToken

```ruby
create_table :api_tokens do |t|
  t.references :user, null: false, foreign_key: true
  t.string :token_digest, null: false  # hashed, never store plain
  t.string :token_prefix, null: false  # first 8 chars for identification
  t.datetime :last_used_at
  t.datetime :revoked_at
  t.timestamps
end

add_index :api_tokens, :token_digest, unique: true
add_index :api_tokens, :token_prefix
```

**Notes:**
- Store token hashed (like passwords)
- `token_prefix` allows showing "tts_ext_abc1..." in UI without exposing full token
- One active (non-revoked) token per user for now

### ExtensionLog (optional, for failure tracking)

```ruby
create_table :extension_logs do |t|
  t.references :user, null: false, foreign_key: true
  t.string :url
  t.string :error_type
  t.text :error_message
  t.timestamps
end
```

---

## Extension Structure

```
browser_extension/
├── src/
│   ├── background.ts      # Service worker (Manifest V3)
│   ├── content.ts         # Content script (Readability extraction)
│   ├── popup.html         # Simple popup (Connect button when not auth'd)
│   ├── popup.ts
│   ├── api.ts             # API client
│   ├── auth.ts            # Token storage/management
│   ├── extractor.ts       # Readability.js wrapper + pre-check
│   └── icons.ts           # Icon state management
├── lib/
│   └── Readability.js     # Mozilla's Readability
├── icons/
│   ├── icon-16.png
│   ├── icon-48.png
│   ├── icon-128.png
│   ├── icon-success.png
│   ├── icon-error.png
│   └── icon-loading.png
├── manifest.json
├── package.json
├── tsconfig.json
└── jest.config.js
```

---

## Manifest V3

```json
{
  "manifest_version": 3,
  "name": "TTS Podcast",
  "version": "1.0.0",
  "description": "Send any article to your TTS podcast feed",
  "permissions": [
    "activeTab",
    "storage"
  ],
  "host_permissions": [
    "https://your-tts-domain.com/*"
  ],
  "action": {
    "default_popup": "popup.html",
    "default_icon": {
      "16": "icons/icon-16.png",
      "48": "icons/icon-48.png",
      "128": "icons/icon-128.png"
    }
  },
  "background": {
    "service_worker": "background.js"
  },
  "content_scripts": [
    {
      "matches": ["<all_urls>"],
      "js": ["content.js"]
    }
  ],
  "icons": {
    "16": "icons/icon-16.png",
    "48": "icons/icon-48.png",
    "128": "icons/icon-128.png"
  }
}
```

---

## Rate Limiting

- **Limit:** 20 episodes per hour per user
- **Implementation:** Rails `Rack::Attack` or custom middleware
- **Response:** 429 with `Retry-After` header
- **Extension behavior:** Show "slow down" icon state

---

## Duplicate Prevention

- **Client-side:** 5-second debounce after successful send
- **Server-side:** None (allow re-sending same URL after debounce)

---

## Web App Changes

### Settings → Extensions Page

New page at `/settings/extensions`:

- Shows connection status (connected/not connected)
- Shows token prefix ("tts_ext_abc1...")
- Shows last used timestamp
- "Disconnect" button to revoke token
- Link to Chrome Web Store (unlisted URL)

### Privacy Policy Update

Add section covering:
- Extension collects current page URL and content
- Content sent to TTS servers for processing
- No data sold to third parties

---

## Chrome Web Store

### Required Assets

| Asset | Spec |
|-------|------|
| Icon 128x128 | PNG, extension icon |
| Screenshot | 1280x800 or 640x400, showing extension in action |
| Short description | 132 chars max |
| Detailed description | Features, how it works |
| Privacy policy URL | Link to /privacy |

### Listing Details

- **Visibility:** Unlisted initially
- **Category:** Productivity
- **Link from:** Settings → Extensions page in web app

---

## Testing Strategy

### Extension Tests (Jest + jest-chrome)

- Token storage/retrieval
- API client request formatting
- Readability extraction wrapper
- Icon state transitions
- Pre-check logic for article detection
- Debounce behavior

### Backend Tests (Rails request specs)

- `POST /api/v1/episodes` with valid token
- `POST /api/v1/episodes` with invalid/revoked token
- `POST /api/v1/episodes` rate limiting
- `GET /api/v1/auth/extension_token` with session
- `GET /api/v1/auth/extension_token` without session
- Token revocation flow

### Manual Testing Checklist

- [ ] First-time connect flow (not logged in)
- [ ] First-time connect flow (already logged in)
- [ ] Send article from news site
- [ ] Send article from paywalled site (logged in)
- [ ] Send non-article page (should fail gracefully)
- [ ] Disconnect from extension
- [ ] Disconnect from web, verify extension handles it
- [ ] Rapid clicking (debounce works)
- [ ] Offline behavior
- [ ] Rate limit behavior

---

## Implementation Order

### Phase 1: Backend Foundation
1. Create `ApiToken` model and migration
2. Add token generation/revocation logic
3. Create `Api::V1::BaseController` with token auth
4. Create `Api::V1::EpisodesController`
5. Add rate limiting
6. Create extension token generation endpoint

### Phase 2: Web App UI
7. Create Settings → Extensions page
8. Add connect/disconnect UI
9. Update privacy policy

### Phase 3: Extension Core
10. Set up TypeScript build pipeline
11. Create manifest.json
12. Implement token storage (auth.ts)
13. Implement API client (api.ts)
14. Implement Readability wrapper + pre-check (extractor.ts)

### Phase 4: Extension UX
15. Implement icon state management
16. Implement popup (connect button)
17. Wire up icon click → extract → send flow
18. Add debounce logic
19. Add error state handling

### Phase 5: Polish & Deploy
20. Create extension icons from TTS branding
21. Write Chrome Web Store descriptions
22. Package extension
23. Register Chrome Web Store developer account
24. Submit for review (unlisted)
25. Add extension link to Settings page

---

## Open Items for Implementation

1. **Exact TTS domain** for `host_permissions` in manifest
2. **Extension ID** — generated by Chrome, needed for callback URL
3. **Icon assets** — need to export from existing TTS branding
4. **Connect flow callback mechanism** — exact redirect/message passing approach

---

## Appendix: Readability.js Pre-check

Heuristics to detect if page is "article-like" before running full extraction:

```typescript
function isArticleLike(document: Document): boolean {
  // Check for article-indicating elements
  const hasArticle = !!document.querySelector('article');
  const hasMainContent = !!document.querySelector('[role="main"], main');

  // Check for significant text content
  const bodyText = document.body?.innerText || '';
  const wordCount = bodyText.split(/\s+/).length;
  const hasEnoughContent = wordCount > 200;

  // Check for blog/article meta tags
  const hasArticleMeta = !!document.querySelector(
    'meta[property="og:type"][content="article"], ' +
    'meta[property="article:published_time"]'
  );

  return hasArticle || hasArticleMeta || (hasMainContent && hasEnoughContent);
}
```

This reduces failed extraction attempts on obvious non-articles (homepages, web apps, etc.).
