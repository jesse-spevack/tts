# Very Normal TTS Front End Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Redesign the front end with Catppuccin color palette, improved layout structure, and enhanced UX for episode creation and status monitoring.

**Architecture:** Rails 8 with Tailwind CSS v4, Turbo Streams for real-time updates, Inter font from Google Fonts. Custom CSS variables for Catppuccin colors with dark/light mode support.

**Tech Stack:** Rails 8.1, Tailwind CSS, Turbo Rails, Inter font, Catppuccin color palette (Latte/Mocha)

---

## Task 1: Add Catppuccin Color Variables to Tailwind

**Files:**
- Modify: `hub/app/assets/tailwind/application.css`

**Step 1: Add CSS custom properties for Catppuccin Latte (light mode)**

```css
@import "tailwindcss";

@layer base {
  :root {
    /* Catppuccin Latte (Light Mode) */
    --color-base: #eff1f5;
    --color-mantle: #e6e9ef;
    --color-crust: #dce0e8;
    --color-text: #4c4f69;
    --color-subtext: #6c6f85;
    --color-surface0: #ccd0da;
    --color-surface1: #bcc0cc;
    --color-surface2: #acb0be;
    --color-overlay0: #9ca0b0;
    --color-overlay1: #8c8fa1;
    --color-overlay2: #7c7f93;

    /* Status Colors */
    --color-yellow: #df8e1d;
    --color-green: #40a02b;
    --color-red: #d20f39;

    /* Primary Action (Teal) */
    --color-primary: #179299;
    --color-primary-hover: #147f85;
    --color-primary-text: #ffffff;
  }

  .dark {
    /* Catppuccin Mocha (Dark Mode) */
    --color-base: #1e1e2e;
    --color-mantle: #181825;
    --color-crust: #11111b;
    --color-text: #cdd6f4;
    --color-subtext: #a6adc8;
    --color-surface0: #313244;
    --color-surface1: #45475a;
    --color-surface2: #585b70;
    --color-overlay0: #6c7086;
    --color-overlay1: #7f849c;
    --color-overlay2: #9399b2;

    /* Status Colors (same hues, adjusted for dark mode) */
    --color-yellow: #f9e2af;
    --color-green: #a6e3a1;
    --color-red: #f38ba8;

    /* Primary Action (Teal) */
    --color-primary: #94e2d5;
    --color-primary-hover: #7fd4c6;
    --color-primary-text: #1e1e2e;
  }

  body {
    background-color: var(--color-base);
    color: var(--color-text);
  }
}
```

**Step 2: Verify Tailwind compiles**

Run: `cd /Users/jesse/code/tts/hub && bin/rails tailwindcss:build`
Expected: Build completes without errors

**Step 3: Commit**

```bash
git add hub/app/assets/tailwind/application.css
git commit -m "feat: add Catppuccin color variables for light/dark mode"
```

---

## Task 2: Add Inter Font from Google Fonts

**Files:**
- Modify: `hub/app/views/layouts/application.html.erb`
- Modify: `hub/app/assets/tailwind/application.css`

**Step 1: Add Google Fonts link to layout head**

In `hub/app/views/layouts/application.html.erb`, after line 17 (the apple-touch-icon link), add:

```erb
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
```

**Step 2: Set Inter as default font in Tailwind**

In `hub/app/assets/tailwind/application.css`, add inside `@layer base`:

```css
  body {
    background-color: var(--color-base);
    color: var(--color-text);
    font-family: 'Inter', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Oxygen, Ubuntu, sans-serif;
  }
```

**Step 3: Verify font loads**

Run: `cd /Users/jesse/code/tts/hub && bin/rails s`
Expected: Visit localhost:3000, open browser dev tools, check computed font-family shows Inter

**Step 4: Commit**

```bash
git add hub/app/views/layouts/application.html.erb hub/app/assets/tailwind/application.css
git commit -m "feat: add Inter font from Google Fonts"
```

---

## Task 3: Create Shared Header Partial

**Files:**
- Create: `hub/app/views/shared/_header.html.erb`
- Modify: `hub/app/views/layouts/application.html.erb`

