# Flash Message Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Redesign flash messages with modern styling including icons, dismiss buttons, and color-coded variants while maintaining CSS variable consistency.

**Architecture:** Create reusable icon partials in the shared/icons directory, update the flash partial to use a three-column flex layout (icon, message, dismiss button), and add a dismissable Stimulus controller for manual dismissal that works alongside the existing auto-dismiss behavior.

**Tech Stack:** Rails ERB partials, Stimulus.js controllers, Tailwind CSS with CSS variables

---

## Task 1: Create Check Circle Icon Partial

**Files:**
- Create: `hub/app/views/shared/icons/_check_circle.html.erb`

**Step 1: Create the check circle icon file**

Create `hub/app/views/shared/icons/_check_circle.html.erb` with this exact content:

```erb
<svg viewBox="0 0 20 20" fill="currentColor" data-slot="icon" aria-hidden="true" class="size-5">
  <path d="M10 18a8 8 0 1 0 0-16 8 8 0 0 0 0 16Zm3.857-9.809a.75.75 0 0 0-1.214-.882l-3.483 4.79-1.88-1.88a.75.75 0 1 0-1.06 1.061l2.5 2.5a.75.75 0 0 0 1.137-.089l4-5.5Z" clip-rule="evenodd" fill-rule="evenodd" />
</svg>
```

**Why:** This icon represents success/completion and will be used for notice flash messages. The `currentColor` fill means it inherits the text color from its parent, allowing us to control the color with CSS variables.

**Step 2: Commit the icon**

```bash
git add hub/app/views/shared/icons/_check_circle.html.erb
git commit -m "feat: add check circle icon for success flash messages"
```

---

## Task 2: Create X Circle Icon Partial

**Files:**
- Create: `hub/app/views/shared/icons/_x_circle.html.erb`

**Step 1: Create the x circle icon file**

Create `hub/app/views/shared/icons/_x_circle.html.erb` with this exact content:

```erb
<svg viewBox="0 0 20 20" fill="currentColor" data-slot="icon" aria-hidden="true" class="size-5">
  <path d="M10 18a8 8 0 1 0 0-16 8 8 0 0 0 0 16ZM8.28 7.22a.75.75 0 0 0-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 1 0 1.06 1.06L10 11.06l1.72 1.72a.75.75 0 1 0 1.06-1.06L11.06 10l1.72-1.72a.75.75 0 0 0-1.06-1.06L10 8.94 8.28 7.22Z" clip-rule="evenodd" fill-rule="evenodd" />
</svg>
```

**Why:** This icon represents errors/alerts and will be used for alert flash messages. Uses the same `currentColor` pattern for consistent color inheritance.

**Step 2: Commit the icon**

```bash
git add hub/app/views/shared/icons/_x_circle.html.erb
git commit -m "feat: add x circle icon for error flash messages"
```

---

## Task 3: Create X Mark Icon Partial

**Files:**
- Create: `hub/app/views/shared/icons/_x_mark.html.erb`

**Step 1: Create the x mark icon file**

Create `hub/app/views/shared/icons/_x_mark.html.erb` with this exact content:

```erb
<svg viewBox="0 0 20 20" fill="currentColor" data-slot="icon" aria-hidden="true" class="size-5">
  <path d="M6.28 5.22a.75.75 0 0 0-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 1 0 1.06 1.06L10 11.06l3.72 3.72a.75.75 0 1 0 1.06-1.06L11.06 10l3.72-3.72a.75.75 0 0 0-1.06-1.06L10 8.94 6.28 5.22Z" />
</svg>
```

**Why:** This is the dismiss/close icon that will appear in the dismiss button on all flash messages. It's a simple X mark without the circle background.

**Step 2: Commit the icon**

```bash
git add hub/app/views/shared/icons/_x_mark.html.erb
git commit -m "feat: add x mark icon for flash dismiss buttons"
```

---

## Task 4: Create Dismissable Stimulus Controller

**Files:**
- Create: `hub/app/javascript/controllers/dismissable_controller.js`

**Step 1: Create the dismissable controller**

