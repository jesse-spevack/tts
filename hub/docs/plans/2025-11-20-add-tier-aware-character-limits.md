# Tier-Aware Character Limits Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement tier-aware character limits to prevent TTS cost overruns while preserving unlimited access for unlimited tier users.

**Architecture:** Create `EpisodeSubmissionValidator` service to provide user-specific limits based on tier. Modify `EpisodeSubmissionService` to accept and enforce character limits. Add client-side validation in Stimulus controller to disable submit button for files exceeding limits (non-unlimited users only).

**Tech Stack:** Rails 8, Minitest, Stimulus (Hotwired), TailwindCSS

**Context:** Following November 2025 incident where two 582KB files cost $373 in TTS API charges due to retry loops. Need safeguards that don't affect unlimited tier users.

---

## Task 1: Create EpisodeSubmissionValidator Service

**Files:**
- Create: `app/services/episode_submission_validator.rb`
- Create: `test/services/episode_submission_validator_test.rb`

**Step 1: Write the failing test**

Create `test/services/episode_submission_validator_test.rb`:

```ruby
require "test_helper"

class EpisodeSubmissionValidatorTest < ActiveSupport::TestCase
  test "returns nil max_characters for unlimited tier users" do
    user = users(:unlimited_user)

    result = EpisodeSubmissionValidator.call(user: user)

    assert_nil result.max_characters
    assert result.unlimited?
  end

  test "returns 10_000 max_characters for free tier users" do
    user = users(:free_user)

    result = EpisodeSubmissionValidator.call(user: user)

    assert_equal 10_000, result.max_characters
    assert_not result.unlimited?
  end

  test "returns 10_000 max_characters for basic tier users" do
    user = users(:basic_user)

    result = EpisodeSubmissionValidator.call(user: user)

    assert_equal 10_000, result.max_characters
    assert_not result.unlimited?
  end

  test "returns 10_000 max_characters for plus tier users" do
    user = users(:plus_user)

    result = EpisodeSubmissionValidator.call(user: user)

    assert_equal 10_000, result.max_characters
    assert_not result.unlimited?
  end

  test "returns 10_000 max_characters for premium tier users" do
    user = users(:premium_user)

    result = EpisodeSubmissionValidator.call(user: user)

    assert_equal 10_000, result.max_characters
    assert_not result.unlimited?
  end
end
```

**Step 2: Add test fixtures**

Add to `test/fixtures/users.yml`:

```yaml
free_user:
  email_address: free@example.com
  tier: 0  # free

basic_user:
  email_address: basic@example.com
  tier: 1  # basic

plus_user:
  email_address: plus@example.com
  tier: 2  # plus

premium_user:
  email_address: premium@example.com
  tier: 3  # premium

unlimited_user:
  email_address: unlimited@example.com
  tier: 4  # unlimited
```

**Step 3: Run tests to verify they fail**

Run: `bin/rails test test/services/episode_submission_validator_test.rb -v`

Expected: FAIL with "uninitialized constant EpisodeSubmissionValidator"

**Step 4: Implement the service**

Create `app/services/episode_submission_validator.rb`:

```ruby
class EpisodeSubmissionValidator
  MAX_CHARACTERS_DEFAULT = 10_000

  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    ValidationResult.success(
      max_characters: max_characters_for_user
    )
  end

  private

  attr_reader :user

  def max_characters_for_user
    return nil if user.unlimited?
    MAX_CHARACTERS_DEFAULT
  end

  class ValidationResult
    attr_reader :max_characters

    def self.success(max_characters:)
      new(max_characters: max_characters)
    end

    def initialize(max_characters:)
      @max_characters = max_characters
    end

    def unlimited?
      max_characters.nil?
    end
  end
end
```

**Step 5: Run tests to verify they pass**

Run: `bin/rails test test/services/episode_submission_validator_test.rb -v`

Expected: All tests PASS

**Step 6: Commit**

```bash
git add app/services/episode_submission_validator.rb test/services/episode_submission_validator_test.rb test/fixtures/users.yml
git commit -m "feat: add EpisodeSubmissionValidator service

Returns tier-based character limits. Unlimited users get nil (no limit),
all other tiers get 10,000 character limit to prevent TTS cost overruns."
```

---

## Task 2: Add Character Limit Enforcement to EpisodeSubmissionService

**Files:**
- Modify: `app/services/episode_submission_service.rb:6-12`
- Modify: `app/services/episode_submission_service.rb:14-23`
- Modify: `test/services/episode_submission_service_test.rb:157` (append new tests)