**Step 1: Create header partial**

Create new file `hub/app/views/shared/_header.html.erb`:

```erb
<header class="fixed top-0 left-0 right-0 bg-[var(--color-base)] border-b border-[var(--color-overlay0)] z-50">
  <div class="max-w-6xl mx-auto px-4 py-4 flex justify-between items-center">
    <div class="text-lg font-semibold">
      Very Normal TTS
    </div>
    <% if authenticated? %>
      <div class="flex items-center gap-4">
        <span class="text-sm text-[var(--color-subtext)]"><%= Current.user.email_address %></span>
        <%= button_to "Logout", session_path, method: :delete, class: "text-sm text-[var(--color-text)] hover:text-[var(--color-primary)] cursor-pointer" %>
      </div>
    <% end %>
  </div>
</header>
```

**Step 2: Update application layout to use header**

Replace the entire `<body>` section in `hub/app/views/layouts/application.html.erb`:

```erb
  <body class="bg-[var(--color-base)] text-[var(--color-text)]">
    <%= render "shared/header" %>
    <main class="max-w-6xl mx-auto mt-20 px-4 py-8">
      <%= yield %>
    </main>
  </body>
```

**Step 3: Start server and verify header appears**

Run: `cd /Users/jesse/code/tts/hub && bin/rails s`
Expected: Header visible at top with "Very Normal TTS" on left, logout on right (when logged in)

**Step 4: Commit**

```bash
git add hub/app/views/shared/_header.html.erb hub/app/views/layouts/application.html.erb
git commit -m "feat: add fixed header with app name and logout button"
```

---

## Task 4: Redesign Sign In Page

**Files:**
- Modify: `hub/app/views/sessions/new.html.erb`

**Step 1: Replace sign in page with new design**

Replace entire content of `hub/app/views/sessions/new.html.erb`:

```erb
<div class="flex justify-center items-center min-h-[calc(100vh-10rem)]">
  <div class="w-full max-w-md border border-[var(--color-overlay0)] rounded-lg p-8">
    <h1 class="text-2xl font-semibold mb-6">Sign in</h1>

    <%= form_with url: session_path, class: "space-y-6" do |form| %>
      <div>
        <label for="email_address" class="block text-sm font-medium mb-2">Email</label>
        <%= form.email_field :email_address,
            required: true,
            autofocus: true,
            autocomplete: "username",
            placeholder: "you@example.com",
            class: "w-full bg-[var(--color-base)] border border-[var(--color-overlay0)] rounded-md px-3 py-2 focus:outline-none focus:border-[var(--color-primary)]" %>
      </div>

      <p class="text-sm text-[var(--color-subtext)]">
        We'll find your account or create a new one
      </p>

      <div>
        <%= form.submit "Send Magic Link",
            class: "w-full bg-[var(--color-primary)] text-[var(--color-primary-text)] font-medium py-2 px-4 rounded-lg hover:bg-[var(--color-primary-hover)] cursor-pointer" %>
      </div>
    <% end %>
  </div>
</div>
```

**Step 2: Verify sign in page displays correctly**

Run: `cd /Users/jesse/code/tts/hub && bin/rails s`
Expected: Visit localhost:3000/session/new, see centered card with email field, helpful text, and styled button

**Step 3: Commit**

```bash
git add hub/app/views/sessions/new.html.erb
git commit -m "feat: redesign sign in page with Catppuccin styling"
```

---

## Task 5: Update Episodes Helper for New Status Colors

**Files:**
- Modify: `hub/app/helpers/episodes_helper.rb`
- Test: `hub/test/helpers/episodes_helper_test.rb`

**Step 1: Write the failing test**

Create new file `hub/test/helpers/episodes_helper_test.rb`:

