# Landing Page Redesign

## Overview

Redesign the landing page with a cleaner hero section, separate samples page, and mobile-friendly improvements.

## Pages

### 1. Landing Page (`/` → `pages#home`)

**Hero Section**
- Headline: "Turn your reading list into a podcast"
- Tagline: "For everyone with 47 tabs they'll never read"
- Primary CTA: "Get started" (teal button) → scrolls to `#signup`
- Secondary CTA: "Learn more →" (text link) → `/how-it-sounds`
- Layout: Full-width, centered content, generous padding (`py-24 sm:py-32`)

**Signup Section**
- Headline: "Sign in or sign up instantly"
- Subtext: "Enter your email and we'll send a login link"
- Two-column grid on desktop (headline left, form right)
- Single column stacked on mobile
- Anchor: `id="signup"`
- Form POSTs to `session_path` (existing magic link flow)
- Terms link included

### 2. How It Sounds Page (`/how-it-sounds` → `pages#how_it_sounds`)

**Audio Samples**
- Premium voice: `/sample-chirp3-hd-enceladus.mp3`
- Standard voice: `/sample-standard-d.mp3`

**How It Works (3 steps)**
1. Upload a txt or markdown file
2. We convert it to natural-sounding audio
3. Listen in your favorite podcast app via your own RSS feed link

**CTA**
- "Get started" button → `/#signup`

### 3. Episode Form Mobile Fix

Update `episodes/new.html.erb`:
- Card padding: `p-4 sm:p-8` (was `p-8`)
- Drag-and-drop area: `p-4 sm:p-8` (was `p-8`)
- Button group: `flex flex-col sm:flex-row` for stacked buttons on mobile

## Routes

```ruby
# Change root from sessions#new to pages#home
root "pages#home"

# Add samples page
get "how-it-sounds", to: "pages#how_it_sounds"
```

## Files to Change

1. `hub/config/routes.rb` - Update root, add how-it-sounds route
2. `hub/app/controllers/pages_controller.rb` - Add `home` and `how_it_sounds` actions
3. `hub/app/views/pages/home.html.erb` - Create landing page
4. `hub/app/views/pages/how_it_sounds.html.erb` - Create samples page
5. `hub/app/views/episodes/new.html.erb` - Mobile-friendly padding
6. `hub/app/views/layouts/application.html.erb` - May need layout variant for landing page (no header padding)

## Color Scheme

Use existing Catppuccin design system variables:
- Primary button: `bg-[var(--color-primary)]` / `hover:bg-[var(--color-primary-hover)]`
- Text: `text-[var(--color-text)]`
- Subtext: `text-[var(--color-subtext)]`
- Background: `bg-[var(--color-base)]`
