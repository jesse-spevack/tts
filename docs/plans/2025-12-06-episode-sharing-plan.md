# Episode Sharing Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add share and download buttons to episode cards, and create a public episode page for sharing.

**Architecture:** Add prefixed_ids gem to Episode model for URL-safe IDs like `ep_abc123`. Add public `show` action to EpisodesController that skips authentication. Reuse existing clipboard Stimulus controller for copy functionality.

**Tech Stack:** Rails 8.1, prefixed_ids gem, Stimulus, Tailwind CSS, Minitest

---

## Task 1: Add prefixed_ids Gem

**Files:**
- Modify: `hub/Gemfile`

**Step 1: Add the gem to Gemfile**

Open `hub/Gemfile` and add after the `pagy` gem (around line 55):

```ruby
# Prefixed IDs for public URLs
gem "prefixed_ids"
```

**Step 2: Run bundle install**

Run: `cd hub && bundle install`
Expected: Gem installs successfully, Gemfile.lock updated

**Step 3: Commit**

```bash
git add hub/Gemfile hub/Gemfile.lock
git commit -m "feat: add prefixed_ids gem for shareable episode URLs"
```

---

## Task 2: Add Prefixed ID to Episode Model

**Files:**
- Modify: `hub/app/models/episode.rb`
- Test: `hub/test/models/episode_test.rb`

**Step 1: Write the failing test**

Create or open `hub/test/models/episode_test.rb` and add:

```ruby
require "test_helper"

class EpisodeTest < ActiveSupport::TestCase
  test "has a prefixed id starting with ep_" do
    episode = episodes(:two)
    assert episode.prefix_id.present?
    assert episode.prefix_id.start_with?("ep_")
  end

  test "can be found by prefix_id" do
    episode = episodes(:two)
    found = Episode.find_by_prefix_id(episode.prefix_id)
    assert_equal episode, found
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd hub && bin/rails test test/models/episode_test.rb -v`
Expected: FAIL - undefined method `prefix_id` or similar

**Step 3: Add prefixed_ids to Episode model**

Open `hub/app/models/episode.rb` and add after line 1:

```ruby
class Episode < ApplicationRecord
  has_prefix_id :ep
```

The full first few lines should be:

```ruby
class Episode < ApplicationRecord
  has_prefix_id :ep

  belongs_to :podcast
  belongs_to :user
```

**Step 4: Run test to verify it passes**

Run: `cd hub && bin/rails test test/models/episode_test.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add hub/app/models/episode.rb hub/test/models/episode_test.rb
git commit -m "feat: add prefixed_ids to Episode model with ep_ prefix"
```

---

## Task 3: Add Show Route for Episodes

**Files:**
- Modify: `hub/config/routes.rb`

**Step 1: Update the routes file**

Open `hub/config/routes.rb` and change line 4 from:

```ruby
resources :episodes, only: [ :index, :new, :create ]
```

to:

```ruby
resources :episodes, only: [ :index, :new, :create, :show ]
```

**Step 2: Verify route exists**

Run: `cd hub && bin/rails routes | grep episode`
Expected: See `episode GET /episodes/:id(.:format) episodes#show`

**Step 3: Commit**

```bash
git add hub/config/routes.rb
git commit -m "feat: add show route for episodes"
```

---

## Task 4: Add Show Action to EpisodesController

**Files:**
- Modify: `hub/app/controllers/episodes_controller.rb`
- Test: `hub/test/controllers/episodes_controller_test.rb`

**Step 1: Write the failing tests**

Open `hub/test/controllers/episodes_controller_test.rb` and add these tests at the end (before the final `end`):

```ruby
  # Public episode show tests

  test "show renders episode page for complete episode without authentication" do
    sign_out
    episode = episodes(:two) # status: complete
    get episode_url(episode.prefix_id)
    assert_response :success
  end

  test "show returns 404 for non-complete episode" do
    sign_out
    episode = episodes(:one) # status: pending
    get episode_url(episode.prefix_id)
    assert_response :not_found
  end

  test "show returns 404 for non-existent episode" do
    sign_out
    get episode_url("ep_nonexistent")
    assert_response :not_found
  end

  test "show displays episode title" do
    episode = episodes(:two)
    get episode_url(episode.prefix_id)
    assert_select "h1", text: episode.title
  end

  test "show displays audio player for complete episode" do
    episode = episodes(:two)
    get episode_url(episode.prefix_id)
    assert_select "audio[controls]"
  end
```

**Step 2: Run tests to verify they fail**

Run: `cd hub && bin/rails test test/controllers/episodes_controller_test.rb -n /show/ -v`
Expected: FAIL - action 'show' could not be found or similar

**Step 3: Add show action to controller**

Open `hub/app/controllers/episodes_controller.rb` and:

1. Change line 2 to allow unauthenticated access to show:

```ruby
  before_action :require_authentication, except: [ :show ]
```