**Step 1: Write the failing tests**

Add to end of `test/services/episode_submission_service_test.rb`:

```ruby
  test "rejects file larger than max_characters when limit provided" do
    large_content = "a" * 10_001
    large_file = StringIO.new(large_content)

    result = EpisodeSubmissionService.new(
      podcast: @podcast,
      params: @params,
      uploaded_file: large_file,
      max_characters: 10_000,
      gcs_uploader: @mock_uploader,
      enqueuer: @mock_enqueuer
    ).call

    assert result.failure?
    assert_not result.episode.persisted?
    assert_includes result.episode.errors[:content].first, "too large"
    assert_includes result.episode.errors[:content].first, "10,001 characters"
    assert_includes result.episode.errors[:content].first, "10,000 characters"
  end

  test "accepts file with exactly max_characters" do
    @mock_uploader.define_singleton_method(:upload_staging_file) { |content:, filename:| "staging/#{filename}" }
    @mock_enqueuer.define_singleton_method(:enqueue_episode_processing) { |**args| nil }

    content = "a" * 10_000
    file = StringIO.new(content)

    result = EpisodeSubmissionService.new(
      podcast: @podcast,
      params: @params,
      uploaded_file: file,
      max_characters: 10_000,
      gcs_uploader: @mock_uploader,
      enqueuer: @mock_enqueuer
    ).call

    assert result.success?
    assert result.episode.persisted?
  end

  test "accepts file larger than 10k when max_characters is nil (unlimited)" do
    @mock_uploader.define_singleton_method(:upload_staging_file) { |content:, filename:| "staging/#{filename}" }
    @mock_enqueuer.define_singleton_method(:enqueue_episode_processing) { |**args| nil }

    large_content = "a" * 50_000
    large_file = StringIO.new(large_content)

    result = EpisodeSubmissionService.new(
      podcast: @podcast,
      params: @params,
      uploaded_file: large_file,
      max_characters: nil, # unlimited
      gcs_uploader: @mock_uploader,
      enqueuer: @mock_enqueuer
    ).call

    assert result.success?
    assert result.episode.persisted?
  end

  test "skips character limit check when max_characters not provided" do
    @mock_uploader.define_singleton_method(:upload_staging_file) { |content:, filename:| "staging/#{filename}" }
    @mock_enqueuer.define_singleton_method(:enqueue_episode_processing) { |**args| nil }

    large_content = "a" * 50_000
    large_file = StringIO.new(large_content)

    result = EpisodeSubmissionService.new(
      podcast: @podcast,
      params: @params,
      uploaded_file: large_file,
      gcs_uploader: @mock_uploader,
      enqueuer: @mock_enqueuer
    ).call

    assert result.success?
    assert result.episode.persisted?
  end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/episode_submission_service_test.rb -v`

Expected: 4 new tests FAIL (max_characters parameter not accepted, validation not implemented)

**Step 3: Modify service to accept max_characters parameter**

In `app/services/episode_submission_service.rb`, modify the `initialize` method (lines 6-12):

```ruby
  def initialize(podcast:, params:, uploaded_file:, max_characters: nil, gcs_uploader: nil, enqueuer: nil)
    @podcast = podcast
    @params = params
    @uploaded_file = uploaded_file
    @max_characters = max_characters
    @gcs_uploader = gcs_uploader
    @enqueuer = enqueuer
  end
```

Add to private attr_reader (line 45):

```ruby
  attr_reader :podcast, :params, :uploaded_file, :max_characters
```

**Step 4: Add character limit validation to call method**

In `app/services/episode_submission_service.rb`, modify the `call` method after the nil check (insert after line 22):

```ruby
  def call
    unless uploaded_file&.respond_to?(:read)
      episode = build_episode
      episode.status = "failed"
      episode.error_message = "No file uploaded"
      episode.save
      Rails.logger.error "event=episode_submission_failed episode_id=#{episode.id} error_class=ValidationError error_message=\"No file uploaded\""
      return Result.failure(episode)
    end

    # NEW: Character limit validation
    if max_characters
      content = uploaded_file.read
      uploaded_file.rewind # Important: allow subsequent reads

      if content.length > max_characters
        episode = build_episode
        episode.errors.add(
          :content,
          "is too large (#{content.length} characters). Maximum: #{max_characters} characters."
        )
        Rails.logger.info "event=file_size_rejected episode_title=\"#{params[:title]}\" size=#{content.length} limit=#{max_characters}"
        return Result.failure(episode)
      end
    end

    episode = build_episode
    return Result.failure(episode) unless episode.save

    # ... rest of existing code
  end
```

