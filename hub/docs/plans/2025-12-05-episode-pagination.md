# Episode List Pagination Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add pagination to the episodes index using Pagy, 10 episodes per page, with Turbo Frame for partial updates.

**Architecture:** Install Pagy gem and configure with 10 items per page and `:last_page` overflow handling. Wrap episode list in Turbo Frame for partial updates. Create custom pagination partial matching existing Tailwind design with dark mode support.

**Tech Stack:** Rails 8, Pagy, Turbo Frames, Tailwind CSS

---

## Task 1: Add Pagy Gem

**Files:**
- Modify: `Gemfile:50` (after faraday gems)

**Step 1: Add gem to Gemfile**

Add after line 52 (after `gem "faraday-follow_redirects"`):

```ruby
# Pagination
gem "pagy", "~> 9.0"
```

**Step 2: Run bundle install**

Run: `bundle install`
Expected: Pagy gem installed successfully

**Step 3: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "feat: add pagy gem for pagination"
```

---

## Task 2: Configure Pagy Initializer

**Files:**
- Create: `config/initializers/pagy.rb`

**Step 1: Create Pagy initializer**

```ruby
# frozen_string_literal: true

Pagy::DEFAULT[:limit] = 10
Pagy::DEFAULT[:overflow] = :last_page
```

**Step 2: Verify configuration loads**

Run: `bin/rails runner "puts Pagy::DEFAULT[:limit]"`
Expected: `10`

**Step 3: Commit**

```bash
git add config/initializers/pagy.rb
git commit -m "feat: configure pagy with 10 items per page"
```

---

## Task 3: Include Pagy in ApplicationController

**Files:**
- Modify: `app/controllers/application_controller.rb`

**Step 1: Read current ApplicationController**

Read the file to understand current structure.

**Step 2: Add Pagy backend include**

Add after the class declaration:

```ruby
include Pagy::Backend
```

**Step 3: Verify controller loads**

Run: `bin/rails runner "ApplicationController.new"`
Expected: No errors

**Step 4: Commit**

```bash
git add app/controllers/application_controller.rb
git commit -m "feat: include pagy backend in application controller"
```

---

## Task 4: Include Pagy in ApplicationHelper

**Files:**
- Modify: `app/helpers/application_helper.rb`

**Step 1: Read current ApplicationHelper**

Read the file to understand current structure.

**Step 2: Add Pagy frontend include**

Add inside the module:

```ruby
include Pagy::Frontend
```

**Step 3: Commit**

```bash
git add app/helpers/application_helper.rb
git commit -m "feat: include pagy frontend in application helper"
```

---

## Task 5: Write Failing Test for Pagination

**Files:**
- Modify: `test/controllers/episodes_controller_test.rb`
- Modify: `test/fixtures/episodes.yml`

**Step 1: Add pagination fixtures**

Add 12 more episode fixtures to `test/fixtures/episodes.yml` (after existing fixtures):

```yaml
pagination_ep_1:
  podcast: one
  user: one
  title: Pagination Episode 1
  author: Test Author
  description: Test description for pagination
  status: complete
  gcs_episode_id: pag1
  audio_size_bytes: 1000
  duration_seconds: 60

pagination_ep_2:
  podcast: one
  user: one
  title: Pagination Episode 2
  author: Test Author
  description: Test description for pagination
  status: complete
  gcs_episode_id: pag2
  audio_size_bytes: 1000
  duration_seconds: 60

pagination_ep_3:
  podcast: one
  user: one
  title: Pagination Episode 3
  author: Test Author
  description: Test description for pagination
  status: complete
  gcs_episode_id: pag3
  audio_size_bytes: 1000
  duration_seconds: 60

pagination_ep_4:
  podcast: one
  user: one
  title: Pagination Episode 4
  author: Test Author
  description: Test description for pagination
  status: complete
  gcs_episode_id: pag4
  audio_size_bytes: 1000
  duration_seconds: 60

