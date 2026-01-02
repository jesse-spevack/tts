# View Partials Extraction Proposal

This document outlines opportunities to extract reusable partials from the current view templates, prioritized by impact and value.

## Priority 1: High Impact - Critical Duplication

### 1.1 Clipboard Copy Button Component
**Files affected:** `episodes/index.html.erb:9-17`, `episodes/_episode_card.html.erb:9-17`, `episodes/show.html.erb:39-47`

**Current duplication:** 3 instances with identical structure

**Proposed partial:** `app/views/shared/_clipboard_button.html.erb`

**Benefits:**
- Eliminates 30+ lines of duplicated markup
- Centralizes clipboard UX behavior
- Makes it trivial to add clipboard functionality anywhere
- Single source of truth for icon toggle logic

**Usage:**
```erb
<%= render "shared/clipboard_button",
  content: episode_url(episode.prefix_id),
  title: "Copy share link",
  icon: "share" # or "copy"
%>
```

---

### 1.2 Back Navigation Link
**Files affected:** `settings/show.html.erb:2-4`, `billing/show.html.erb:2-4`, `upgrades/show.html.erb:2-4`

**Current duplication:** 3 identical instances

**Proposed partial:** `app/views/shared/_back_link.html.erb`

**Benefits:**
- DRY up navigation pattern used across all settings-like pages
- Consistent back navigation UX
- Easy to update styling globally

**Usage:**
```erb
<%= render "shared/back_link",
  path: episodes_path,
  text: "Back to Episodes"
%>
```

---

### 1.3 Feature List Item with Checkmark
**Files affected:** `pages/home.html.erb` (lines 182-211 - repeated 5x), `shared/_premium_card.html.erb` (lines 47-59 - repeated 3x)

**Current duplication:** 8 instances with identical SVG checkmark pattern

**Proposed partial:** `app/views/shared/_feature_list_item.html.erb`

**Benefits:**
- Removes ~80 lines of repeated SVG markup
- Makes feature lists scannable and maintainable
- Consistent checkmark styling across pricing and features
- Easy to swap icon if design changes

**Usage:**
```erb
<ul class="space-y-3 text-sm text-[var(--color-subtext)]">
  <%= render "shared/feature_list_item", text: "Private podcast feed" %>
  <%= render "shared/feature_list_item", text: "Unlimited episodes" %>
</ul>
```

---

### 1.4 Audio Player Component
**Files affected:** `episodes/show.html.erb:30-34`, `sessions/new.html.erb:14-23` (2x), `pages/how_it_sounds.html.erb:7-10`

**Current duplication:** 4 instances with similar structure

**Proposed partial:** `app/views/shared/_audio_player.html.erb`

**Benefits:**
- Centralizes audio player markup
- Easier to add features like playback rate, progress saving
- Consistent audio UX across the app
- Can add analytics tracking in one place

**Usage:**
```erb
<%= render "shared/audio_player",
  source: @episode.audio_url,
  label: "Premium voice",
  preload: "metadata"
%>
```

---

## Priority 2: Medium Impact - Code Organization

### 2.1 Form Submit/Cancel Button Group
**Files affected:** `episodes/new.html.erb` (lines 51-54, 73-76, 133-136)

**Current duplication:** 3 identical button groups in same file

**Proposed partial:** `app/views/shared/_form_actions.html.erb`

**Benefits:**
- DRY up common form pattern
- Consistent form button styling
- Easier responsive behavior management
- Reusable across all forms

**Usage:**
```erb
<%= render "shared/form_actions",
  submit_text: "Create Episode",
  cancel_path: episodes_path,
  submit_class: "additional-classes" # optional
%>
```

---

### 2.2 Signup CTA Button
**Files affected:** `pages/home.html.erb` (lines 15-24, 170-179, 230-238)

**Current duplication:** 3 instances with similar data attributes

**Proposed partial:** `app/views/shared/_signup_cta_button.html.erb`

**Benefits:**
- Centralizes signup modal trigger logic
- Consistent CTA appearance
- Easier A/B testing of copy
- Single place to update modal attributes

**Usage:**
```erb
<%= render "shared/signup_cta_button",
  text: "Start listening free",
  plan: "free",
  heading: "Start listening free",
  subtext: "2 episodes/month, no credit card required",
  style: :primary # or :secondary
%>
```

---

### 2.3 How It Works Step
**Files affected:** `pages/home.html.erb:47-77`, `pages/how_it_sounds.html.erb:17-28`

**Current duplication:** Two different patterns for showing steps

**Proposed partial:** `app/views/shared/_how_it_works_step.html.erb`

**Benefits:**
- Unified step display across pages
- Easier to maintain consistent messaging
- Can support both icon and numbered variants
- Cleaner step iteration

**Usage:**
```erb
<% steps = [
  { icon: "upload", title: "Add your content", description: "..." },
  { icon: "audio", title: "We turn it into audio", description: "..." }
] %>

<%= render "shared/how_it_works_steps", steps: steps, variant: :icons %>
```

---

### 2.4 Episode Action Buttons
**Files affected:** `episodes/_episode_card.html.erb:8-31`, `episodes/show.html.erb:38-60`

**Current duplication:** Similar action button patterns

**Proposed partial:** `app/views/shared/_episode_actions.html.erb`

**Benefits:**
- Consistent episode action UI
- Easier to add new actions
- Centralized permission logic
- Better icon alignment

**Usage:**
```erb
<%= render "shared/episode_actions",
  episode: episode,
  layout: :compact # or :full
%>
```

---

## Priority 3: Low-Medium Impact - Quality of Life

### 3.1 Page Header with Title
**Files affected:** `episodes/index.html.erb:4-6`, `episodes/new.html.erb:2`, `settings/show.html.erb:5`, `billing/show.html.erb:5`