**Step 5: Run tests to verify they pass**

Run: `bin/rails test test/services/episode_submission_service_test.rb -v`

Expected: All tests PASS (including 4 new tests)

**Step 6: Commit**

```bash
git add app/services/episode_submission_service.rb test/services/episode_submission_service_test.rb
git commit -m "feat: add character limit enforcement to episode submission

Service now accepts optional max_characters parameter. When provided,
validates file size and rejects files exceeding limit. When nil or
omitted, skips validation (for unlimited tier users)."
```

---

## Task 3: Update EpisodesController to Use Validator

**Files:**
- Modify: `app/controllers/episodes_controller.rb:14-28`
- Modify: `test/controllers/episodes_controller_test.rb:1` (append new tests)

**Step 1: Write the failing tests**

Add to end of `test/controllers/episodes_controller_test.rb`:

```ruby
  test "enforces character limit for free tier users" do
    sign_in users(:free_user)

    large_content = "a" * 10_001
    file = fixture_file_upload(
      StringIO.new(large_content),
      "text/markdown",
      original_filename: "large.md"
    )

    assert_no_difference "Episode.count" do
      post episodes_url, params: {
        episode: {
          title: "Large Episode",
          author: "Test Author",
          description: "Test Description",
          content: file
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "p.text-\\[var\\(--color-red\\)\\]", text: /too large/i
  end

  test "allows unlimited tier users to upload large files" do
    sign_in users(:unlimited_user)

    large_content = "a" * 50_000
    file = fixture_file_upload(
      StringIO.new(large_content),
      "text/markdown",
      original_filename: "large.md"
    )

    mock_result = EpisodeSubmissionService::Result.success(
      episodes(:one)
    )

    EpisodeSubmissionService.stub :call, mock_result do
      assert_difference "Episode.count", 0 do # stubbed, no actual creation
        post episodes_url, params: {
          episode: {
            title: "Large Episode",
            author: "Test Author",
            description: "Test Description",
            content: file
          }
        }
      end
    end

    assert_redirected_to episodes_path
  end
```

**Step 2: Add helper method for fixture file upload**

Add to `test/test_helper.rb` if not already present:

```ruby
def fixture_file_upload(io, mime_type, original_filename:)
  uploaded_file = ActionDispatch::Http::UploadedFile.new(
    tempfile: io,
    type: mime_type,
    filename: original_filename
  )
  uploaded_file
end
```

**Step 3: Run tests to verify they fail**

Run: `bin/rails test test/controllers/episodes_controller_test.rb -v`