2. Add the show action after `def index` (after line 8):

```ruby
  def show
    @episode = Episode.find_by_prefix_id!(params[:id])
    raise ActiveRecord::RecordNotFound unless @episode.complete?
    @podcast = @episode.podcast
  rescue PrefixedIds::RecordNotFound
    raise ActiveRecord::RecordNotFound
  end
```

**Step 4: Run tests to verify they pass (except view tests)**

Run: `cd hub && bin/rails test test/controllers/episodes_controller_test.rb -n /show/ -v`
Expected: Some tests may fail due to missing view - that's expected, we'll create it next

**Step 5: Commit**

```bash
git add hub/app/controllers/episodes_controller.rb hub/test/controllers/episodes_controller_test.rb
git commit -m "feat: add public show action for episodes"
```

---

## Task 5: Create Share and Download Icon Partials

**Files:**
- Create: `hub/app/views/shared/icons/_share.html.erb`
- Create: `hub/app/views/shared/icons/_download.html.erb`

**Step 1: Create share icon partial**

Create `hub/app/views/shared/icons/_share.html.erb`:

```erb
<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="size-5">
  <path stroke-linecap="round" stroke-linejoin="round" d="M7.217 10.907a2.25 2.25 0 1 0 0 2.186m0-2.186c.18.324.283.696.283 1.093s-.103.77-.283 1.093m0-2.186 9.566-5.314m-9.566 7.5 9.566 5.314m0 0a2.25 2.25 0 1 0 3.935 2.186 2.25 2.25 0 0 0-3.935-2.186Zm0-12.814a2.25 2.25 0 1 0 3.933-2.185 2.25 2.25 0 0 0-3.933 2.185Z" />
</svg>
```

**Step 2: Create download icon partial**

Create `hub/app/views/shared/icons/_download.html.erb`:

```erb
<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="size-5">
  <path stroke-linecap="round" stroke-linejoin="round" d="m9 13.5 3 3m0 0 3-3m-3 3v-6m1.06-4.19-2.12-2.12a1.5 1.5 0 0 0-1.061-.44H4.5A2.25 2.25 0 0 0 2.25 6v12a2.25 2.25 0 0 0 2.25 2.25h15A2.25 2.25 0 0 0 21.75 18V9a2.25 2.25 0 0 0-2.25-2.25h-5.379a1.5 1.5 0 0 1-1.06-.44Z" />
</svg>
```

**Step 3: Commit**

```bash
git add hub/app/views/shared/icons/_share.html.erb hub/app/views/shared/icons/_download.html.erb
git commit -m "feat: add share and download icon partials"
```

---

## Task 6: Create Public Episode Show View

**Files:**
- Create: `hub/app/views/episodes/show.html.erb`

**Step 1: Create the show view**

Create `hub/app/views/episodes/show.html.erb`:

```erb
<% content_for :title, @episode.title %>

<div class="max-w-2xl mx-auto">
  <%= render "shared/card", padding: "p-8" do %>
    <p class="text-sm text-[var(--color-subtext)] mb-2"><%= @podcast.title %></p>

    <h1 class="text-2xl font-semibold mb-2"><%= @episode.title %></h1>

    <p class="text-sm text-[var(--color-subtext)] mb-6">
      by <%= @episode.author %>
      <% if @episode.duration_seconds %>
        <span class="mx-2">&middot;</span>
        <%= format_duration(@episode.duration_seconds) %>
      <% end %>
    </p>

    <div class="mb-6">
      <audio controls class="w-full" preload="metadata">
        <source src="<%= @episode.audio_url %>" type="audio/mpeg">
        Your browser does not support the audio element.
      </audio>
    </div>

    <p class="text-[var(--color-subtext)] mb-6"><%= @episode.description %></p>

    <div class="flex gap-4">
      <button type="button"
              data-controller="clipboard"
              data-clipboard-content-value="<%= episode_url(@episode.prefix_id) %>"
              data-action="click->clipboard#copy"
              class="flex items-center gap-2 px-4 py-2 rounded-lg border border-[var(--color-border)] hover:bg-[var(--color-surface)] transition-colors cursor-pointer">
        <span data-clipboard-target="copyIcon"><%= render "shared/icons/share" %></span>
        <span data-clipboard-target="checkIcon" class="hidden text-[var(--color-green)]"><%= render "shared/icons/check_circle" %></span>
        <span>Copy Link</span>
      </button>

      <%= link_to @episode.audio_url, download: "#{@episode.title.parameterize}.mp3", class: "flex items-center gap-2 px-4 py-2 rounded-lg border border-[var(--color-border)] hover:bg-[var(--color-surface)] transition-colors" do %>
        <%= render "shared/icons/download" %>
        <span>Download MP3</span>
      <% end %>
    </div>
  <% end %>
</div>
```

**Step 2: Run the controller tests**