Create `hub/app/javascript/controllers/dismissable_controller.js` with this exact content:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  dismiss() {
    this.element.classList.add("opacity-0")
    setTimeout(() => {
      this.element.remove()
    }, 300)
  }
}
```

**Why:** This controller handles manual dismissal when the user clicks the X button. It uses the same fade-out pattern as the auto-dismiss controller (opacity-0 class + 300ms timeout) for visual consistency. The controller is simple and focused on a single responsibility.

**Step 2: Test the controller manually**

Open the browser console and verify Stimulus registered the controller:

```javascript
// In browser console:
window.Stimulus.controllers
// Should include "dismissable"
```

**Step 3: Commit the controller**

```bash
git add hub/app/javascript/controllers/dismissable_controller.js
git commit -m "feat: add dismissable Stimulus controller for flash messages"
```

---

## Task 5: Update Flash Partial with New Design

**Files:**
- Modify: `hub/app/views/shared/_flash.html.erb:1-11`

**Step 1: Replace the entire flash partial**

Replace the entire contents of `hub/app/views/shared/_flash.html.erb` with:

```erb
<% if notice.present? %>
  <div data-controller="auto-dismiss dismissable" class="rounded-md bg-[var(--color-green)]/10 p-4 outline outline-[var(--color-green)]/20 mb-6 transition-opacity duration-300">
    <div class="flex">
      <div class="shrink-0 text-[var(--color-green)]">
        <%= render "shared/icons/check_circle" %>
      </div>
      <div class="ml-3">
        <p class="text-sm font-medium text-[var(--color-green)]"><%= notice %></p>
      </div>
      <div class="ml-auto pl-3">
        <div class="-mx-1.5 -my-1.5">
          <button type="button" data-action="click->dismissable#dismiss" class="inline-flex rounded-md p-1.5 text-[var(--color-green)] hover:bg-[var(--color-green)]/10 focus-visible:ring-2 focus-visible:ring-[var(--color-green)] focus-visible:ring-offset-1 focus-visible:outline-hidden">
            <span class="sr-only">Dismiss</span>
            <%= render "shared/icons/x_mark" %>
          </button>
        </div>
      </div>
    </div>
  </div>
<% end %>

<% if alert.present? %>
  <div data-controller="auto-dismiss dismissable" class="rounded-md bg-[var(--color-red)]/10 p-4 outline outline-[var(--color-red)]/20 mb-6 transition-opacity duration-300">
    <div class="flex">
      <div class="shrink-0 text-[var(--color-red)]">
        <%= render "shared/icons/x_circle" %>
      </div>
      <div class="ml-3">
        <p class="text-sm font-medium text-[var(--color-red)]"><%= alert %></p>
      </div>
      <div class="ml-auto pl-3">
        <div class="-mx-1.5 -my-1.5">
          <button type="button" data-action="click->dismissable#dismiss" class="inline-flex rounded-md p-1.5 text-[var(--color-red)] hover:bg-[var(--color-red)]/10 focus-visible:ring-2 focus-visible:ring-[var(--color-red)] focus-visible:ring-offset-1 focus-visible:outline-hidden">
            <span class="sr-only">Dismiss</span>
            <%= render "shared/icons/x_mark" %>
          </button>
        </div>
      </div>
    </div>
  </div>
