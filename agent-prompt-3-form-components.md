# Agent Prompt 3: Form & CTA Components

## Objective
Extract form action buttons, signup CTA buttons, and legal links to reduce duplication in form-heavy views.

## Context
Form submit/cancel patterns are repeated 3x in episodes/new. Signup CTA buttons with modal triggers appear 3x on home page. Legal policy links appear 2x with similar markup.

## Tasks

### Task 1: Create Form Actions Partial

**Create:** `app/views/shared/_form_actions.html.erb`

**Current duplicates in:**
- `app/views/episodes/new.html.erb:51-54` (URL form)
- `app/views/episodes/new.html.erb:73-76` (Paste form)
- `app/views/episodes/new.html.erb:133-136` (File form)

**Requirements:**
- Accept parameters: `submit_text`, `cancel_path`, `submit_class` (optional)
- Flex layout with responsive stacking
- Primary button for submit, text button for cancel
- Match existing responsive classes

**Signature:**
```erb
<%# locals: (submit_text:, cancel_path:, submit_class: "") %>
```

**Implementation:**
```erb
<%# locals: (submit_text:, cancel_path:, submit_class: "") %>
<div class="flex flex-col sm:flex-row sm:items-center gap-4 pt-4">
  <%= submit_tag submit_text, class: "#{button_classes(type: :primary, full_width: false)} sm:w-auto w-full #{submit_class}" %>
  <%= link_to "Cancel", cancel_path, class: "#{button_classes(type: :text)} text-center" %>
</div>
```

**After creating the partial, update these files:**
1. `app/views/episodes/new.html.erb` - Replace lines 51-54
2. `app/views/episodes/new.html.erb` - Replace lines 73-76
3. `app/views/episodes/new.html.erb` - Replace lines 133-136

**Example usage:**
```erb
<%= render "shared/form_actions",
  submit_text: "Create Episode",
  cancel_path: episodes_path
%>
```

---

### Task 2: Create Signup CTA Button Partial

**Create:** `app/views/shared/_signup_cta_button.html.erb`

**Current duplicates in:**
- `app/views/pages/home.html.erb:15-24` (Hero section)
- `app/views/pages/home.html.erb:170-179` (Free pricing card)
- `app/views/pages/home.html.erb:230-238` (Bottom CTA)

**Requirements:**
- Accept parameters: `text`, `plan`, `heading`, `subtext`, `style` (default: "primary"), `additional_classes` (optional)
- Include data attributes for signup modal
- Support :primary and :outline styles

**Signature:**
```erb
<%# locals: (text:, plan: "free", heading: nil, subtext: nil, style: :primary, additional_classes: "") %>
```

**Implementation:**
```erb
<%# locals: (text:, plan: "free", heading: nil, subtext: nil, style: :primary, additional_classes: "") %>
<%
  heading ||= text
  button_style = case style
  when :primary
    "rounded-lg bg-[var(--color-primary)] px-4 py-2.5 text-sm font-semibold text-[var(--color-primary-text)] shadow-sm hover:bg-[var(--color-primary-hover)] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--color-primary)]"
  when :outline
    "block w-full rounded-lg px-4 py-2.5 text-center text-sm font-semibold text-[var(--color-primary)] ring-1 ring-[var(--color-primary)] hover:bg-[var(--color-surface0)]"
  when :large
    "rounded-lg bg-[var(--color-primary)] px-6 py-3 text-base font-semibold text-[var(--color-primary-text)] shadow-sm hover:bg-[var(--color-primary-hover)]"
  end
%>
<button
  type="button"
  data-action="click->signup-modal#open"
  data-plan="<%= plan %>"
  data-heading="<%= heading %>"
  data-subtext="<%= subtext %>"
  class="<%= button_style %> <%= additional_classes %>"
>
  <%= text %>
</button>
```

**After creating the partial, update these files:**
1. `app/views/pages/home.html.erb` - Replace lines 15-24
2. `app/views/pages/home.html.erb` - Replace lines 170-179
3. `app/views/pages/home.html.erb` - Replace lines 230-238

**Example usage:**
```erb
<%# Hero section %>
<%= render "shared/signup_cta_button",
  text: "Start listening free",
  plan: "free",
  heading: "Start listening free",
  subtext: "2 episodes/month, no credit card required",
  style: :primary
%>

<%# Free pricing card %>
<%= render "shared/signup_cta_button",
  text: "Create my feed",
  plan: "free",
  heading: "Start listening free",
  subtext: "2 episodes/month, no credit card required",
  style: :outline,
  additional_classes: "mt-6"
%>

<%# Bottom CTA %>
<%= render "shared/signup_cta_button",
  text: "Create my free feed",
  plan: "free",
  heading: "Start listening free",
  subtext: "2 episodes/month, no credit card required",
  style: :large,
  additional_classes: "mt-8"
%>
```

---

### Task 3: Create Legal Links Partial

**Create:** `app/views/shared/_legal_links.html.erb`

**Current duplicates in:**
- `app/views/sessions/new.html.erb:45-48`
- `app/views/episodes/show.html.erb:79-81`

**Requirements:**
- Accept parameter: `prefix` (optional, default: "By signing up, you agree to our")
- Links to terms and privacy policy
- Consistent styling
- Flexible prefix text

**Signature:**
```erb
<%# locals: (prefix: "By signing up, you agree to our", text_size: "text-sm") %>
```

**Implementation:**
```erb
<%# locals: (prefix: "By signing up, you agree to our", text_size: "text-sm") %>
<%= prefix %>
<%= link_to "Terms of Service", terms_path, class: "font-semibold text-[var(--color-primary)] hover:text-[var(--color-primary-hover)]" %>
and
<%= link_to "Privacy Policy", privacy_path, class: "font-semibold text-[var(--color-primary)] hover:text-[var(--color-primary-hover)]" %>.
```

**After creating the partial, update these files:**
1. `app/views/sessions/new.html.erb` - Replace lines 45-48
2. `app/views/episodes/show.html.erb` - Replace lines 79-81

**Example usage:**
```erb
<%# sessions/new.html.erb %>
<p class="text-xs text-[var(--color-subtext)] text-center">
  <%= render "shared/legal_links" %>
</p>

<%# episodes/show.html.erb %>
<p class="mt-4 text-sm text-[var(--color-subtext)]">
  Free tier, no credit card required. <%= render "shared/legal_links" %>
</p>
```

---

## Testing Checklist

After implementation, verify:
- [ ] Form actions work correctly (submit + cancel)
- [ ] All signup CTA buttons open the modal with correct data
- [ ] Modal displays correct heading and subtext
- [ ] Legal links navigate to correct pages
- [ ] Responsive layout works (mobile + desktop)
- [ ] Button styling matches original design
- [ ] Run Rails tests: `rails test`

## Success Criteria
- 3 new partials created in `app/views/shared/`
- 8 instances replaced across 2 view files
- Form submission still works correctly
- Modal integration preserved
- Tests passing
