# Recent Changes Report (Last 2 Days)
**Generated: 2026-01-26**
**Branch: origin/main**
**Commits Reviewed: 17 commits**

---

## High-Level Summary

The past 2 days saw two major feature additions and several supporting changes:

### 1. Chrome Browser Extension (#176)
A complete browser extension allowing users to send web articles to their podcast feed with one click. Includes:
- Manifest V3 Chrome extension with TypeScript
- Token-based API authentication
- Article extraction using Mozilla Readability
- Backend API endpoints (`/api/v1/episodes`, `/api/v1/extension_logs`)
- Rack::Attack rate limiting (20 eps/hour)
- Extension settings page with disconnect functionality

### 2. Email-to-Podcast Feature (#175)
Enables users to create podcast episodes by emailing content. Includes:
- ActionMailbox integration for email routing
- Token-based email authentication (`readtome+token@domain`)
- Email content extraction (plain text preferred, HTML stripped)
- Success/failure notification emails
- Settings UI for enabling/disabling and token regeneration

### 3. Supporting Changes
- Browser extension help page (#177)
- Extension help page icon state fixes
- Privacy policy updates for extension
- Dependabot updates (pagy gem)
- Gitignore updates for extension artifacts

---

## Issues and Improvements (Priority Order)

### P0 - Critical Security

*None identified.* The code demonstrates good security practices overall:
- HMAC-SHA256 token hashing with secret_key_base
- Trusted domain validation for token capture
- Log injection prevention via input sanitization
- Token format validation before storage

### P1 - High Priority (Should Address Soon)

1. **Missing rate limiting for email-to-podcast** (`app/mailboxes/episodes_mailbox.rb`)
   - The email endpoint has no rate limiting, unlike the API endpoint (20/hour)
   - An attacker with a valid token could spam episode creation via email
   - **Suggestion**: Add rate limiting to the mailbox or `CreatesEmailEpisode` service

2. **No email_message sanitization in ExtensionLogsController** (`app/controllers/api/v1/extension_logs_controller.rb:7`)
   - While `error_type` and `url` are sanitized, `error_message` is not logged but could be in the future
   - Currently `error_message` is passed through to `logExtensionFailure` but only `error_type` and `url` are logged
   - **Suggestion**: Add sanitization for `error_message` for consistency if it gets logged later

3. **Token shown in HTML source** (`app/views/extension/connect/show.html.erb:5-6`)
   - Plain token is embedded in both `data-extension-connect-token-value` and `data-tts-token`
   - While necessary for the extension handshake, it's visible in page source
   - **Suggestion**: Consider a more secure handshake mechanism (one-time use JS postMessage with nonce)

### P2 - Medium Priority (Tech Debt)

4. **Duplicate code for token hashing** (`app/services/generates_api_token.rb:41-43` and `app/services/finds_api_token.rb:20-22` and `app/models/api_token.rb:23-25`)
   - Three places define `hash_token` with identical logic
   - **Suggestion**: Keep only `ApiToken.hash_token` and make it public, or extract to a concern

5. **settings namespace defined twice in routes** (`config/routes.rb:45-48` and `55-57`)
   - Two separate `namespace :settings` blocks
   - **Suggestion**: Consolidate into a single block for maintainability

6. **Inconsistent error response status codes between Rack::Attack and API**
   - Rack::Attack returns 429 for rate limiting
   - API returns 403 for episode limit (`check_episode_creation_permission`)
   - Extension code handles both 429 and 403 differently
   - **Suggestion**: Standardize on 429 for all rate/limit exceeded responses

7. **Missing content length validation in API** (`app/services/creates_extension_episode.rb`)
   - The service doesn't validate content length before creating an episode
   - Validation happens later in the job processing, wasting resources
   - **Suggestion**: Add early content length validation like `CreatesEmailEpisode` does

8. **Unused/redundant popup files mentioned in issues**
   - Issue tts-kwg mentions removing unused popup.html and popup.js
   - These files may still be in the build
   - **Suggestion**: Verify and remove if present

### P3 - Low Priority (Nice to Have)

9. **Extension connect page always generates new token on page load** (`app/controllers/extension/connect_controller.rb:12`)
   - Every page refresh generates a new token, revoking previous
   - Could cause issues if user accidentally refreshes during setup
   - **Suggestion**: Check if user already has active extension connection

10. **No explicit handling of encoding issues** (`app/services/extracts_email_content.rb`)
    - HTML stripping uses `ActionController::Base.helpers.strip_tags`
    - May produce unexpected results with non-UTF8 encoded emails
    - **Suggestion**: Add explicit encoding normalization

11. **Missing index on `email_episodes_enabled`** (`db/schema.rb`)
    - The `find_user_by_token` query in episodes_mailbox filters by both `email_ingest_token` AND `email_episodes_enabled`
    - Only `email_ingest_token` has an index
    - **Suggestion**: Consider composite index or rely on unique token index being sufficient

12. **Hardcoded domain in test** (`test/mailboxes/episodes_mailbox_test.rb:40`)
    - Uses `"readtome+invalidtoken123@tts.verynormal.dev"` directly
    - Should use `Rails.configuration.x.email_ingest_domain`
    - **Suggestion**: Use configured domain for test portability

13. **API timeout may be too long** (`browser_extension/src/api.ts:9`)
    - 30 second timeout (`API_TIMEOUT_MS = 30000`) may lead to poor UX
    - User sees loading state for 30 seconds before error
    - **Suggestion**: Consider shorter timeout (10-15s) for better UX

### P4 - Informational (No Action Required)

14. **Active Storage tables added but may not be used**
    - Migration `create_active_storage_tables` added as ActionMailbox dependency
    - Currently no Active Storage attachments appear to be used
    - Keep aware for future cleanup if not needed

15. **Test helper endpoints protected correctly**
    - `TestHelpersController` properly checks `Rails.env.local?`
    - Routes also wrapped in `if Rails.env.local?`
    - Defense in depth is good

---

## Positive Observations

The codebase demonstrates several good practices:

1. **Security-conscious design**: HMAC token hashing, domain validation, input sanitization
2. **Consistent service object pattern**: `Creates*`, `Enables*`, `Generates*`, `Finds*`
3. **Comprehensive test coverage**: Unit tests for all new services and controllers
4. **Structured logging**: Uses `StructuredLogging` concern throughout
5. **Error handling**: Graceful error handling with user-friendly messages via `EmailEpisodeHelper`
6. **Result pattern**: Consistent use of `Result.success`/`Result.failure`
7. **RESTful routing**: Clean nested resource structure
8. **TypeScript for extension**: Type safety in browser extension code

---

## Files Changed Summary

| Category | Files Added | Files Modified |
|----------|-------------|----------------|
| Controllers | 9 | 3 |
| Services | 14 | 1 |
| Models | 1 | 2 |
| Views | 9 | 2 |
| Mailboxes | 2 | 0 |
| Mailers | 1 | 2 |
| Extension (TS) | 16 | 0 |
| Tests | 22 | 3 |
| Config | 2 | 2 |
| Migrations | 5 | 0 |

**Total: ~7,000 lines added across 87 files**

---

## Recommendations Summary

1. **Immediate**: Add rate limiting to email-to-podcast feature
2. **Short-term**: Consolidate token hashing code, fix duplicate route namespaces
3. **Medium-term**: Standardize rate limit response codes, add early content validation
4. **Consider**: More secure token handshake for extension connect flow