Expected: FAIL (controller doesn't use validator yet)

**Step 4: Modify controller to use validator**

In `app/controllers/episodes_controller.rb`, modify the `create` action (lines 14-28):

```ruby
  def create
    # Get user's character limit based on tier
    validation = EpisodeSubmissionValidator.call(user: Current.user)

    # Submit episode with tier-appropriate limits
    result = EpisodeSubmissionService.call(
      podcast: @podcast,
      params: episode_params,
      uploaded_file: params[:episode][:content],
      max_characters: validation.max_characters
    )

    if result.success?
      redirect_to episodes_path, notice: "Episode created! Processing..."
    else
      @episode = result.episode
      flash.now[:alert] = @episode.error_message if @episode.error_message

      # Show validation errors from service
      if @episode.errors[:content].any?
        flash.now[:alert] = @episode.errors[:content].first
      end

      render :new, status: :unprocessable_entity
    end
  end
```

**Step 5: Run tests to verify they pass**

Run: `bin/rails test test/controllers/episodes_controller_test.rb -v`

Expected: All tests PASS

**Step 6: Commit**

```bash
git add app/controllers/episodes_controller.rb test/controllers/episodes_controller_test.rb test/test_helper.rb
git commit -m "feat: integrate validator in episodes controller

Controller now gets user's character limit from EpisodeSubmissionValidator
and passes it to submission service. Unlimited users bypass limits,
other tiers have 10k character cap."
```

---

## Task 4: Add Helper Methods for View

**Files:**
- Modify: `app/helpers/episodes_helper.rb:1` (append new methods)
- Modify: `test/helpers/episodes_helper_test.rb:30` (append new tests)

**Step 1: Write the failing tests**

Add to end of `test/helpers/episodes_helper_test.rb`:

```ruby
  test "user_max_characters returns nil for unlimited users" do
    Current.user = users(:unlimited_user)

    assert_nil user_max_characters
  end

  test "user_max_characters returns 10_000 for free tier users" do
    Current.user = users(:free_user)

    assert_equal 10_000, user_max_characters
  end

  test "user_max_characters returns 10_000 for basic tier users" do
    Current.user = users(:basic_user)

    assert_equal 10_000, user_max_characters
  end

  test "show_character_limit? returns false for unlimited users" do
    Current.user = users(:unlimited_user)

    assert_not show_character_limit?
  end

  test "show_character_limit? returns true for free tier users" do
    Current.user = users(:free_user)

    assert show_character_limit?
  end

  test "show_character_limit? returns true for all non-unlimited tiers" do
    [users(:free_user), users(:basic_user), users(:plus_user), users(:premium_user)].each do |user|
      Current.user = user
      assert show_character_limit?, "Expected show_character_limit? to be true for #{user.tier} tier"
    end
  end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/helpers/episodes_helper_test.rb -v`

Expected: FAIL with "undefined method `user_max_characters`"

**Step 3: Implement helper methods**

Add to `app/helpers/episodes_helper.rb`:

```ruby
  def user_max_characters
    validator = EpisodeSubmissionValidator.call(user: Current.user)
    validator.max_characters
  end

  def show_character_limit?
    !Current.user.unlimited?
  end
```

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/helpers/episodes_helper_test.rb -v`

Expected: All tests PASS

**Step 5: Commit**

```bash
git add app/helpers/episodes_helper.rb test/helpers/episodes_helper_test.rb
git commit -m "feat: add helper methods for character limits

Helpers provide user_max_characters and show_character_limit? for views.
Unlimited users get nil limit and no UI, others get 10k limit with UI."
```

---

## Task 5: Update View with Conditional Character Limit UI

**Files:**
- Modify: `app/views/episodes/new.html.erb:39-54`

**Step 1: Add conditional character limit UI to view**

In `app/views/episodes/new.html.erb`, modify the file upload section (lines 39-54):

```erb
      <div data-controller="file-upload"
           <% if show_character_limit? %>
             data-file-upload-max-characters-value="<%= user_max_characters %>"
           <% end %>>
        <%= f.label :content, "Markdown Content", class: label_classes %>
        <div
          data-file-upload-target="dropzone"
          data-action="click->file-upload#triggerInput dragover->file-upload#handleDragOver dragleave->file-upload#handleDragLeave drop->file-upload#handleDrop"
          class="border-2 border-dashed border-[var(--color-overlay0)] rounded-lg p-8 text-center cursor-pointer hover:border-[var(--color-primary)] transition-colors"
        >
          <%= f.file_field :content,
              accept: ".md,.markdown,.txt",
              required: true,
              data: { file_upload_target: "input", action: "change->file-upload#updateFilename" },
              class: "hidden" %>
          <p class="text-[var(--color-subtext)] mb-2">Click to upload or drag and drop<br>(.md or .txt)</p>
          <p data-file-upload-target="filename" class="hidden text-sm font-medium text-[var(--color-primary)]"></p>
        </div>

        <% if show_character_limit? %>
          <div data-file-upload-target="validation" class="hidden mt-2">
            <p class="text-sm text-[var(--color-subtext)]">
              <span data-file-upload-target="charCount" class="font-medium"></span>
              / <%= number_with_delimiter(user_max_characters) %> characters
            </p>
            <p data-file-upload-target="error"
               class="text-[var(--color-red)] text-sm mt-1 hidden"></p>
          </div>
        <% end %>
      </div>
```

**Step 2: Test in browser**

Run: `bin/rails server`

Visit: `http://localhost:3000/episodes/new`

Expected (for non-unlimited user): Character count UI visible in HTML
Expected (for unlimited user): No character count UI, no data-file-upload-max-characters-value attribute

**Step 3: Commit**

```bash
git add app/views/episodes/new.html.erb
git commit -m "feat: add conditional character limit UI to episode form

Shows character count and limit only for non-unlimited users. Unlimited
users see no limit UI at all. Adds Stimulus targets for validation."
```

---

## Task 6: Enhance Stimulus Controller with Client-Side Validation

**Files:**
- Modify: `app/javascript/controllers/file_upload_controller.js:1-59`

**Step 1: Add Stimulus values and targets**

In `app/javascript/controllers/file_upload_controller.js`, modify the class definition:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "dropzone", "filename", "validation", "charCount", "error"]
  static values = { maxCharacters: Number }

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
    const acceptedExtensions = [".md", ".markdown", ".txt"]

    if (files.length > 0) {
      const file = files[0]
      const fileName = file.name.toLowerCase()
      const isAccepted = acceptedExtensions.some(ext => fileName.endsWith(ext))

      if (isAccepted) {
        this.inputTarget.files = files
        this.updateFilename()
      } else {
        // Show error feedback
        this.dropzoneTarget.classList.add("border-[var(--color-red)]")
        setTimeout(() => {
          this.dropzoneTarget.classList.remove("border-[var(--color-red)]")
        }, 2000)
      }
    }
  }

  async updateFilename() {
    if (this.inputTarget.files.length > 0) {
      const file = this.inputTarget.files[0]
      this.filenameTarget.textContent = file.name
      this.filenameTarget.classList.remove("hidden")

      // Validate file size if limit exists
      if (this.hasMaxCharactersValue) {
        await this.validateFileSize(file)
      }
    } else {
      this.filenameTarget.classList.add("hidden")
      if (this.hasValidationTarget) {
        this.validationTarget.classList.add("hidden")
      }
    }
  }

  async validateFileSize(file) {
    try {
      const text = await file.text()
      const charCount = text.length

      // Show character count
      this.charCountTarget.textContent = charCount.toLocaleString()
      this.validationTarget.classList.remove("hidden")

      // Check if over limit
      if (charCount > this.maxCharactersValue) {
        const overage = charCount - this.maxCharactersValue
        this.errorTarget.textContent = `File exceeds limit by ${overage.toLocaleString()} characters`
        this.errorTarget.classList.remove("hidden")
        this.disableSubmit()
      } else {
        this.errorTarget.classList.add("hidden")
        this.enableSubmit()
      }
    } catch (error) {
      console.error("Error reading file:", error)
      // On error, enable submit and let server-side validation handle it
      this.enableSubmit()
    }
  }

  disableSubmit() {
    const submitButton = this.element.closest("form").querySelector("[type=submit]")
    if (submitButton) {
      submitButton.disabled = true
      submitButton.classList.add("opacity-50", "cursor-not-allowed")
    }
  }

  enableSubmit() {
    const submitButton = this.element.closest("form").querySelector("[type=submit]")
    if (submitButton) {
      submitButton.disabled = false
      submitButton.classList.remove("opacity-50", "cursor-not-allowed")
    }
  }
}
```

**Step 2: Test in browser with non-unlimited user**

1. Sign in as free tier user
2. Visit `/episodes/new`
3. Select file under 10,000 characters
   - Expected: Character count shown, submit button enabled
4. Select file over 10,000 characters
   - Expected: Error message shown, submit button disabled

**Step 3: Test in browser with unlimited user**

1. Sign in as unlimited tier user
2. Visit `/episodes/new`
3. Select large file (50,000+ characters)
   - Expected: No character count shown, submit button enabled

**Step 4: Commit**

```bash
git add app/javascript/controllers/file_upload_controller.js
git commit -m "feat: add client-side character limit validation