```ruby
require "test_helper"

class EpisodesHelperTest < ActionView::TestCase
  test "status_badge returns processing badge with pulse animation" do
    result = status_badge("processing")
    assert_includes result, "Processing"
    assert_includes result, "animate-pulse"
    assert_includes result, "var(--color-yellow)"
  end

  test "status_badge returns completed badge with checkmark" do
    result = status_badge("complete")
    assert_includes result, "Completed"
    assert_includes result, "✓"
    assert_includes result, "var(--color-green)"
  end

  test "status_badge returns failed badge with X" do
    result = status_badge("failed")
    assert_includes result, "Failed"
    assert_includes result, "✗"
    assert_includes result, "var(--color-red)"
  end

  test "status_badge returns pending badge" do
    result = status_badge("pending")
    assert_includes result, "Pending"
    assert_includes result, "var(--color-yellow)"
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/jesse/code/tts/hub && bin/rails test test/helpers/episodes_helper_test.rb`
Expected: FAIL with "undefined method `status_badge'"

**Step 3: Write minimal implementation**

Replace entire content of `hub/app/helpers/episodes_helper.rb`:

```ruby
module EpisodesHelper
  def status_badge(status)
    case status
    when "pending"
      content_tag :span, class: "inline-flex items-center gap-1 text-sm" do
        content_tag(:span, "●", class: "text-[var(--color-yellow)]") +
        content_tag(:span, "Pending")
      end
    when "processing"
      content_tag :span, class: "inline-flex items-center gap-1 text-sm" do
        content_tag(:span, "●", class: "text-[var(--color-yellow)] animate-pulse") +
        content_tag(:span, "Processing")
      end
    when "complete"
      content_tag :span, class: "inline-flex items-center gap-1 text-sm" do
        content_tag(:span, "✓", class: "text-[var(--color-green)]") +
        content_tag(:span, "Completed")
      end
    when "failed"
      content_tag :span, class: "inline-flex items-center gap-1 text-sm" do
        content_tag(:span, "✗", class: "text-[var(--color-red)]") +
        content_tag(:span, "Failed")
      end
    else
      content_tag :span, status, class: "text-sm text-[var(--color-subtext)]"
    end
  end

  # Keep old method for backwards compatibility during migration
  def status_class(status)
    case status
    when "pending"
      "bg-yellow-100 text-yellow-800"
    when "processing"
      "bg-blue-100 text-blue-800"
    when "complete"
      "bg-green-100 text-green-800"
    when "failed"
      "bg-red-100 text-red-800"
    else
      "bg-gray-100 text-gray-800"
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `cd /Users/jesse/code/tts/hub && bin/rails test test/helpers/episodes_helper_test.rb`
Expected: PASS (4 tests, all green)

**Step 5: Commit**

```bash
git add hub/app/helpers/episodes_helper.rb hub/test/helpers/episodes_helper_test.rb
git commit -m "feat: add status_badge helper with icons and pulse animation"
```

---

## Task 6: Redesign Episodes List with Card Layout

**Files:**
- Modify: `hub/app/views/episodes/index.html.erb`

**Step 1: Replace episodes index with card layout**

Replace entire content of `hub/app/views/episodes/index.html.erb`:

```erb
<div>
  <div class="flex justify-between items-start mb-8">
    <div>
      <h1 class="text-2xl font-semibold mb-2">Episodes</h1>
      <p class="text-sm text-[var(--color-subtext)]">
        RSS Feed: <%= link_to @podcast.feed_url, @podcast.feed_url, class: "text-[var(--color-primary)] hover:underline", target: "_blank" %>
      </p>
    </div>
    <%= link_to new_episode_path, class: "bg-[var(--color-primary)] text-[var(--color-primary-text)] px-4 py-2 rounded-lg hover:bg-[var(--color-primary-hover)] font-medium" do %>
      + New Episode
    <% end %>
  </div>

  <% if @episodes.any? %>
    <div class="space-y-4">
      <% @episodes.each do |episode| %>
        <div class="border border-[var(--color-overlay0)] rounded-lg p-4">
          <div class="mb-2">
            <%= status_badge(episode.status) %>
          </div>
          <h2 class="text-lg font-semibold mb-1"><%= episode.title %></h2>
          <div class="flex justify-between items-center text-sm text-[var(--color-subtext)]">
            <span>by <%= episode.author %></span>
            <span><%= episode.created_at.strftime("%b %d, %Y") %></span>
          </div>
        </div>
      <% end %>
    </div>
  <% else %>
    <div class="border border-[var(--color-overlay0)] rounded-lg p-12 text-center">
      <div class="max-w-sm mx-auto">
        <p class="text-lg mb-4">Get started:</p>
        <ol class="text-left text-[var(--color-subtext)] mb-6 space-y-2">
          <li>1. Create an episode</li>
          <li>2. Upload your markdown</li>
          <li>3. We generate the audio</li>
        </ol>
        <%= link_to new_episode_path, class: "inline-block bg-[var(--color-primary)] text-[var(--color-primary-text)] px-6 py-2 rounded-lg hover:bg-[var(--color-primary-hover)] font-medium" do %>
          + Create Episode
        <% end %>
      </div>
    </div>
  <% end %>
