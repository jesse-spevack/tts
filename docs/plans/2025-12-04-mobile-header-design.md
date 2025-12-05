# Mobile-Responsive Header Design

## Problem

The header looks bad on mobile - content overflows and wraps awkwardly when all elements (logo, theme toggle, Settings, email, Logout) try to fit in one row.

## Solution

Responsive header with hamburger menu on mobile.

## Desktop Behavior (≥640px)

No change. Header displays:
- Logo "Very Normal TTS" on the left
- Right side: theme toggle, Settings link, email, Logout button

## Mobile Behavior (<640px)

Header displays:
- Logo "Very Normal TTS" on the left
- Hamburger icon (3 horizontal lines) on the right

When hamburger is tapped:
- Icon changes to X (close icon)
- Disclosure panel slides down below header containing:
  - User's email address (label, not link)
  - Theme toggle with "Dark mode" / "Light mode" label
  - Settings link
  - Logout button

Tapping X or any menu item closes the panel.

## Implementation

### Files to modify

- `app/views/shared/_header.html.erb` - add responsive classes and mobile menu markup
- `app/javascript/controllers/mobile_menu_controller.js` - new Stimulus controller

### Header structure

```erb
<header>
  <div class="...">
    <!-- Logo (always visible) -->

    <!-- Desktop nav (hidden on mobile via hidden sm:flex) -->

    <!-- Hamburger button (visible on mobile via sm:hidden) -->
  </div>

  <!-- Mobile menu panel (hidden by default, toggled by Stimulus) -->
</header>
```

### Stimulus controller

- `toggle()` action on hamburger button
- Toggles `hidden` class on mobile menu panel
- Toggles hamburger/X icon visibility
- Closes menu when clicking a link

### Styling

- Uses existing CSS variables (`--color-base`, `--color-text`, `--color-overlay0`, etc.)
- Mobile menu has border-top separator
- Menu items full-width, stacked vertically
- Touch-friendly padding on menu items
