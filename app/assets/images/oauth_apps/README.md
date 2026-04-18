# OAuth app logos

SVGs in this directory are inlined directly into HTML at render time by `UiHelper#oauth_app_badge`. The contents are marked `html_safe` without sanitization — treat them as trusted code and review them like any other file in the repo.

## Contract for adding a new logo

- Use `fill="currentColor"` on rendered shapes so the logo themes with container text color (light/dark mode). Remove baked-in brand fills.
- Remove any `<script>`, `<foreignObject>`, external `<use href="http...">`, or `<style>` elements. The helper strips `<script>` and `<foreignObject>` as a backstop, but don't rely on it.
- Remove `width=` and `height=` attributes from the root `<svg>` — sizing is controlled by the container.
- Keep the `viewBox`.
- Name the file `<slug>.svg` where `<slug>` matches `OauthApplication#name.parameterize` (e.g., "Claude" → `claude.svg`, "ChatGPT" → `chatgpt.svg`).

If an OAuth app is connected with no logo here, `oauth_app_badge` falls back to an initials badge (first letter of each word, max 2).