</div>
```

**Step 2: Verify episodes list displays correctly**

Run: `cd /Users/jesse/code/tts/hub && bin/rails s`
Expected: Visit localhost:3000, see card-based episode list (or empty state if no episodes)

**Step 3: Commit**

```bash
git add hub/app/views/episodes/index.html.erb
git commit -m "feat: redesign episodes list with single-column card layout"
```

---

## Task 7: Create Drag-and-Drop File Upload Stimulus Controller

**Files:**
- Create: `hub/app/javascript/controllers/file_upload_controller.js`
- Modify: `hub/app/javascript/controllers/index.js`

**Step 1: Create file upload controller**

Create new file `hub/app/javascript/controllers/file_upload_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "dropzone", "filename"]

  connect() {
    this.updateFilename()
  }

  triggerInput() {
    this.inputTarget.click()
  }

  handleDragOver(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.add("border-[var(--color-primary)]")
  }

  handleDragLeave(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.remove("border-[var(--color-primary)]")
  }

  handleDrop(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.remove("border-[var(--color-primary)]")

    const files = event.dataTransfer.files
    if (files.length > 0) {
      this.inputTarget.files = files
      this.updateFilename()
    }
  }

  updateFilename() {
    if (this.inputTarget.files.length > 0) {
      const filename = this.inputTarget.files[0].name
      this.filenameTarget.textContent = filename
      this.filenameTarget.classList.remove("hidden")
    } else {
      this.filenameTarget.classList.add("hidden")
    }
  }
}
```

**Step 2: Register controller in index.js**

The controller will auto-register via esbuild/importmap. Verify `hub/app/javascript/controllers/index.js` has:

```javascript
import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
eagerLoadControllersFrom("controllers", application)
```

**Step 3: Verify controller loads**

Run: `cd /Users/jesse/code/tts/hub && bin/rails s`
Expected: No JavaScript errors in console

**Step 4: Commit**

```bash
git add hub/app/javascript/controllers/file_upload_controller.js
git commit -m "feat: add Stimulus controller for drag-and-drop file upload"
```

---

## Task 8: Redesign Episode Creation Form

**Files:**
- Modify: `hub/app/views/episodes/new.html.erb`

**Step 1: Replace episode form with new design**

Replace entire content of `hub/app/views/episodes/new.html.erb`:

```erb
<div class="max-w-2xl mx-auto">
  <h1 class="text-2xl font-semibold mb-8">Create New Episode</h1>

  <div class="border border-[var(--color-overlay0)] rounded-lg p-8">
    <%= form_with model: @episode, url: episodes_path, local: true, multipart: true, class: "space-y-6" do |f| %>
      <% if @episode.errors.any? %>
        <div class="border border-[var(--color-red)] rounded-lg p-4 bg-[var(--color-red)]/10">
          <p class="text-[var(--color-red)] font-medium mb-2">Please fix the following errors:</p>
          <ul class="list-disc list-inside text-sm text-[var(--color-red)]">
            <% @episode.errors.full_messages.each do |message| %>
              <li><%= message %></li>
            <% end %>
          </ul>
        </div>
      <% end %>

      <div>
        <%= f.label :title, class: "block text-sm font-medium mb-2" %>
        <%= f.text_field :title,
            class: "w-full bg-[var(--color-base)] border border-[var(--color-overlay0)] rounded-md px-3 py-2 focus:outline-none focus:border-[var(--color-primary)]",
            placeholder: "My Awesome Episode" %>
      </div>

      <div>
        <%= f.label :author, class: "block text-sm font-medium mb-2" %>
        <%= f.text_field :author,
            class: "w-full bg-[var(--color-base)] border border-[var(--color-overlay0)] rounded-md px-3 py-2 focus:outline-none focus:border-[var(--color-primary)]",
            placeholder: "Your Name" %>
      </div>

      <div>
        <%= f.label :description, class: "block text-sm font-medium mb-2" %>
        <%= f.text_area :description,
            rows: 3,
            class: "w-full bg-[var(--color-base)] border border-[var(--color-overlay0)] rounded-md px-3 py-2 focus:outline-none focus:border-[var(--color-primary)]",
            placeholder: "A brief description of this episode..." %>
      </div>

      <div data-controller="file-upload">
        <%= f.label :content, "Markdown Content", class: "block text-sm font-medium mb-2" %>
        <div
          data-file-upload-target="dropzone"
          data-action="click->file-upload#triggerInput dragover->file-upload#handleDragOver dragleave->file-upload#handleDragLeave drop->file-upload#handleDrop"
          class="border-2 border-dashed border-[var(--color-overlay0)] rounded-lg p-8 text-center cursor-pointer hover:border-[var(--color-primary)] transition-colors"
        >
          <%= f.file_field :content,
              accept: ".md,.markdown,.txt",
              data: { file_upload_target: "input", action: "change->file-upload#updateFilename" },
              class: "hidden" %>
          <p class="text-[var(--color-subtext)] mb-2">Click to upload .md file<br>or drag and drop</p>
          <p data-file-upload-target="filename" class="hidden text-sm font-medium text-[var(--color-primary)]"></p>
        </div>
      </div>

      <div class="flex items-center gap-4 pt-4">
        <%= f.submit "Create Episode",
            class: "bg-[var(--color-primary)] text-[var(--color-primary-text)] px-6 py-2 rounded-lg hover:bg-[var(--color-primary-hover)] font-medium cursor-pointer" %>
        <%= link_to "Cancel", episodes_path, class: "text-[var(--color-subtext)] hover:text-[var(--color-text)]" %>
      </div>
    <% end %>
  </div>