<% end %>
```

**Why:**
- Changed from `border` to `outline` for the subtle ring effect matching the design spec
- Three-column flex layout: icon (shrink-0), message (ml-3), dismiss button (ml-auto)
- Both controllers attached: `data-controller="auto-dismiss dismissable"`
- Icons rendered as partials with color controlled by parent wrapper
- Dismiss button has `data-action="click->dismissable#dismiss"` to trigger the controller
- `sr-only` text provides accessibility for screen readers
- Hover and focus-visible states for better UX

**Step 2: Commit the updated flash partial**

```bash
git add hub/app/views/shared/_flash.html.erb
git commit -m "feat: redesign flash messages with icons and dismiss buttons"
```

---

## Task 6: Test Notice Flash Message

**Files:**
- Reference: `hub/app/controllers/episodes_controller.rb` (or any controller that sets flash[:notice])

**Step 1: Start the Rails server**

```bash
rails server
```

**Step 2: Trigger a notice flash**

Navigate to a flow that triggers a notice flash (e.g., successful login, or manually test by temporarily adding to a controller):

```ruby
# Temporary test code (add to any controller action you can easily access):
flash[:notice] = "This is a test notice message"
redirect_to root_path
```

**Step 3: Verify the visual appearance**

Check in browser:
- [ ] Green background with subtle green outline ring
- [ ] Check circle icon appears on the left in green
- [ ] Message text is green, small (text-sm), and medium weight
- [ ] X button appears on the right
- [ ] Hover over X button shows subtle green background highlight

**Step 4: Verify manual dismiss works**

- [ ] Click the X button
- [ ] Flash message fades out over 300ms
- [ ] Flash message is removed from DOM after fade

**Step 5: Verify auto-dismiss works**

- [ ] Refresh page to show flash again
- [ ] Wait 3.5 seconds without clicking
- [ ] Flash message auto-dismisses with fade-out animation

**Step 6: Verify accessibility**

- [ ] Tab to the dismiss button using keyboard
- [ ] Focus-visible ring appears around the button
- [ ] Press Enter or Space to dismiss
- [ ] Use screen reader to verify "Dismiss" is announced

**Step 7: Verify responsive behavior**

- [ ] Resize browser to mobile width (375px)
- [ ] Verify icon, text, and button align properly
- [ ] Test with long message text (50+ characters)
- [ ] Verify text wraps without breaking layout

**Step 8: Remove temporary test code if added**

Remove any temporary flash test code added to controllers.

---

## Task 7: Test Alert Flash Message

**Files:**
- Reference: `hub/app/controllers/episodes_controller.rb:34`

**Step 1: Ensure Rails server is running**

```bash
rails server
```

**Step 2: Trigger an alert flash**

The easiest way is to trigger the tier restriction at `hub/app/controllers/episodes_controller.rb:34`. Alternatively, manually test:

```ruby
# Temporary test code (add to any controller action):
flash[:alert] = "This is a test alert message"
redirect_to root_path
```

**Step 3: Verify the visual appearance**

Check in browser:
- [ ] Red background with subtle red outline ring
- [ ] X circle (error) icon appears on the left in red
- [ ] Message text is red, small (text-sm), and medium weight
- [ ] X button appears on the right
- [ ] Hover over X button shows subtle red background highlight

**Step 4: Verify manual dismiss works**

- [ ] Click the X button
- [ ] Flash message fades out over 300ms
- [ ] Flash message is removed from DOM after fade

**Step 5: Verify auto-dismiss works**

- [ ] Refresh page to show flash again
- [ ] Wait 3.5 seconds without clicking
- [ ] Flash message auto-dismisses with fade-out animation

**Step 6: Verify both flash types can appear together**

Test displaying both notice and alert simultaneously:

```ruby
# Temporary test code:
flash[:notice] = "Success message"
flash[:alert] = "Error message"
redirect_to root_path
```

Verify:
- [ ] Both messages display stacked vertically with mb-6 spacing
- [ ] Each has correct icon and color
- [ ] Each can be dismissed independently
- [ ] Both auto-dismiss independently

**Step 7: Remove temporary test code if added**

Remove any temporary flash test code added to controllers.

---

## Task 8: Cross-Browser Testing

**Step 1: Test in Chrome**

- [ ] Notice flash displays correctly
- [ ] Alert flash displays correctly
- [ ] Manual dismiss works
- [ ] Auto-dismiss works
- [ ] Hover effects work
- [ ] Focus-visible rings work

**Step 2: Test in Firefox**

- [ ] Notice flash displays correctly
- [ ] Alert flash displays correctly
- [ ] Manual dismiss works
- [ ] Auto-dismiss works
- [ ] Hover effects work
- [ ] Focus-visible rings work

**Step 3: Test in Safari (if on macOS)**

- [ ] Notice flash displays correctly
- [ ] Alert flash displays correctly
- [ ] Manual dismiss works
- [ ] Auto-dismiss works
- [ ] Hover effects work
- [ ] Focus-visible rings work

**Step 4: Test on mobile device or emulator**

- [ ] Touch interaction works for dismiss button
- [ ] Layout is responsive
- [ ] Text is readable at mobile size
- [ ] No horizontal scrolling

---

## Task 9: Final Verification and Commit

**Step 1: Run full test suite**

```bash
rake test
```

Expected: All tests pass (no regressions from flash message changes)

**Step 2: Visual regression check**

Manually verify all pages that display flash messages still work:
- Login/authentication flows
- Episodes submission (tier restriction alert)
- Any other flows identified in codebase that use flash

**Step 3: Verify no console errors**

- [ ] Open browser console
- [ ] Navigate through various flows
- [ ] Confirm no JavaScript errors related to flash messages or controllers

**Step 4: Final commit if any fixes were needed**

```bash
git add .
git commit -m "test: verify flash message redesign across all flows"
```

**Step 5: Review git log**

```bash
git log --oneline -10
```

Should show clean commit history:
- feat: add check circle icon for success flash messages
- feat: add x circle icon for error flash messages
- feat: add x mark icon for flash dismiss buttons
- feat: add dismissable Stimulus controller for flash messages
- feat: redesign flash messages with icons and dismiss buttons
- (possibly) test: verify flash message redesign across all flows

---

## Notes

**DRY:** Icon partials are reusable across the application if needed elsewhere. The dismissable controller can be used on other dismissable elements.

**YAGNI:** Only implemented notice and alert flash types since those are the only ones currently used in the codebase. Warning and info variants can be added when needed.

**Testing:** Manual testing is sufficient for this UI change. No unit tests needed for static partials. The Stimulus controller is simple enough that integration testing through browser verification is appropriate.

**Accessibility:** Screen reader support via sr-only labels, keyboard navigation support with focus-visible states, and semantic HTML structure.

**Performance:** No performance impact. Three small SVG icon files add minimal bytes. Stimulus controller is lightweight.

**Backwards Compatibility:** This is a breaking visual change but maintains functional compatibility. All existing `flash[:notice]` and `flash[:alert]` calls continue to work.
