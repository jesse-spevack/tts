# URL Episode Error Messaging Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Display `error_message` on failed episode cards so users understand why their URL submission failed.

**Architecture:** Add a conditional block to the episode card partial that renders the error message when an episode has failed status and an error message exists.

**Tech Stack:** Rails ERB views, Minitest integration tests

---

## Task 1: Add Failed Episode Fixture

**Files:**
- Modify: `hub/test/fixtures/episodes.yml`

**Step 1: Add a failed episode fixture with error_message**

Add this fixture at the end of the file:

```yaml
failed_with_error:
  podcast: one
  user: one
  title: Failed Episode
  author: Test Author
  description: Test description
  status: failed
  error_message: This content is too long for your account tier
  audio_size_bytes: 0
  duration_seconds: 0
```

**Step 2: Commit**

```bash
git add hub/test/fixtures/episodes.yml
git commit -m "test: add failed episode fixture for error message testing"
```

---

## Task 2: Write Failing Test for Error Message Display

**Files:**
- Modify: `hub/test/controllers/episodes_controller_test.rb`

**Step 1: Write the failing test**

Add this test after the pagination tests (around line 335):

```ruby
# Failed episode error message tests

test "index displays error message for failed episodes" do
  # Use the failed_with_error fixture
  get episodes_url
  assert_response :success
  assert_includes response.body, "This content is too long for your account tier"
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/episodes_controller_test.rb:338 -v`

Expected: FAIL - the error message is not in the response body

**Step 3: Commit the failing test**

```bash
git add hub/test/controllers/episodes_controller_test.rb
git commit -m "test: add failing test for error message on failed episode card"
```

---

## Task 3: Implement Error Message Display

**Files:**
- Modify: `hub/app/views/episodes/_episode_card.html.erb:26`

**Step 1: Add the error message display**

After line 25 (`</div>` closing the status/actions row), add:

```erb
    <% if episode.failed? && episode.error_message.present? %>
      <p class="text-sm text-[var(--color-red)] mt-1"><%= episode.error_message %></p>
    <% end %>
```

The full context should look like:

```erb
      </div>
    </div>
    <% if episode.failed? && episode.error_message.present? %>
      <p class="text-sm text-[var(--color-red)] mt-1"><%= episode.error_message %></p>
    <% end %>
    <h2 class="text-lg font-semibold mb-1"><%= episode.title %></h2>
```

**Step 2: Run test to verify it passes**

Run: `bin/rails test test/controllers/episodes_controller_test.rb:338 -v`

Expected: PASS

**Step 3: Commit**

```bash
git add hub/app/views/episodes/_episode_card.html.erb
git commit -m "feat: display error message on failed episode cards"
```

---

## Task 4: Add Test for Non-Failed Episodes Don't Show Error

**Files:**
- Modify: `hub/test/controllers/episodes_controller_test.rb`

**Step 1: Write test to ensure error message styling doesn't appear for non-failed episodes**

Add this test after the previous one:

```ruby
test "index does not display error styling for completed episodes" do
  # Delete the failed episode so we only have completed ones
  Episode.where(status: :failed).delete_all

  get episodes_url
  assert_response :success

  # Should not contain the error message paragraph with red styling
  assert_no_match(/text-\[var\(--color-red\)\].*mt-1/, response.body)
end
```

**Step 2: Run test to verify it passes**

Run: `bin/rails test test/controllers/episodes_controller_test.rb -v`

Expected: PASS (all tests)

**Step 3: Commit**

```bash
git add hub/test/controllers/episodes_controller_test.rb
git commit -m "test: verify error message only shows for failed episodes"
```

---

## Task 5: Run Full Test Suite

**Step 1: Run all tests**

Run: `bin/rails test`

Expected: All tests pass

**Step 2: Final commit (if any cleanup needed)**

If all tests pass, the implementation is complete.