</div>
```

**Step 2: Verify form displays correctly**

Run: `cd /Users/jesse/code/tts/hub && bin/rails s`
Expected: Visit localhost:3000/episodes/new, see styled form with drag-and-drop area

**Step 3: Commit**

```bash
git add hub/app/views/episodes/new.html.erb
git commit -m "feat: redesign episode creation form with drag-and-drop upload"
```

---

## Task 9: Add Turbo Stream Support for Episode Status Updates

**Files:**
- Modify: `hub/app/models/episode.rb`
- Create: `hub/app/views/episodes/_episode_card.html.erb`
- Modify: `hub/app/views/episodes/index.html.erb`

**Step 1: Extract episode card to partial**

Create new file `hub/app/views/episodes/_episode_card.html.erb`:

```erb
<%= turbo_frame_tag dom_id(episode) do %>
  <div class="border border-[var(--color-overlay0)] rounded-lg p-4">
    <div class="mb-2">
      <%= status_badge(episode.status) %>
    </div>
    <h2 class="text-lg font-semibold mb-1"><%= episode.title %></h2>
    <div class="flex justify-between items-center text-sm text-[var(--color-subtext)]">
      <span>by <%= episode.author %></span>
      <span><%= episode.created_at.strftime("%b %d, %Y") %></span>
    </div>
  </div>
<% end %>
```

**Step 2: Update episodes index to use partial**

In `hub/app/views/episodes/index.html.erb`, replace the episodes loop section:

```erb
  <% if @episodes.any? %>
    <div class="space-y-4">
      <% @episodes.each do |episode| %>
        <%= render "episode_card", episode: episode %>
      <% end %>
    </div>
  <% else %>