**Current duplication:** Similar page header patterns

**Proposed partial:** `app/views/shared/_page_header.html.erb`

**Benefits:**
- Consistent page title styling
- Optional subtitle support
- Cleaner view templates
- Easier to add breadcrumbs later

**Usage:**
```erb
<%= render "shared/page_header",
  title: "Episodes",
  subtitle: "Manage your podcast episodes"
%>
```

---

### 3.2 Empty State Component
**Files affected:** `episodes/index.html.erb:35-45`

**Current duplication:** Only 1 instance now, but pattern is reusable

**Proposed partial:** `app/views/shared/_empty_state.html.erb`

**Benefits:**
- Reusable empty state pattern for future features
- Consistent empty state UX
- Supports custom messages and CTAs

**Usage:**
```erb
<%= render "shared/empty_state",
  title: "No episodes yet",
  instructions: ["1. Click + New Episode", "2. Upload content", "3. Listen"]
%>
```

---

### 3.3 Inline SVG Icons
**Files affected:** `pages/home.html.erb` has several inline SVGs that aren't extracted

**Current state:** Upload icon (lines 49-51) and audio waveform icon (lines 60-62) are inline

**Proposed:** Extract to `app/views/shared/icons/` directory

**Benefits:**
- Consistent with existing icon partial pattern
- Reusable across views
- Easier to update icon styling

**Files to create:**
- `app/views/shared/icons/_upload.html.erb`
- `app/views/shared/icons/_waveform.html.erb`

---

### 3.4 Subscription Status Card
**Files affected:** `billing/show.html.erb:7-47`

**Current duplication:** Multiple conditional cards with similar structure

**Proposed partial:** `app/views/billing/_subscription_card.html.erb`

**Benefits:**
- Cleaner billing view
- Easier to add new subscription states
- Consistent card styling
- Better testability

**Usage:**
```erb
<%= render "billing/subscription_card",
  status: @subscription.status,
  subscription: @subscription
%>
```

---

### 3.5 Terms & Privacy Policy Links
**Files affected:** `sessions/new.html.erb:45-48`, `episodes/show.html.erb:79-81`

**Current duplication:** 2 instances with similar structure

**Proposed partial:** `app/views/shared/_legal_links.html.erb`

**Benefits:**
- Consistent legal disclosure formatting
- Single place to update policy links
- Easier to add cookie policy later

**Usage:**
```erb
<%= render "shared/legal_links",
  prefix: "By signing up, you agree to our"
%>
```

---

### 3.6 Free Plan Pricing Card
**Files affected:** `pages/home.html.erb:159-213`

**Current state:** Premium card is extracted, but Free card is not

**Proposed partial:** `app/views/shared/_free_card.html.erb`

**Benefits:**
- Parallel structure with `_premium_card.html.erb`
- Reusable in billing/upgrade flows
- Easier to maintain pricing parity
- Better A/B testing capability

**Usage:**
```erb
<%= render "shared/free_card", mode: :landing %>
```

---

## Priority 4: Refactoring - Complexity Reduction

### 4.1 Header Navigation Items
**Files affected:** `shared/_header.html.erb:8-32` (desktop), `50-80` (mobile)

**Current duplication:** Navigation logic duplicated between desktop/mobile

**Proposed approach:** Extract navigation item logic to a helper or dedicated partial

**Benefits:**
- Single source of navigation items
- Reduces header complexity from 82 to ~50 lines
- Easier to add new nav items
- Consistent behavior between desktop/mobile

**Proposed partials:**
- `app/views/shared/_nav_items.html.erb` (renders in both contexts)

---

### 4.2 Form Tab Panel in episodes/new
**Files affected:** `episodes/new.html.erb:37-138`

**Current duplication:** Three similar form panels with different fields

**Proposed approach:** Single form partial with conditional field rendering

**Benefits:**
- Reduces view from 142 to ~80 lines
- Consistent form behavior
- Easier to add validation feedback
- Shared form styling

**Proposed partial:** `app/views/episodes/_episode_form_panel.html.erb`

---

## Implementation Recommendations

### Phase 1 (Quick Wins)
Start with Priority 1 items as they provide immediate value:
1. Back navigation link (5 min)
2. Feature list item (15 min)
3. Clipboard button (20 min)
4. Audio player (15 min)

**Total time:** ~1 hour
**Lines of code reduced:** ~200+
**Files simplified:** 8+

### Phase 2 (Form & CTA Improvements)
Priority 2 items improve code organization:
1. Form actions (10 min)
2. Signup CTA button (15 min)
3. Episode actions (20 min)
4. How it works steps (20 min)

**Total time:** ~1 hour
**Lines of code reduced:** ~150+
**Files simplified:** 5+

### Phase 3 (Polish)
Priority 3 and 4 items for long-term maintainability:
- Can be done incrementally
- Lower urgency but good for new feature development
- Reduces technical debt

---

## Expected Outcomes

### Code Quality Metrics
- **Lines of code reduction:** 400-500 lines
- **Files affected:** 15+ view files
- **New reusable partials:** 12-15
- **Duplication eliminated:** ~60%

### Maintenance Benefits
- ✅ Easier to update UI components globally
- ✅ Faster feature development with reusable components
- ✅ Better consistency across pages
- ✅ Improved testability with focused partials
- ✅ Cleaner diffs in version control
- ✅ Onboarding easier with clear component structure

### Design System Foundation
These partials create a foundation for a component library that can grow with the application.

---

## Notes

- All partials should accept keyword arguments for flexibility
- Consider using ViewComponent gem for more complex components in the future
- Add documentation comments to each partial explaining usage and parameters
- Update style guide documentation as partials are created