Reads file content on selection and validates character count against
user's tier limit. Disables submit button if over limit. Only validates
for non-unlimited users. Falls back to server validation on errors."
```

---

## Task 7: Integration Testing

**Files:**
- Create: `test/integration/episode_submission_with_limits_test.rb`

**Step 1: Write integration test**

Create `test/integration/episode_submission_with_limits_test.rb`:

```ruby
require "test_helper"

class EpisodeSubmissionWithLimitsTest < ActionDispatch::IntegrationTest
  test "free tier user cannot submit file over 10k characters" do
    sign_in users(:free_user)

    large_content = "a" * 10_001

    post episodes_url, params: {
      episode: {
        title: "Test Episode",
        author: "Test Author",
        description: "Test Description",
        content: fixture_file_upload(
          StringIO.new(large_content),
          "text/markdown",
          original_filename: "large.md"
        )
      }
    }

    assert_response :unprocessable_entity
    assert_select ".text-\\[var\\(--color-red\\)\\]", text: /too large/i
  end

  test "unlimited tier user can submit file over 10k characters" do
    sign_in users(:unlimited_user)
    podcast = podcasts(:one)
    podcast.users << users(:unlimited_user)

    large_content = "# Large Content\n\n" + ("a" * 50_000)

    mock_uploader = Minitest::Mock.new
    mock_uploader.expect :upload_staging_file, "staging/test.md", [Hash]

    mock_enqueuer = Minitest::Mock.new
    mock_enqueuer.expect :enqueue_episode_processing, "task-123", [Hash]

    GcsUploader.stub :new, mock_uploader do
      CloudTasksEnqueuer.stub :new, mock_enqueuer do
        assert_difference "Episode.count", 1 do
          post episodes_url, params: {
            episode: {
              title: "Large Episode",
              author: "Test Author",
              description: "Test Description",
              content: fixture_file_upload(
                StringIO.new(large_content),
                "text/markdown",
                original_filename: "large.md"
              )
            }
          }
        end
      end
    end

    assert_redirected_to episodes_path
    follow_redirect!
    assert_select ".notice", text: /created/i

    mock_uploader.verify
    mock_enqueuer.verify
  end

  test "free tier user can submit file at exactly 10k characters" do
    sign_in users(:free_user)
    podcast = podcasts(:one)
    podcast.users << users(:free_user)

    content = "a" * 10_000

    mock_uploader = Minitest::Mock.new
    mock_uploader.expect :upload_staging_file, "staging/test.md", [Hash]

    mock_enqueuer = Minitest::Mock.new
    mock_enqueuer.expect :enqueue_episode_processing, "task-123", [Hash]

    GcsUploader.stub :new, mock_uploader do
      CloudTasksEnqueuer.stub :new, mock_enqueuer do
        assert_difference "Episode.count", 1 do
          post episodes_url, params: {
            episode: {
              title: "At Limit Episode",
              author: "Test Author",
              description: "Test Description",
              content: fixture_file_upload(
                StringIO.new(content),
                "text/markdown",
                original_filename: "at-limit.md"
              )
            }
          }
        end
      end
    end

    assert_redirected_to episodes_path

    mock_uploader.verify
    mock_enqueuer.verify
  end