```

**Step 3: Add broadcast callback to Episode model**

In `hub/app/models/episode.rb`, add after existing code:

```ruby
class Episode < ApplicationRecord
  belongs_to :podcast

  validates :title, :author, :description, presence: true
  validates :status, inclusion: { in: %w[pending processing complete failed] }

  scope :newest_first, -> { order(created_at: :desc) }

  # Broadcast updates when status changes
  after_update_commit :broadcast_status_change, if: :saved_change_to_status?

  private

  def broadcast_status_change
    broadcast_replace_to(
      "podcast_#{podcast_id}_episodes",
      target: self,
      partial: "episodes/episode_card",
      locals: { episode: self }
    )
  end
end
```

**Step 4: Subscribe to Turbo Stream in episodes index**

At the top of `hub/app/views/episodes/index.html.erb`, add:

```erb
<%= turbo_stream_from "podcast_#{@podcast.id}_episodes" %>

<div>
  <div class="flex justify-between items-start mb-8">
```

**Step 5: Verify Turbo Stream setup**

Run: `cd /Users/jesse/code/tts/hub && bin/rails s`
Expected: No errors, page loads with Turbo subscription

**Step 6: Commit**

```bash
git add hub/app/views/episodes/_episode_card.html.erb hub/app/views/episodes/index.html.erb hub/app/models/episode.rb
git commit -m "feat: add Turbo Streams for real-time episode status updates"
```

---

## Task 10: Add Dark Mode Toggle

**Files:**
- Create: `hub/app/javascript/controllers/theme_controller.js`
- Modify: `hub/app/views/shared/_header.html.erb`

**Step 1: Create theme controller**

Create new file `hub/app/javascript/controllers/theme_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["icon"]

  connect() {
    this.loadTheme()
  }

  toggle() {
    const isDark = document.documentElement.classList.toggle("dark")
    localStorage.setItem("theme", isDark ? "dark" : "light")
    this.updateIcon(isDark)
  }

  loadTheme() {
    const savedTheme = localStorage.getItem("theme")
    const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches
    const isDark = savedTheme === "dark" || (!savedTheme && prefersDark)

    if (isDark) {
      document.documentElement.classList.add("dark")
    }
    this.updateIcon(isDark)
  }

  updateIcon(isDark) {
    if (this.hasIconTarget) {
      this.iconTarget.textContent = isDark ? "☀️" : "🌙"
    }
  }
}
```

**Step 2: Add toggle button to header**

In `hub/app/views/shared/_header.html.erb`, update the authenticated section:

```erb
<header class="fixed top-0 left-0 right-0 bg-[var(--color-base)] border-b border-[var(--color-overlay0)] z-50" data-controller="theme">
  <div class="max-w-6xl mx-auto px-4 py-4 flex justify-between items-center">
    <div class="text-lg font-semibold">
      Very Normal TTS
    </div>
    <div class="flex items-center gap-4">
      <button
        data-action="click->theme#toggle"
        class="text-lg cursor-pointer hover:opacity-70"
        title="Toggle dark mode"
      >
        <span data-theme-target="icon">🌙</span>
      </button>
      <% if authenticated? %>
        <span class="text-sm text-[var(--color-subtext)]"><%= Current.user.email_address %></span>
        <%= button_to "Logout", session_path, method: :delete, class: "text-sm text-[var(--color-text)] hover:text-[var(--color-primary)] cursor-pointer" %>
      <% end %>
    </div>
  </div>