Run: `cd hub && bin/rails test test/controllers/episodes_controller_test.rb -n /show/ -v`
Expected: All show tests PASS

**Step 3: Commit**

```bash
git add hub/app/views/episodes/show.html.erb
git commit -m "feat: add public episode show view with audio player"
```

---

## Task 7: Update Episode Card with Share and Download Buttons

**Files:**
- Modify: `hub/app/views/episodes/_episode_card.html.erb`

**Step 1: Update the episode card partial**

Open `hub/app/views/episodes/_episode_card.html.erb` and replace the entire content with:

```erb
<%= turbo_frame_tag dom_id(episode), data: { testid: "episode-card" } do %>
  <%= render "shared/card" do %>
    <div class="mb-2 flex justify-between items-center">
      <div class="flex items-center gap-2">
        <%= status_badge(episode.status) %>
      </div>
      <div class="flex items-center gap-3">
        <% if episode.complete? %>
          <button type="button"
                  data-controller="clipboard"
                  data-clipboard-content-value="<%= episode_url(episode.prefix_id) %>"
                  data-action="click->clipboard#copy"
                  class="text-[var(--color-subtext)] hover:text-[var(--color-primary)] transition-colors cursor-pointer"
                  title="Copy share link">
            <span data-clipboard-target="copyIcon"><%= render "shared/icons/share" %></span>
            <span data-clipboard-target="checkIcon" class="hidden text-[var(--color-green)]"><%= render "shared/icons/check_circle" %></span>
          </button>
          <%= link_to episode.audio_url, download: "#{episode.title.parameterize}.mp3", class: "text-[var(--color-subtext)] hover:text-[var(--color-primary)] transition-colors", title: "Download MP3" do %>
            <%= render "shared/icons/download" %>
          <% end %>
        <% end %>
        <% if episode.duration_seconds %>
          <span class="text-sm text-[var(--color-subtext)]"><%= format_duration(episode.duration_seconds) %></span>
        <% end %>
      </div>
    </div>
    <h2 class="text-lg font-semibold mb-1"><%= episode.title %></h2>
    <% if episode.url? && episode.source_url.present? %>
      <p class="text-xs text-[var(--color-subtext)] truncate mb-1">
        <%= link_to episode.source_url, episode.source_url, target: "_blank", class: "hover:underline" %>
      </p>
    <% end %>
    <div class="flex justify-between items-center text-sm text-[var(--color-subtext)]">
      <span>by <%= episode.author %></span>
      <span><%= episode.created_at.strftime("%b %d, %Y") %></span>
    </div>
    <p class="mt-2 text-xs text-[var(--color-subtext)] font-mono truncate">
      <%= episode.content_preview %>
    </p>
  <% end %>
<% end %>
```

**Step 2: Run all tests to verify nothing broke**

Run: `cd hub && bin/rails test`
Expected: All tests PASS

**Step 3: Commit**

```bash
git add hub/app/views/episodes/_episode_card.html.erb
git commit -m "feat: add share and download buttons to episode card"
```

---

## Task 8: Add Controller Tests for Edge Cases

**Files:**
- Modify: `hub/test/controllers/episodes_controller_test.rb`

**Step 1: Add additional edge case tests**

Open `hub/test/controllers/episodes_controller_test.rb` and add before the final `end`:

```ruby
  test "show works for authenticated users too" do
    episode = episodes(:two)
    get episode_url(episode.prefix_id)
    assert_response :success
  end

  test "show displays download button" do
    episode = episodes(:two)
    get episode_url(episode.prefix_id)
    assert_select "a[download]", text: /Download MP3/
  end

  test "show displays copy link button" do
    episode = episodes(:two)
    get episode_url(episode.prefix_id)
    assert_select "button[data-controller='clipboard']"
  end
```

**Step 2: Run all controller tests**

Run: `cd hub && bin/rails test test/controllers/episodes_controller_test.rb -v`
Expected: All tests PASS

**Step 3: Commit**

```bash
git add hub/test/controllers/episodes_controller_test.rb
git commit -m "test: add edge case tests for episode show action"
```

---

## Task 9: Final Verification

**Step 1: Run full test suite**

Run: `cd hub && bin/rails test`
Expected: All tests PASS

**Step 2: Run rubocop**

Run: `cd hub && bundle exec rubocop`
Expected: No offenses or only pre-existing ones

**Step 3: Manual verification (optional)**

Start the server and verify:
1. Episode cards show share/download icons for complete episodes
2. Clicking share copies URL and shows checkmark
3. Download link downloads the MP3
4. `/episodes/ep_xxxxx` shows public episode page
5. Page works without being logged in

---

## Summary

This implementation adds:
- `prefixed_ids` gem for URL-safe episode IDs
- Public `EpisodesController#show` action
- Public episode page with audio player, copy link, and download
- Share and download buttons on episode cards (complete episodes only)
- Full test coverage
