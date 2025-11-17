# Very Normal TTS Design System

## Overview

Clean and minimal design focused on improving visual aesthetics and UX flow for core features: episode creation, status monitoring, and onboarding.

## Layout Structure

### Header (Fixed)
```
┌─────────────────────────────────────────────────────────────┐
│  Very Normal TTS                    user@example.com  [Logout] │
└─────────────────────────────────────────────────────────────┘
```
- Logo/app name: Left-aligned
- User email + logout button: Right-aligned
- Full-width, white/base background with subtle bottom border
- Present on all authenticated pages

### Main Content Area
- Centered container, max-width ~1200px
- Generous padding (responsive)
- Consistent page titles and spacing

### No Footer
Keep it minimal.

## Color Palette

### Catppuccin Latte (Light Mode)
```css
--base: #eff1f5;       /* Page background */
--text: #4c4f69;       /* Primary text */
--surface: #ccd0da;    /* Cards, inputs */
--overlay: #9ca0b0;    /* Borders, dividers */
--subtext: #6c6f85;    /* Secondary text */
```

### Catppuccin Mocha (Dark Mode)
```css
--base: #1e1e2e;       /* Page background */
--text: #cdd6f4;       /* Primary text */
--surface: #313244;    /* Cards, inputs */
--overlay: #6c7086;    /* Borders, dividers */
--subtext: #a6adc8;    /* Secondary text */
```

### Status Colors (Both Modes)
```css
--status-processing: #f9e2af;  /* Yellow/Amber */
--status-completed: #a6e3a1;   /* Green */
--status-failed: #f38ba8;      /* Red */
```

### Primary Action (Teal)
```css
/* Light mode */
--primary: #179299;
--primary-hover: #147f85;

/* Dark mode */
--primary: #94e2d5;
--primary-hover: #7fd4c6;
```

### Text on Primary Button
- Light mode: White (`#ffffff`)
- Dark mode: Base (`#1e1e2e`)

## Typography

### Font Family
Inter (via Google Fonts or self-hosted)

```css
font-family: 'Inter', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Oxygen, Ubuntu, sans-serif;
```

### Font Sizes & Weights
- **Page titles**: 24px, semi-bold (600)
- **Card titles**: 18px, semi-bold (600)
- **Body text**: 16px, regular (400)
- **Labels/captions**: 14px, medium (500)
- **Small text**: 12px, regular (400)

### Line Height
- Headers: 1.25
- Body text: 1.5

## Components

### Cards
- **Style**: Flat (same background as page)
- **Border**: 1px solid overlay color
- **Border radius**: 8px
- **Padding**: 16-24px
- **No shadow**

### Buttons

#### Primary Button
```css
background: var(--primary);
color: white; /* or base in dark mode */
padding: 8px 24px;
border-radius: 8px;
font-weight: 500;
```

#### Text/Link Button
```css
color: var(--text);
background: transparent;
text-decoration: underline on hover;
```

### Form Inputs
```css
background: var(--base);
border: 1px solid var(--overlay);
border-radius: 6px;
padding: 8px 12px;
font-size: 16px;
```

### File Upload (Styled)
```
┌───────────────────────────────────┐
│                                   │
│     Click to upload .md file      │
│     or drag and drop              │
│                                   │
└───────────────────────────────────┘
```
- Dashed border
- Center-aligned text
- Changes appearance on file selection to show filename

## Page Layouts

### Episodes List
```
Episodes                              [+ New Episode]
RSS Feed: https://...

┌─────────────────────────────────────────────────────┐
│ ● Processing                                        │
│ Episode Title                                       │
│ by Author Name                         Nov 16, 2025 │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│ ✓ Completed                                         │
│ Episode Title                                       │
│ by Author Name                         Nov 15, 2025 │
└─────────────────────────────────────────────────────┘
```
- Single column layout
- Status indicator top-left (with pulsing animation for Processing)
- Title prominent
- Author and date secondary
- Cards are full-width within content container

### Empty State
```
┌─────────────────────────────┐
│                             │
│   Get started:              │
│   1. Create an episode      │
│   2. Upload your markdown   │
│   3. We generate the audio  │
│                             │
│   [+ Create Episode]        │
│                             │
└─────────────────────────────┘
```
- Centered on page
- Instructional 3-step guide
- Single prominent CTA
- Lots of whitespace

### Episode Creation Form
- Single-page form (no wizard)
- Form wrapped in card with padding
- Fields: Title, Author, Description, Markdown Content (file upload)
- Clear labels above inputs
- Inline validation errors (red text below field)
- Primary submit button, text link for cancel
- Styled drag-and-drop file upload area

### Sign In Page
```
┌─────────────────────────────┐
│                             │
│   Sign in                   │
│                             │
│   Email                     │
│   ┌───────────────────┐     │
│   │                   │     │
│   └───────────────────┘     │
│                             │
│   We'll find your account   │
│   or create a new one       │
│                             │
│   [Send Magic Link]         │
│                             │
└─────────────────────────────┘
```
- Centered card
- Single email field
- Clear messaging: account lookup or creation
- No logout in header (user not authenticated)

## Real-Time Updates

### Technology
- Turbo Streams (server-pushed updates)
- No polling, no Stimulus needed for status updates

### Status Indicator Behavior
- **Processing**: Yellow badge with pulsing/breathing animation
- **Completed**: Green badge with checkmark
- **Failed**: Red badge with X

When status changes via Turbo Stream:
- Card updates without page reload
- Optional brief highlight animation on status change

## Dark/Light Mode

### Implementation
- Support both modes from the start
- Toggle mechanism (user preference or system preference)
- CSS custom properties for all colors
- Apply theme class to `<html>` or `<body>` element

### Considerations
- All colors defined for both modes
- Sufficient contrast ratios maintained
- Status colors work in both modes
- Test all components in both modes

## Responsive Breakpoints

- **Mobile**: < 640px
- **Tablet**: 640px - 1024px
- **Desktop**: > 1024px

Content container adjusts padding, but single-column layout means minimal changes needed.

## Accessibility

- High contrast text (Catppuccin designed for readability)
- Focus indicators on interactive elements
- Proper heading hierarchy
- Form labels associated with inputs
- Status conveyed by color AND icon/text
