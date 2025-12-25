# Demo Animation Improvements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add play button overlay to demo animation and normalize frame heights so visitors understand this is a demo, not a live interface.

**Architecture:** Modify Stimulus controller to wait for user click before starting animation. Add overlay markup to hero_demo partial. Adjust browser frame min-height to match phone frame.

**Tech Stack:** Stimulus.js, ERB templates, Tailwind CSS

---

## Task 1: Normalize Browser Frame Height

**Files:**
- Modify: `hub/app/views/shared/_demo_browser_frame.html.erb:17`

**Step 1: Add min-height to browser frame content area**

The phone frame content area has `min-height: 200px`. The phone frame also has notch (~24px) and home indicator (~20px), making total height ~244px. The browser frame has a title bar (~36px). To match heights, browser content needs `min-height: 208px` (244 - 36 = 208).

In `hub/app/views/shared/_demo_browser_frame.html.erb`, change line 17 from:

```erb
  <div class="p-4 bg-[var(--color-base)]">
```

to:

```erb
  <div class="p-4 bg-[var(--color-base)]" style="min-height: 208px;">
```

**Step 2: Verify in browser**

Run: `bin/rails server` (if not running)

Open: `http://localhost:3000`

Expected: Browser frames should now match phone frame height. Animation should still auto-play (we'll change that next).

**Step 3: Commit**

```bash
git add hub/app/views/shared/_demo_browser_frame.html.erb
git commit -m "fix: normalize demo browser frame height to match phone frame"
```

---

## Task 2: Add Overlay Target to Stimulus Controller

**Files:**
- Modify: `hub/app/javascript/controllers/demo_animation_controller.js:4`

**Step 1: Add overlay to static targets**

In `hub/app/javascript/controllers/demo_animation_controller.js`, change line 4 from:

```javascript
  static targets = ["frame", "replay"]
```

to:

```javascript
  static targets = ["frame", "replay", "overlay"]
```

**Step 2: Verify no errors**

Run: `bin/rails server` (if not running)

Open: `http://localhost:3000`, open browser console

Expected: No JavaScript errors. Animation still auto-plays (overlay markup not added yet).

**Step 3: Commit**

```bash
git add hub/app/javascript/controllers/demo_animation_controller.js
git commit -m "feat: add overlay target to demo animation controller"
```

---

## Task 3: Add Play Action to Controller

**Files:**
- Modify: `hub/app/javascript/controllers/demo_animation_controller.js:19-25` and add new method

**Step 1: Modify connect() to not auto-start**

In `hub/app/javascript/controllers/demo_animation_controller.js`, change the `connect()` method (lines 19-25) from:

```javascript
  connect() {
    if (this.prefersReducedMotion) {
      this.showStaticFallback()
      return
    }
    this.startAnimation()
  }
```

to:

```javascript
  connect() {
    if (this.prefersReducedMotion) {
      this.showStaticFallback()
      return
    }
    // Don't auto-start - wait for user to click play
  }
```

**Step 2: Add play() method after connect()**

Add this new method after `connect()` (around line 26):

```javascript
  play() {
    if (this.hasOverlayTarget) {
      this.overlayTarget.classList.add("hidden")
    }
    this.startAnimation()
  }
```

**Step 3: Verify in browser**

Open: `http://localhost:3000`

Expected: Animation should NOT auto-play. First frame is visible but static. No errors in console.

**Step 4: Commit**

```bash
git add hub/app/javascript/controllers/demo_animation_controller.js
git commit -m "feat: add play action, remove auto-start from demo animation"
```

---

## Task 4: Add Overlay Markup to Hero Demo

**Files:**
- Modify: `hub/app/views/pages/_hero_demo.html.erb:9` (insert after line 9)

**Step 1: Add play button overlay inside animation container**

In `hub/app/views/pages/_hero_demo.html.erb`, after line 9 (`<div class="relative">`), insert the overlay markup:

```erb
    <%# Play button overlay - click to start demo %>
    <div
      data-demo-animation-target="overlay"
      data-action="click->demo-animation#play"
      class="absolute inset-0 z-10 flex flex-col items-center justify-center cursor-pointer"
    >
      <%# Play button circle %>
      <div class="w-14 h-14 rounded-full bg-[var(--color-primary)] flex items-center justify-center shadow-lg hover:scale-105 transition-transform">
        <svg class="w-6 h-6 text-[var(--color-primary-text)] ml-1" fill="currentColor" viewBox="0 0 24 24">
          <path d="M8 5v14l11-7z"/>
        </svg>
      </div>
      <span class="mt-3 text-sm text-[var(--color-subtext)]">See how it works</span>
    </div>
```

**Step 2: Verify in browser**

Open: `http://localhost:3000`

Expected:
- Play button overlay visible over the first frame
- Clicking play button hides overlay and starts animation
- Animation plays through all frames
- "Watch again" button appears at end

**Step 3: Commit**

```bash
git add hub/app/views/pages/_hero_demo.html.erb
git commit -m "feat: add play button overlay to demo animation"
```

---

## Task 5: Handle Reduced Motion with Overlay

**Files:**
- Modify: `hub/app/javascript/controllers/demo_animation_controller.js` (showStaticFallback method)

**Step 1: Hide overlay in reduced motion fallback**

In `hub/app/javascript/controllers/demo_animation_controller.js`, modify the `showStaticFallback()` method (around line 88) from:

```javascript
  showStaticFallback() {
    // Show only the "success" frame for reduced motion (index 3)
    this.frameTargets.forEach((frame, i) => {
      if (i === 3) {
        frame.classList.remove("hidden", "opacity-0")
        frame.classList.add("opacity-100")
      } else {
        frame.classList.add("hidden")
      }
    })
  }
```

to:

```javascript
  showStaticFallback() {
    // Hide overlay for reduced motion users
    if (this.hasOverlayTarget) {
      this.overlayTarget.classList.add("hidden")
    }
    // Show only the "success" frame for reduced motion (index 3)
    this.frameTargets.forEach((frame, i) => {
      if (i === 3) {
        frame.classList.remove("hidden", "opacity-0")
        frame.classList.add("opacity-100")
      } else {
        frame.classList.add("hidden")
      }
    })
  }
```

**Step 2: Verify reduced motion behavior**

In browser DevTools, enable "Reduce motion" in Rendering settings (or via system preferences).

Open: `http://localhost:3000`

Expected: No play button overlay visible. Success frame shown directly.

**Step 3: Commit**

```bash
git add hub/app/javascript/controllers/demo_animation_controller.js
git commit -m "fix: hide overlay for reduced motion users"
```

---

## Task 6: Final Verification

**Step 1: Full flow test**

1. Open `http://localhost:3000` in a fresh browser tab
2. Verify: Play button overlay visible, animation NOT playing
3. Click play button
4. Verify: Overlay disappears, animation starts
5. Watch full animation (typing → click → processing → success → transition → podcast)
6. Verify: "Watch again" button appears
7. Click "Watch again"
8. Verify: Animation replays from beginning

**Step 2: Test reduced motion**

1. Enable reduced motion in browser/system settings
2. Refresh page
3. Verify: No overlay, success frame shown immediately

**Step 3: Visual check**

1. Verify browser frames and phone frame have consistent height
2. No layout shift during animation

**Step 4: Final commit (if any cleanup needed)**

If all looks good, no additional commit needed.
