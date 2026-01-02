# Agent Prompt 4: Pricing & Episode Components

## Objective
Extract pricing card components and episode-related partials to create symmetry with the existing premium card and improve episode views.

## Context
The Free pricing card is inline on the home page while Premium is already a partial. Episode actions follow a pattern that can be extracted. Empty states can be made reusable.

## Tasks

### Task 1: Create Free Pricing Card Partial

**Create:** `app/views/shared/_free_card.html.erb`

**Current inline location:**
- `app/views/pages/home.html.erb:159-213`

**Requirements:**
- Accept parameter: `mode` (:landing or :billing)
- Match structure of `_premium_card.html.erb`
- Include all free tier features
- Use signup CTA button (assumes Agent 3 completed)

**Signature:**
```erb
<%# locals: (mode:) %>
```

**Implementation:**
```erb
<%# locals: (mode:) %>
<div class="rounded-2xl p-8 ring-1 ring-[var(--color-overlay0)]">
  <h3 class="text-lg font-semibold text-[var(--color-text)]">Free</h3>
  <p class="mt-4 text-sm text-[var(--color-subtext)]">
    Try it out, no credit card required.
  </p>

  <p class="mt-6">
    <span class="text-4xl font-semibold tracking-tight text-[var(--color-text)]">$0</span>
    <span class="text-sm text-[var(--color-subtext)]">/month</span>
  </p>

  <%= render "shared/signup_cta_button",
    text: "Create my feed",
    plan: "free",
    heading: "Start listening free",
    subtext: "2 episodes/month, no credit card required",
    style: :outline,
    additional_classes: "mt-6"
  %>

  <ul class="mt-8 space-y-3 text-sm text-[var(--color-subtext)]">
    <%= render "shared/feature_list_item", text: "Private podcast feed" %>
    <%= render "shared/feature_list_item", text: "Paste links, text, or upload files" %>
    <%= render "shared/feature_list_item", text: "Choose your voice" %>
    <%= render "shared/feature_list_item", text: "2 episodes per month" %>
    <%= render "shared/feature_list_item", text: "Up to 15,000 characters" %>
  </ul>
</div>
```

**After creating the partial, update:**
1. `app/views/pages/home.html.erb` - Replace lines 159-213 with:
```erb
<%= render "shared/free_card", mode: :landing %>
```

**Note:** This partial depends on Agent 1 completing `_feature_list_item.html.erb` and Agent 3 completing `_signup_cta_button.html.erb`. If those aren't available yet, use the inline markup temporarily.

---

### Task 2: Create Empty State Partial

**Create:** `app/views/shared/_empty_state.html.erb`

**Current location:**
- `app/views/episodes/index.html.erb:35-45`

**Requirements:**
- Accept parameters: `title`, `instructions` (array), `max_width` (default: "sm")
- Support ordered list of instructions
- Centered layout
- Flexible for reuse in other contexts

**Signature:**
```erb
<%# locals: (title:, instructions: [], max_width: "sm") %>
```

**Implementation:**
```erb
<%# locals: (title:, instructions: [], max_width: "sm") %>
<%= render "shared/card", padding: "p-12" do %>
  <div class="text-center">
    <div class="max-w-<%= max_width %> mx-auto">
      <p class="text-lg mb-4"><%= title %></p>
      <% if instructions.any? %>
        <ol class="text-left text-[var(--color-subtext)] space-y-2">
          <% instructions.each do |instruction| %>
            <li><%= instruction %></li>
          <% end %>
        </ol>
      <% end %>
    </div>
  </div>
<% end %>
```

**After creating the partial, update:**
1. `app/views/episodes/index.html.erb` - Replace lines 35-45 with:
```erb
<%= render "shared/empty_state",
  title: "No episodes yet",
  instructions: [
    "1. Click <strong>+ New Episode</strong> above".html_safe,
    "2. Upload a text file with your content",
    "3. We'll generate the audio for you"
  ]
%>
```

---

### Task 3: Create Episode Actions Partial

**Create:** `app/views/episodes/_episode_actions.html.erb`

**Current patterns in:**
- `app/views/episodes/_episode_card.html.erb:7-35` (compact with status)
- `app/views/episodes/show.html.erb:38-60` (full with buttons)

**Requirements:**
- Accept parameters: `episode`, `layout` (:compact or :full)
- Support share, download, delete, and external link actions
- Conditional rendering based on episode status
- Include duration display for compact layout

**Signature:**
```erb
<%# locals: (episode:, layout: :compact) %>
```