end
```

**Step 2: Run integration tests**

Run: `bin/rails test test/integration/episode_submission_with_limits_test.rb -v`

Expected: All integration tests PASS

**Step 3: Commit**

```bash
git add test/integration/episode_submission_with_limits_test.rb
git commit -m "test: add integration tests for tier-aware limits

Tests complete flow from submission to validation for different tiers.
Verifies unlimited users bypass limits and free tier users are blocked."
```

---

## Task 8: Run Full Test Suite

**Step 1: Run all tests**

Run: `bin/rails test`

Expected: All tests PASS

**Step 2: Check for any deprecation warnings or issues**

Review test output for any warnings or unexpected behavior.

**Step 3: If all tests pass, commit**

```bash
git add .
git commit -m "chore: verify all tests pass with new tier-aware limits" --allow-empty
```

---

## Verification Checklist

After completing all tasks:

- [ ] `EpisodeSubmissionValidator` returns correct limits for each tier
- [ ] Service enforces character limits when provided
- [ ] Service skips validation when `max_characters` is nil
- [ ] Controller integrates validator and passes limits to service
- [ ] Helper methods return correct values for different tiers
- [ ] View conditionally shows character limit UI
- [ ] Client-side validation disables submit for oversized files
- [ ] Unlimited users see no character count UI
- [ ] Free tier users cannot submit files over 10k characters
- [ ] All tests pass

---

## Manual Testing Steps

**As Free Tier User:**
1. Visit `/episodes/new`
2. Upload 5k character file → Should see "5,000 / 10,000 characters", submit enabled
3. Upload 10,001 character file → Should see error "exceeds limit by 1 character", submit disabled
4. Try to submit anyway (via browser dev tools) → Server should reject with error message

**As Unlimited User:**
1. Visit `/episodes/new`
2. Upload 50k character file → Should see no character count, submit enabled
3. Submit successfully → Episode should be created and queued for processing

---

## Cost Impact Analysis

**Before:**
- No limits on file size
- 582KB file = ~515,000 characters
- Cost per episode (Chirp3-HD): $15.45
- With 13 retries: $200.85 per episode
- Incident total: $373

**After (Free Tier Users):**
- 10,000 character limit enforced
- Cost per episode (Chirp3-HD): $0.30 (within free tier if first of month)
- Max cost per episode: $0.30
- **97% cost reduction for typical use cases**

**After (Unlimited Users):**
- No change - unlimited access preserved
- Business use cases unaffected
