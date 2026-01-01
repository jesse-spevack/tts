# Signup Modal Implementation Plan

## Overview

Replace the scroll-to-signup pattern with a modal dialog that shows plan-specific content when users click pricing CTAs. Uses native `<dialog>` element with Stimulus controller.

## Tasks

### Task 1: Create signup modal Stimulus controller

**File:** `app/javascript/controllers/signup_modal_controller.js`

```javascript
import { Controller } from "@hotwired/stimulus"

const PLAN_CONTENT = {
  free: {
    heading: "Start listening free",
    subtext: "2 episodes/month, no credit card required"
  },
  premium_monthly: {
    heading: "Go Premium",
    subtext: "$9/month · Unlimited episodes · Cancel anytime"
  },
  premium_annual: {
    heading: "Go Premium",
    subtext: "$89/year · Unlimited episodes · Save 18%"
  }
}

export default class extends Controller {
  static targets = ["dialog", "heading", "subtext", "planField"]

  open(event) {
    event.preventDefault()
    const plan = event.currentTarget.dataset.plan || "free"
    this.updateContent(plan)
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }

  closeOnBackdrop(event) {
    if (event.target === this.dialogTarget) {
      this.close()
    }
  }

  updateContent(plan) {
    const content = PLAN_CONTENT[plan] || PLAN_CONTENT.free
    this.headingTarget.textContent = content.heading
    this.subtextTarget.textContent = content.subtext
    this.planFieldTarget.value = plan === "free" ? "" : plan
  }
}
```

**Verification:** Controller file exists and exports default class.

---

### Task 2: Create signup modal partial

**File:** `app/views/shared/_signup_modal.html.erb`

```erb
<div data-controller="signup-modal">
  <dialog
    data-signup-modal-target="dialog"
    data-action="click->signup-modal#closeOnBackdrop"
    class="fixed inset-0 z-50 m-auto max-w-md rounded-xl bg-[var(--color-base)] p-6 shadow-xl backdrop:bg-black/50 backdrop:backdrop-blur-sm"
  >
    <div class="text-center">
      <!-- Envelope Icon -->
      <div class="mx-auto flex size-12 items-center justify-center rounded-full bg-[var(--color-primary)]/10">
        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="size-6 text-[var(--color-primary)]">
          <path stroke-linecap="round" stroke-linejoin="round" d="M21.75 6.75v10.5a2.25 2.25 0 0 1-2.25 2.25h-15a2.25 2.25 0 0 1-2.25-2.25V6.75m19.5 0A2.25 2.25 0 0 0 19.5 4.5h-15a2.25 2.25 0 0 0-2.25 2.25m19.5 0v.243a2.25 2.25 0 0 1-1.07 1.916l-7.5 4.615a2.25 2.25 0 0 1-2.36 0L3.32 8.91a2.25 2.25 0 0 1-1.07-1.916V6.75" />
        </svg>
      </div>

      <!-- Heading -->
      <h3 data-signup-modal-target="heading" class="mt-4 text-xl font-semibold text-[var(--color-text)]">
        Start listening free
      </h3>

      <!-- Subtext -->
      <p data-signup-modal-target="subtext" class="mt-2 text-sm text-[var(--color-subtext)]">
        2 episodes/month, no credit card required
      </p>
    </div>

    <!-- Form -->
    <%= form_with url: session_path, class: "mt-6" do |form| %>
      <%= form.hidden_field :plan, value: "", data: { signup_modal_target: "planField" } %>

      <div class="space-y-4">
        <%= form.email_field :email_address,
            required: true,
            autocomplete: "email",
            placeholder: "Enter your email",
            class: "w-full rounded-lg bg-[var(--color-surface0)] px-4 py-3 text-base outline-none ring-1 ring-[var(--color-overlay0)] placeholder:text-[var(--color-subtext)] focus:ring-2 focus:ring-[var(--color-primary)]" %>

        <%= form.submit "Send me a link",
            class: "w-full rounded-lg bg-[var(--color-primary)] px-4 py-3 text-sm font-semibold text-[var(--color-primary-text)] shadow-sm hover:bg-[var(--color-primary-hover)] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--color-primary)] cursor-pointer" %>
      </div>
    <% end %>

    <p class="mt-4 text-center text-xs text-[var(--color-subtext)]">
      By signing up, you agree to our
      <%= link_to "Terms", terms_path, class: "underline hover:text-[var(--color-primary)]" %>
      and <%= link_to "Privacy Policy", privacy_path, class: "underline hover:text-[var(--color-primary)]" %>.
    </p>
  </dialog>
</div>
```

**Verification:** Partial renders without errors.

---

### Task 3: Add modal to application layout

**File:** `app/views/layouts/application.html.erb`

Add before the closing `</body>` tag:

```erb
<%= render "shared/signup_modal" %>
```

**Verification:** Modal dialog is present in page HTML.

---

### Task 4: Update pricing card buttons to open modal

**File:** `app/views/pages/home.html.erb`

Replace the Free card's "Create my feed" link (currently `href="#signup"`):

```erb
<button
  type="button"
  data-action="click->signup-modal#open"
  data-plan="free"
  class="mt-6 block w-full rounded-lg px-4 py-2.5 text-center text-sm font-semibold text-[var(--color-primary)] ring-1 ring-[var(--color-primary)] hover:bg-[var(--color-surface0)]"
>
  Create my feed
</button>
```

