# Demo Animation Improvements Design

## Problem

The current hero demo animation auto-plays and looks like a real interface, causing visitors to think the website is actively doing something on their behalf rather than showing a demonstration of the product.

Additionally, the browser frames (frames 1-5) are shorter than the phone frame (frame 6), creating a visual jump during the animation.

## Solution

### 1. Play Button Overlay

Add a play button overlay to the demo that:
- Shows the first frame (URL input) as a static preview
- Displays a centered, semi-transparent play button
- Includes subtle text: "See how it works"
- On click: hides overlay and starts the animation
- After animation completes: shows existing "Watch again" button

**Why this works:** The play button is a universal signal that frames the experience as "watching a demo" rather than "interacting with a live form." The mental shift happens before the animation starts.

### 2. Normalize Frame Heights

Make browser frames match the phone frame height:
- Add `min-height` to browser frame content area
- Target height: match phone frame's total height (~240px including notch/home indicator)
- Browser content will have additional breathing room, which improves visual balance

**Why this works:** Consistent height eliminates the visual "jump" when transitioning from browser to phone frames, creating a more polished animation.

## Implementation

### Files to Modify

1. **`hub/app/views/pages/_hero_demo.html.erb`**
   - Add play button overlay markup before the animation container
   - Overlay contains: semi-transparent backdrop, play icon, "See how it works" text

2. **`hub/app/javascript/controllers/demo_animation_controller.js`**
   - Add `overlay` target
   - Modify `connect()` to NOT auto-start animation
   - Add `play()` action that hides overlay and calls `startAnimation()`

3. **`hub/app/views/shared/_demo_browser_frame.html.erb`**
   - Add `min-height` style to content area to match phone frame height

4. **`hub/app/assets/stylesheets/demo_animation.css`**
   - Add styles for play button overlay (positioning, hover states)

### Markup Structure

```erb
<div data-controller="demo-animation" class="w-full max-w-sm mx-auto">
  <%# Play button overlay - visible initially %>
  <div data-demo-animation-target="overlay"
       data-action="click->demo-animation#play"
       class="absolute inset-0 z-10 flex flex-col items-center justify-center cursor-pointer bg-[var(--color-base)]/50">
    <div class="w-16 h-16 rounded-full bg-[var(--color-primary)] flex items-center justify-center">
      <svg><!-- play icon --></svg>
    </div>
    <span class="mt-2 text-sm text-[var(--color-subtext)]">See how it works</span>
  </div>

  <%# Existing animation frames... %>
</div>
```

## Out of Scope

- Copy changes ("Why I built this" → "Why Very Normal TTS") - separate task