pagination_ep_5:
  podcast: one
  user: one
  title: Pagination Episode 5
  author: Test Author
  description: Test description for pagination
  status: complete
  gcs_episode_id: pag5
  audio_size_bytes: 1000
  duration_seconds: 60

pagination_ep_6:
  podcast: one
  user: one
  title: Pagination Episode 6
  author: Test Author
  description: Test description for pagination
  status: complete
  gcs_episode_id: pag6
  audio_size_bytes: 1000
  duration_seconds: 60

pagination_ep_7:
  podcast: one
  user: one
  title: Pagination Episode 7
  author: Test Author
  description: Test description for pagination
  status: complete
  gcs_episode_id: pag7
  audio_size_bytes: 1000
  duration_seconds: 60

pagination_ep_8:
  podcast: one
  user: one
  title: Pagination Episode 8
  author: Test Author
  description: Test description for pagination
  status: complete
  gcs_episode_id: pag8
  audio_size_bytes: 1000
  duration_seconds: 60

pagination_ep_9:
  podcast: one
  user: one
  title: Pagination Episode 9
  author: Test Author
  description: Test description for pagination
  status: complete
  gcs_episode_id: pag9
  audio_size_bytes: 1000
  duration_seconds: 60

pagination_ep_10:
  podcast: one
  user: one
  title: Pagination Episode 10
  author: Test Author
  description: Test description for pagination
  status: complete
  gcs_episode_id: pag10
  audio_size_bytes: 1000
  duration_seconds: 60

pagination_ep_11:
  podcast: one
  user: one
  title: Pagination Episode 11
  author: Test Author
  description: Test description for pagination
  status: complete
  gcs_episode_id: pag11
  audio_size_bytes: 1000
  duration_seconds: 60

pagination_ep_12:
  podcast: one
  user: one
  title: Pagination Episode 12
  author: Test Author
  description: Test description for pagination
  status: complete
  gcs_episode_id: pag12
  audio_size_bytes: 1000
  duration_seconds: 60
```

**Step 2: Add pagination tests**

Add to `test/controllers/episodes_controller_test.rb`:

```ruby
# Pagination tests

test "index paginates episodes to 10 per page" do
  get episodes_url
  assert_response :success

  # Should have @pagy assigned
  assert assigns(:pagy).present?, "Expected @pagy to be assigned"

  # Should only show 10 episodes (we have 14 total: one, pagination_ep_1..12, and one from other podcast)
  # Actually podcast :one has 13 episodes (one + 12 pagination), so first page = 10
  assert_equal 10, assigns(:episodes).size
end

test "index shows second page when page param provided" do
  get episodes_url, params: { page: 2 }
  assert_response :success

  # Second page should have remaining episodes
  assert assigns(:episodes).size > 0
  assert assigns(:episodes).size <= 10
end

test "index handles page beyond max by showing last page" do
  get episodes_url, params: { page: 999 }
  assert_response :success

  # Should not error, should show last page
  assert assigns(:pagy).present?
  assert assigns(:episodes).present?
end

test "index renders turbo frame for episodes list" do
  get episodes_url
  assert_response :success
  assert_select "turbo-frame#episodes_list"
end

test "index does not show pagination when 10 or fewer episodes" do
  # Delete pagination fixtures to have only 1 episode
  Episode.where(podcast: podcasts(:one)).where.not(id: episodes(:one).id).delete_all

  get episodes_url
  assert_response :success

  # Should not render pagination nav
  assert_select "nav.pagination", count: 0
end
```

**Step 3: Run tests to verify they fail**

Run: `bin/rails test test/controllers/episodes_controller_test.rb -n /pagination/`
Expected: Tests fail (controller not using Pagy yet)

**Step 4: Commit failing tests**

```bash
git add test/controllers/episodes_controller_test.rb test/fixtures/episodes.yml
git commit -m "test: add failing tests for episode pagination"
```

---

## Task 6: Update EpisodesController to Use Pagy

**Files:**
- Modify: `app/controllers/episodes_controller.rb:6-8`

**Step 1: Update index action**

Change the index action from:

```ruby
def index
  @episodes = @podcast.episodes.newest_first
