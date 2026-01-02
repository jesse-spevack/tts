# Agent Prompt 1: Core Shared Components

## Objective
Extract and implement the highest-priority, most-duplicated shared components: clipboard button, back navigation link, and feature list items.

## Context
These components are duplicated across multiple views and eliminating this duplication will reduce ~150 lines of code while improving maintainability.

## Tasks

### Task 1: Create Clipboard Button Partial

**Create:** `app/views/shared/_clipboard_button.html.erb`

**Current duplicates in:**
- `app/views/episodes/index.html.erb:9-17`
- `app/views/episodes/_episode_card.html.erb:9-17`
- `app/views/episodes/show.html.erb:39-47`

**Requirements:**
- Accept parameters: `content` (text to copy), `title` (tooltip), `icon` (default: "share")
- Use existing clipboard controller pattern
- Support both "share" and "copy" icons
- Include the checkmark toggle behavior (copyIcon → checkIcon)
- Return green checkmark on success

**Signature:**
```erb
<%# locals: (content:, title: "Copy to clipboard", icon: "share") %>
```

**Example usage:**
```erb
<%= render "shared/clipboard_button",
  content: episode_url(episode.prefix_id),
  title: "Copy share link",
  icon: "share"
%>
```

**After creating the partial, update these files to use it:**
1. `app/views/episodes/index.html.erb` (line 9-17)
2. `app/views/episodes/_episode_card.html.erb` (line 9-17)
3. `app/views/episodes/show.html.erb` (line 39-47 and 44-46)

---

### Task 2: Create Back Navigation Link Partial

**Create:** `app/views/shared/_back_link.html.erb`

**Current duplicates in:**
- `app/views/settings/show.html.erb:2-4`
- `app/views/billing/show.html.erb:2-4`
- `app/views/upgrades/show.html.erb:2-4`

**Requirements:**
- Accept parameters: `path`, `text` (default: "Back")
- Include arrow_left icon
- Use existing styling classes

**Signature:**
```erb
<%# locals: (path:, text: "Back") %>
```

**Example usage:**
```erb
<%= render "shared/back_link",
  path: episodes_path,
  text: "Back to Episodes"
%>
```

**After creating the partial, update these files to use it:**
1. `app/views/settings/show.html.erb` (line 2-4)
2. `app/views/billing/show.html.erb` (line 2-4)
3. `app/views/upgrades/show.html.erb` (line 2-4)

---

### Task 3: Create Feature List Item Partial

**Create:** `app/views/shared/_feature_list_item.html.erb`

**Current duplicates in:**
- `app/views/pages/home.html.erb:182-211` (5 instances)
- `app/views/shared/_premium_card.html.erb:47-59` (3 instances)

**Requirements:**
- Accept parameter: `text`
- Include checkmark SVG (from line 183-185 in home.html.erb)
- Use flex gap-x-3 layout
- Match existing styling

**Signature:**
```erb
<%# locals: (text:) %>
```

**Example usage:**
```erb
<ul class="mt-8 space-y-3 text-sm text-[var(--color-subtext)]">
  <%= render "shared/feature_list_item", text: "Private podcast feed" %>
  <%= render "shared/feature_list_item", text: "Unlimited episodes" %>
</ul>
```

**After creating the partial, update these files:**
1. `app/views/pages/home.html.erb` - Replace lines 182-211 with loop using partial
2. `app/views/shared/_premium_card.html.erb` - Replace lines 47-59 with loop using partial

**Note for home.html.erb:** Extract the features into a local variable array first:
```erb
<% free_features = [
  "Private podcast feed",
  "Paste links, text, or upload files",
  "Choose your voice",
  "2 episodes per month",
  "Up to 15,000 characters"
] %>
<ul class="mt-8 space-y-3 text-sm text-[var(--color-subtext)]">
  <% free_features.each do |feature| %>
    <%= render "shared/feature_list_item", text: feature %>
  <% end %>
</ul>
```

---

## Testing Checklist

After implementation, verify:
- [ ] All clipboard buttons still work (copy to clipboard)
- [ ] Checkmark appears on successful copy
- [ ] Back links navigate correctly
- [ ] Feature lists render with proper spacing and icons
- [ ] No visual regressions (compare before/after screenshots)
- [ ] Run Rails tests: `rails test`

## Success Criteria
- 3 new partials created in `app/views/shared/`
- 8 view files updated to use new partials
- ~150 lines of duplicate code removed
- All existing functionality preserved
- Tests passing
