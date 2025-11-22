# Marketing Landing Page Design

## Overview

Minimal landing page for lead capture / early access signup. Replaces the existing sign-in page with marketing copy added above the form.

## Target Audience

People who want to listen to articles they'd never get around to reading. The insight: "Read later" tabs never get read, but "listen later" actually happens because you can do it while your hands/eyes are busy.

## Content

**Headline:** "The podcast for everything you meant to read"

**Subhead:** "Convert any article to audio. Listen in your favorite podcast app."

**Form:**
- Email input (placeholder: "you@example.com")
- Button: "Send Magic Link"
- Helper text: "Free tier. No credit card."

## Layout

```
┌─────────────────────────────────────────────────────────────────┐
│  Very Normal TTS                                    [☀/☾]      │
└─────────────────────────────────────────────────────────────────┘

              ┌─────────────────────────────────────┐
              │                                     │
              │   The podcast for everything        │
              │   you meant to read                 │
              │                                     │
              │   Convert any article to audio.     │
              │   Listen in your favorite           │
              │   podcast app.                      │
              │                                     │
              │   Email                             │
              │   ┌───────────────────────────┐     │
              │   │ you@example.com           │     │
              │   └───────────────────────────┘     │
              │                                     │
              │   Free tier. No credit card.        │
              │                                     │
              │   ┌───────────────────────────┐     │
              │   │    Send Magic Link        │     │
              │   └───────────────────────────┘     │
              │                                     │
              └─────────────────────────────────────┘
```

## Visual Styling

- Centered card (reuse existing `_card.html.erb` partial)
- Headline: 24px, semi-bold (`text-2xl font-semibold`)
- Subhead: 16px, subtext color (`text-[var(--color-subtext)]`)
- Form uses existing helper methods: `button_classes`, `input_classes`, `label_classes`
- Dark/light mode via existing Catppuccin theme
- Vertically centered on page (existing `min-h-[calc(100vh-10rem)]` pattern)

## Routes

| Path | Logged Out | Logged In |
|------|------------|-----------|
| `/` | Landing page (sessions#new) | Redirect to episodes index |
| `/sign_in` | Redirect to `/` | Redirect to `/` |

## Form Behavior

1. User enters email and clicks "Send Magic Link"
2. Backend checks if email exists:
   - If new: creates free tier account, sends magic link
   - If existing: sends magic link to sign in
3. Same success message either way: "Check your email for a sign-in link"
4. No account enumeration (identical response regardless of account existence)

## Implementation

1. Modify `hub/app/views/sessions/new.html.erb`:
   - Add headline and subhead above form
   - Change helper text from "We'll find your account or create a new one" to "Free tier. No credit card."

2. Update `hub/config/routes.rb`:
   - Set root to `sessions#new` for logged-out users
   - Add redirect from `/sign_in` to root
   - Keep root → episodes#index for logged-in users

## Out of Scope

- Logo/branding beyond "Very Normal TTS"
- Footer
- Additional marketing sections
- Social proof / testimonials
- FAQ