end
```

To:

```ruby
def index
  @pagy, @episodes = pagy(@podcast.episodes.newest_first)
end
```

**Step 2: Run pagination tests**

Run: `bin/rails test test/controllers/episodes_controller_test.rb -n /pagination/`
Expected: Some tests pass, turbo frame tests still fail

**Step 3: Commit**

```bash
git add app/controllers/episodes_controller.rb
git commit -m "feat: use pagy for episode pagination in controller"
```

---

## Task 7: Create Pagination Partial

**Files:**
- Create: `app/views/episodes/_pagination.html.erb`

**Step 1: Create pagination partial**

```erb
<%# Only show pagination when there's more than one page %>
<% return if pagy.pages <= 1 %>

<nav class="pagination flex items-center justify-between border-t border-gray-200 px-4 sm:px-0 dark:border-white/10 mt-6">
  <%# Previous link %>
  <div class="-mt-px flex w-0 flex-1">
    <% if pagy.prev %>
      <%= link_to episodes_path(page: pagy.prev),
            class: "inline-flex items-center border-t-2 border-transparent pt-4 pr-1 text-sm font-medium text-gray-500 hover:border-gray-300 hover:text-gray-700 dark:text-gray-400 dark:hover:border-white/20 dark:hover:text-gray-200",
            data: { turbo_frame: "episodes_list", turbo_action: "advance" } do %>
        <svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true" class="mr-3 size-5 text-gray-400 dark:text-gray-500">
          <path d="M18 10a.75.75 0 0 1-.75.75H4.66l2.1 1.95a.75.75 0 1 1-1.02 1.1l-3.5-3.25a.75.75 0 0 1 0-1.1l3.5-3.25a.75.75 0 1 1 1.02 1.1l-2.1 1.95h12.59A.75.75 0 0 1 18 10Z" clip-rule="evenodd" fill-rule="evenodd" />
        </svg>
        Previous
      <% end %>
    <% else %>
      <span class="inline-flex items-center border-t-2 border-transparent pt-4 pr-1 text-sm font-medium text-gray-300 dark:text-gray-600 cursor-not-allowed">
        <svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true" class="mr-3 size-5 text-gray-300 dark:text-gray-600">
          <path d="M18 10a.75.75 0 0 1-.75.75H4.66l2.1 1.95a.75.75 0 1 1-1.02 1.1l-3.5-3.25a.75.75 0 0 1 0-1.1l3.5-3.25a.75.75 0 1 1 1.02 1.1l-2.1 1.95h12.59A.75.75 0 0 1 18 10Z" clip-rule="evenodd" fill-rule="evenodd" />
        </svg>
        Previous
      </span>
    <% end %>
  </div>

  <%# Page numbers (desktop only) %>
  <div class="hidden md:-mt-px md:flex">
    <% pagy.series.each do |item| %>
      <% if item == :gap %>
        <span class="inline-flex items-center border-t-2 border-transparent px-4 pt-4 text-sm font-medium text-gray-500 dark:text-gray-400">...</span>
      <% elsif item == pagy.page %>
        <span aria-current="page" class="inline-flex items-center border-t-2 border-indigo-500 px-4 pt-4 text-sm font-medium text-indigo-600 dark:border-indigo-400 dark:text-indigo-400"><%= item %></span>
      <% else %>
        <%= link_to item, episodes_path(page: item),
              class: "inline-flex items-center border-t-2 border-transparent px-4 pt-4 text-sm font-medium text-gray-500 hover:border-gray-300 hover:text-gray-700 dark:text-gray-400 dark:hover:border-white/20 dark:hover:text-gray-200",
              data: { turbo_frame: "episodes_list", turbo_action: "advance" } %>
      <% end %>
    <% end %>
  </div>

  <%# Next link %>
  <div class="-mt-px flex w-0 flex-1 justify-end">
    <% if pagy.next %>
      <%= link_to episodes_path(page: pagy.next),
            class: "inline-flex items-center border-t-2 border-transparent pt-4 pl-1 text-sm font-medium text-gray-500 hover:border-gray-300 hover:text-gray-700 dark:text-gray-400 dark:hover:border-white/20 dark:hover:text-gray-200",
            data: { turbo_frame: "episodes_list", turbo_action: "advance" } do %>
        Next
        <svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true" class="ml-3 size-5 text-gray-400 dark:text-gray-500">
          <path d="M2 10a.75.75 0 0 1 .75-.75h12.59l-2.1-1.95a.75.75 0 1 1 1.02-1.1l3.5 3.25a.75.75 0 0 1 0 1.1l-3.5 3.25a.75.75 0 1 1-1.02-1.1l2.1-1.95H2.75A.75.75 0 0 1 2 10Z" clip-rule="evenodd" fill-rule="evenodd" />
        </svg>
      <% end %>
    <% else %>
      <span class="inline-flex items-center border-t-2 border-transparent pt-4 pl-1 text-sm font-medium text-gray-300 dark:text-gray-600 cursor-not-allowed">
        Next
        <svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true" class="ml-3 size-5 text-gray-300 dark:text-gray-600">
          <path d="M2 10a.75.75 0 0 1 .75-.75h12.59l-2.1-1.95a.75.75 0 1 1 1.02-1.1l3.5 3.25a.75.75 0 0 1 0 1.1l-3.5 3.25a.75.75 0 1 1-1.02-1.1l2.1-1.95H2.75A.75.75 0 0 1 2 10Z" clip-rule="evenodd" fill-rule="evenodd" />
        </svg>
      </span>
    <% end %>
  </div>