Replace the Premium card's "Get Premium" link (currently `href="#signup?plan=premium_monthly"`):

```erb
<button
  type="button"
  data-action="click->signup-modal#open"
  data-plan="premium_monthly"
  data-pricing-toggle-target="premiumLink"
  class="mt-6 block w-full rounded-lg bg-[var(--color-primary)] px-4 py-2.5 text-center text-sm font-semibold text-[var(--color-primary-text)] shadow-sm hover:bg-[var(--color-primary-hover)]"
>
  Get Premium
</button>
```

**Verification:** Clicking pricing buttons opens modal with correct plan content.

---

### Task 5: Update pricing toggle controller

**File:** `app/javascript/controllers/pricing_toggle_controller.js`

Change from updating `href` to updating `data-plan` attribute:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["monthlyPrice", "annualPrice", "premiumLink"]

  connect() {
    this.update()
  }

  update() {
    const selected = this.element.querySelector('input[name="frequency"]:checked')?.value || "monthly"
    const isAnnual = selected === "annual"

    // Toggle price visibility
    this.monthlyPriceTarget.classList.toggle("hidden", isAnnual)
    this.annualPriceTarget.classList.toggle("hidden", !isAnnual)

    // Update premium button's plan
    const plan = isAnnual ? "premium_annual" : "premium_monthly"
    this.premiumLinkTarget.dataset.plan = plan
  }
}
```

**Verification:** Toggling monthly/annual updates the button's data-plan attribute.

---

### Task 6: Update hero CTA to open modal

**File:** `app/views/pages/home.html.erb`

Replace the "Start listening free" link in the hero section:

```erb
<button
  type="button"
  data-action="click->signup-modal#open"
  data-plan="free"
  class="rounded-lg bg-[var(--color-primary)] px-4 py-2.5 text-sm font-semibold text-[var(--color-primary-text)] shadow-sm hover:bg-[var(--color-primary-hover)] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--color-primary)]"
>
  Start listening free
</button>
```

**Verification:** Hero CTA opens modal.

---

### Task 7: Simplify the #signup section

**File:** `app/views/pages/home.html.erb`

Replace the entire `<!-- Signup Section -->` with:

```erb
<!-- Signup Section -->
<div id="signup" class="bg-[var(--color-base)] py-16 sm:py-24 lg:py-32">
  <div class="mx-auto max-w-7xl px-6 text-center lg:px-8">
    <h2 class="text-3xl font-semibold tracking-tight sm:text-4xl">
      Ready to start listening?
    </h2>
    <p class="mt-4 text-lg text-[var(--color-subtext)]">
      No credit card required. Set up in 30 seconds.
    </p>
    <button
      type="button"
      data-action="click->signup-modal#open"
      data-plan="free"
      class="mt-8 rounded-lg bg-[var(--color-primary)] px-6 py-3 text-base font-semibold text-[var(--color-primary-text)] shadow-sm hover:bg-[var(--color-primary-hover)]"
    >
      Create my free feed
    </button>
  </div>
</div>
```

**Verification:** Simplified signup section renders and button opens modal.

---

### Task 8: Delete signup form controller

**File:** `app/javascript/controllers/signup_form_controller.js`

Delete this file - no longer needed.

**Verification:** File is deleted, no JS errors in console.

---

### Task 9: Add dialog styling to CSS

**File:** `app/assets/tailwind/application.css`

Add after the `:root` and `.dark` blocks (inside `@layer base`):

```css
dialog::backdrop {
  background: rgba(0, 0, 0, 0.5);
  backdrop-filter: blur(4px);
}

dialog[open] {
  animation: fade-in 150ms ease-out;
}

@keyframes fade-in {
  from {
    opacity: 0;
    transform: scale(0.95);
  }
  to {
    opacity: 1;
    transform: scale(1);
  }
}
```

**Verification:** Modal has smooth fade-in animation and blurred backdrop.

---

### Task 10: Run tests and verify

Run full test suite:

```bash
bin/rails test
```

Manual verification checklist:
- [ ] Hero "Start listening free" opens modal with free content
- [ ] Pricing "Create my feed" opens modal with free content
- [ ] Pricing "Get Premium" opens modal with monthly content
- [ ] Toggle to annual, "Get Premium" opens modal with annual content
- [ ] Bottom CTA opens modal with free content
- [ ] Escape key closes modal
- [ ] Clicking backdrop closes modal
- [ ] Form submits and redirects with flash notice
- [ ] Plan param is correctly passed through to magic link

**Verification:** All tests pass, manual checklist complete.

---

## Files Changed

| Action | File |
|--------|------|
| Create | `app/javascript/controllers/signup_modal_controller.js` |
| Create | `app/views/shared/_signup_modal.html.erb` |
| Modify | `app/views/layouts/application.html.erb` |
| Modify | `app/views/pages/home.html.erb` |
| Modify | `app/javascript/controllers/pricing_toggle_controller.js` |
| Modify | `app/assets/tailwind/application.css` |
| Delete | `app/javascript/controllers/signup_form_controller.js` |