**Implementation:**
```erb
<%# locals: (episode:, layout: :compact) %>
<% if layout == :compact %>
  <%# Compact layout for episode cards %>
  <div class="flex items-center gap-3">
    <% if episode.complete? %>
      <%= render "shared/clipboard_button",
        content: episode_url(episode.prefix_id),
        title: "Copy share link",
        icon: "share"
      %>
      <%= link_to episode_path(episode.prefix_id, format: :mp3),
        class: "text-[var(--color-subtext)] hover:text-[var(--color-primary)] transition-colors",
        title: "Download MP3" do %>
        <%= render "shared/icons/download" %>
      <% end %>
    <% end %>
    <% if deletable?(episode) %>
      <%= button_to episode_path(episode),
        method: :delete,
        form_class: "contents",
        class: "text-[var(--color-subtext)] hover:text-[var(--color-red)] transition-colors cursor-pointer",
        title: "Delete episode",
        data: { turbo_confirm: "Are you sure you want to delete '#{episode.title}'?", turbo_frame: "_top" } do %>
        <%= render "shared/icons/trash" %>
      <% end %>
    <% end %>
    <% if episode.duration_seconds %>
      <span class="text-sm text-[var(--color-subtext)]"><%= format_duration(episode.duration_seconds) %></span>
    <% end %>
  </div>
<% else %>
  <%# Full layout for show page with labeled buttons %>
  <div class="flex gap-4">
    <%= render "shared/clipboard_button",
      content: episode_url(episode.prefix_id),
      title: "Share episode"
    %>

    <%= link_to episode_path(episode.prefix_id, format: :mp3),
      class: "flex items-center gap-2 border border-[var(--color-overlay0)] text-[var(--color-text)] font-medium py-2 px-4 rounded-lg hover:border-[var(--color-primary)] cursor-pointer transition-colors" do %>
      <%= render "shared/icons/download" %>
      <span>Download MP3</span>
    <% end %>

    <% if episode.url? && episode.source_url.present? %>
      <%= link_to episode.source_url, target: "_blank", rel: "noopener",
        class: "flex items-center gap-2 border border-[var(--color-overlay0)] text-[var(--color-text)] font-medium py-2 px-4 rounded-lg hover:border-[var(--color-primary)] cursor-pointer transition-colors" do %>
        <%= render "shared/icons/external_link" %>
        <span>View Original</span>
      <% end %>
    <% end %>
  </div>
<% end %>
```

**After creating the partial, update:**
1. `app/views/episodes/_episode_card.html.erb` - Replace lines 7-35 with:
```erb
<div class="mb-2 flex justify-between items-center">
  <div class="flex items-center gap-2">
    <%= status_badge(episode.status) %>
  </div>
  <%= render "episodes/episode_actions", episode: episode, layout: :compact %>
</div>
```

2. `app/views/episodes/show.html.erb` - Replace lines 38-60 with:
```erb
<%= render "episodes/episode_actions", episode: @episode, layout: :full %>
```

**Note:** The `:full` layout's clipboard button needs special styling. Update the clipboard_button partial to accept a `with_label` parameter:

In `_clipboard_button.html.erb`, support:
```erb
<% if defined?(with_label) && with_label %>
  <button ... class="flex items-center gap-2 border border-[var(--color-overlay0)] ...">
    <span data-clipboard-target="copyIcon"><%= render "shared/icons/#{icon}" %></span>
    <span data-clipboard-target="checkIcon" class="hidden text-[var(--color-green)]"><%= render "shared/icons/check_circle" %></span>
    <span>Share</span>
  </button>
<% else %>
  <%# existing compact implementation %>
<% end %>
```

---

## Testing Checklist

After implementation, verify:
- [ ] Free pricing card displays correctly on home page
- [ ] Both pricing cards have visual symmetry
- [ ] Empty state renders with proper styling
- [ ] Episode actions work in both layouts (compact & full)
- [ ] Share/download/delete buttons function correctly
- [ ] Duration displays in compact layout
- [ ] External link appears only for URL-based episodes
- [ ] Run Rails tests: `rails test`

## Success Criteria
- 3 new partials created (1 pricing, 1 empty state, 1 episode actions)
- 3 view files updated
- Pricing cards have symmetrical structure
- Episode actions are DRY and reusable
- Tests passing

## Dependencies
- Depends on Agent 1: `_feature_list_item.html.erb`, `_clipboard_button.html.erb`
- Depends on Agent 3: `_signup_cta_button.html.erb`
- If those aren't complete, implement with fallback to inline markup