</header>
```

**Step 3: Verify dark mode toggle works**

Run: `cd /Users/jesse/code/tts/hub && bin/rails s`
Expected: Click toggle button, theme switches between light and dark, persists on reload

**Step 4: Commit**

```bash
git add hub/app/javascript/controllers/theme_controller.js hub/app/views/shared/_header.html.erb
git commit -m "feat: add dark mode toggle with localStorage persistence"
```

---

## Task 11: Add Flash Message Styling

**Files:**
- Create: `hub/app/views/shared/_flash.html.erb`
- Modify: `hub/app/views/layouts/application.html.erb`

**Step 1: Create flash partial**

Create new file `hub/app/views/shared/_flash.html.erb`:

```erb
<% if notice.present? %>
  <div class="bg-[var(--color-green)]/10 border border-[var(--color-green)] text-[var(--color-green)] px-4 py-3 rounded-lg mb-6">
    <%= notice %>
  </div>
<% end %>

<% if alert.present? %>
  <div class="bg-[var(--color-red)]/10 border border-[var(--color-red)] text-[var(--color-red)] px-4 py-3 rounded-lg mb-6">
    <%= alert %>
  </div>
<% end %>
```

**Step 2: Add flash rendering to layout**

In `hub/app/views/layouts/application.html.erb`, update the main section:

```erb
    <main class="max-w-6xl mx-auto mt-20 px-4 py-8">
      <%= render "shared/flash" %>
      <%= yield %>
    </main>
```

**Step 3: Verify flash messages display**

Run: `cd /Users/jesse/code/tts/hub && bin/rails s`
Expected: After login/logout actions, see styled flash messages

**Step 4: Commit**

```bash
git add hub/app/views/shared/_flash.html.erb hub/app/views/layouts/application.html.erb
git commit -m "feat: add styled flash message partial"
```

---

## Task 12: Update Controller Tests for New Views

**Files:**
- Modify: `hub/test/controllers/episodes_controller_test.rb`
- Modify: `hub/test/controllers/sessions_controller_test.rb`

**Step 1: Verify existing tests still pass**

Run: `cd /Users/jesse/code/tts/hub && bin/rails test test/controllers/`
Expected: All tests pass (views changed but controller behavior unchanged)

**Step 2: Add test for Turbo Stream subscription**

In `hub/test/controllers/episodes_controller_test.rb`, add:

```ruby
test "index page includes turbo stream subscription" do
  sign_in(@user)
  get episodes_url
  assert_response :success
  assert_select "turbo-cable-stream-source[channel='Turbo::StreamsChannel']"
end
```

**Step 3: Run updated tests**

Run: `cd /Users/jesse/code/tts/hub && bin/rails test test/controllers/episodes_controller_test.rb`
Expected: All tests pass

**Step 4: Commit**

```bash
git add hub/test/controllers/episodes_controller_test.rb
git commit -m "test: verify Turbo Stream subscription in episodes index"
```

---

## Task 13: Run Full Test Suite and Fix Any Issues

**Files:**
- Various (depends on failures)

**Step 1: Run all tests**

Run: `cd /Users/jesse/code/tts/hub && bin/rails test`
Expected: All tests pass

**Step 2: Run RuboCop**

Run: `cd /Users/jesse/code/tts/hub && bin/rubocop`
Expected: No offenses detected

**Step 3: Fix any issues found**

If tests fail or RuboCop reports issues, fix them.

**Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix: resolve test failures and linting issues"
```

---

## Task 14: Final Verification and Cleanup

**Files:**
- Possibly remove: `hub/app/views/pages/home.html.erb` (no longer needed)

**Step 1: Verify complete user flow**

1. Visit sign in page - should see styled centered form
2. Sign in - should redirect to episodes index
3. Episodes index - should show header with logout, episode cards (or empty state)
4. Create episode - should show styled form with drag-and-drop
5. Toggle dark mode - should switch themes and persist
6. Logout - should return to sign in page

**Step 2: Remove unused home page (optional)**

If `pages/home.html.erb` is no longer needed, remove it:

```bash
rm hub/app/views/pages/home.html.erb
```

Update routes to remove:
```ruby
# Remove this line from config/routes.rb
get "pages/home"
```

**Step 3: Final commit**

```bash
git add -A
git commit -m "chore: cleanup unused views and finalize redesign"
```

---

Plan complete and saved to `docs/plans/2025-11-16-frontend-redesign.md`. Two execution options:

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

Which approach?