</nav>
```

**Step 2: Commit**

```bash
git add app/views/episodes/_pagination.html.erb
git commit -m "feat: create pagination partial with tailwind styling"
```

---

## Task 8: Update Episodes Index with Turbo Frame

**Files:**
- Modify: `app/views/episodes/index.html.erb`

**Step 1: Wrap episode list and pagination in Turbo Frame**

Replace the content after the header div (starting at the `<% if @episodes.any? %>` line) with:

```erb
<%= turbo_frame_tag "episodes_list" do %>
  <% if @episodes.any? %>
    <div class="flex flex-col gap-3">
      <% @episodes.each do |episode| %>
        <%= render "episode_card", episode: episode %>
      <% end %>
    </div>

    <%= render "pagination", pagy: @pagy %>
  <% else %>
    <%= render "shared/card", padding: "p-12" do %>
      <div class="text-center">
        <div class="max-w-sm mx-auto">
          <p class="text-lg mb-4">No episodes yet</p>
          <ol class="text-left text-[var(--color-subtext)] space-y-2">
            <li>1. Click <strong>+ New Episode</strong> above</li>
            <li>2. Upload a text file with your content</li>
            <li>3. We'll generate the audio for you</li>
          </ol>
        </div>
      </div>
    <% end %>
  <% end %>
<% end %>
```

**Step 2: Run all pagination tests**

Run: `bin/rails test test/controllers/episodes_controller_test.rb -n /pagination/`
Expected: All pagination tests pass

**Step 3: Run full test suite**

Run: `bin/rails test`
Expected: All tests pass

**Step 4: Commit**

```bash
git add app/views/episodes/index.html.erb
git commit -m "feat: wrap episode list in turbo frame with pagination"
```

---

## Task 9: Final Verification

**Step 1: Start the server and manually verify**

Run: `bin/rails server`

Verify:
1. Episodes page loads
2. If you have >10 episodes, pagination appears
3. Clicking page numbers updates the list without full page reload
4. URL updates when navigating pages
5. Back button works
6. Previous is disabled on page 1
7. Next is disabled on last page

**Step 2: Run full test suite one more time**

Run: `bin/rails test`
Expected: All tests pass

**Step 3: Final commit for any cleanup**

If any changes needed, commit them.
