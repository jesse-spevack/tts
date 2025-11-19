# Fix Episode Submission NoMethodError Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Prevent NoMethodError when episode content file is nil/missing by adding validation and user feedback

**Architecture:** Add nil guard in EpisodeSubmissionService before calling .read on uploaded_file, with clear error message returned to user

**Tech Stack:** Ruby on Rails 8, RSpec for testing

---

## Task 1: Add failing test for nil uploaded file

**Files:**
- Create: `test/services/episode_submission_service_test.rb`

**Step 1: Write the failing test**

Create test file with nil file handling test:

```ruby
require "test_helper"

class EpisodeSubmissionServiceTest < ActiveSupport::TestCase
  test "returns failure when uploaded file is nil" do
    podcast = podcasts(:one)
    params = {
      title: "Test Episode",
      author: "Test Author",
      description: "Test Description"
    }

    result = EpisodeSubmissionService.call(
      podcast: podcast,
      params: params,
      uploaded_file: nil
    )

    assert result.failure?
    assert_equal "No file uploaded", result.episode.error_message
    assert_equal "failed", result.episode.status
  end

  test "returns failure when uploaded file is missing read method" do
    podcast = podcasts(:one)
    params = {
      title: "Test Episode",
      author: "Test Author",
      description: "Test Description"
    }

    # Simulate an object without read method
    fake_file = Object.new

    result = EpisodeSubmissionService.call(
      podcast: podcast,
      params: params,
      uploaded_file: fake_file
    )

    assert result.failure?
    assert_match /file upload/i, result.episode.error_message
    assert_equal "failed", result.episode.status
  end
end
```

**Step 2: Run test to verify it fails**

Run: `rails test test/services/episode_submission_service_test.rb`

Expected: FAIL with NoMethodError or test failure

**Step 3: Add validation to EpisodeSubmissionService**

Modify `app/services/episode_submission_service.rb`:

```ruby
def upload_to_staging(episode)
  # Validate uploaded file exists and is readable
  unless uploaded_file.respond_to?(:read)
    raise ArgumentError, "Invalid file upload - file must be readable"
  end

  content = uploaded_file.read
  filename = "#{episode.id}-#{Time.now.to_i}.md"

  staging_path = gcs_uploader.upload_staging_file(content: content, filename: filename)

  Rails.logger.info "event=staging_uploaded episode_id=#{episode.id} staging_path=#{staging_path} size_bytes=#{content.bytesize}"

  staging_path
end
```

And update the call method to handle nil uploaded_file:

```ruby
def call
  # Validate uploaded file before building episode
  unless uploaded_file&.respond_to?(:read)
    episode = build_episode
    episode.status = "failed"
    episode.error_message = "No file uploaded"
    episode.save
    Rails.logger.error "event=episode_submission_failed episode_id=#{episode.id} error_class=ValidationError error_message=\"No file uploaded\""
    return Result.failure(episode)
  end

  episode = build_episode
  return Result.failure(episode) unless episode.save

  Rails.logger.info "event=episode_created episode_id=#{episode.id} podcast_id=#{podcast.podcast_id} user_id=#{podcast.users.first.id} title=\"#{episode.title}\""

  staging_path = upload_to_staging(episode)
  enqueue_processing(episode, staging_path)

  Result.success(episode)
rescue Google::Cloud::Error => e
  Rails.logger.error "event=gcs_upload_failed episode_id=#{episode&.id} error_class=#{e.class} error_message=\"#{e.message}\""
  episode&.update(status: "failed", error_message: "Failed to upload to staging: #{e.message}")
  Result.failure(episode)
rescue ArgumentError => e
  Rails.logger.error "event=episode_submission_failed episode_id=#{episode&.id} error_class=#{e.class} error_message=\"#{e.message}\""
  episode&.update(status: "failed", error_message: e.message)
  Result.failure(episode)
rescue StandardError => e
  Rails.logger.error "event=episode_submission_failed episode_id=#{episode&.id} error_class=#{e.class} error_message=\"#{e.message}\""
  episode&.update(status: "failed", error_message: e.message)
  Result.failure(episode)
end
```

**Step 4: Run test to verify it passes**

Run: `rails test test/services/episode_submission_service_test.rb`

Expected: PASS

**Step 5: Test with fixtures**

Verify fixtures exist or create them in `test/fixtures/podcasts.yml`:

```yaml
one:
  podcast_id: podcast_test_123
  created_at: <%= Time.now %>
  updated_at: <%= Time.now %>
```

Run: `rails test test/services/episode_submission_service_test.rb`

Expected: All tests PASS

**Step 6: Commit**

```bash
git add test/services/episode_submission_service_test.rb app/services/episode_submission_service.rb
git commit -m "fix: add validation for nil episode content file

Prevents NoMethodError when uploaded_file is nil or doesn't respond to read.
Returns clear error message to user instead of crashing.

Closes episode submission error for episode_id=14"
```

---

## Task 2: Add user-facing error message in controller

**Files:**
- Modify: `app/controllers/episodes_controller.rb:20-25`
- Test: `test/controllers/episodes_controller_test.rb`

**Step 1: Write failing controller test**

Create `test/controllers/episodes_controller_test.rb`:

```ruby
require "test_helper"

class EpisodesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @podcast = podcasts(:one)
    @user.podcasts << @podcast
    sign_in_as @user
  end

  test "create shows error when no file uploaded" do
    post episodes_path, params: {
      episode: {
        title: "Test Episode",
        author: "Test Author",
        description: "Test Description",
        content: nil
      }
    }

    assert_response :unprocessable_entity
    assert_select "p", text: /file/i
  end

  private

  def sign_in_as(user)
    post session_path, params: { email_address: user.email_address }
    # Follow authentication flow as needed
  end
end
```

**Step 2: Run test to verify behavior**

Run: `rails test test/controllers/episodes_controller_test.rb`

Expected: May need authentication setup adjustment

**Step 3: Update controller to show error**

Modify `app/controllers/episodes_controller.rb`:

```ruby
def create
  result = EpisodeSubmissionService.call(
    podcast: @podcast,
    params: episode_params,
    uploaded_file: params[:episode][:content]
  )

  if result.success?
    redirect_to episodes_path, notice: "Episode created! Processing..."
  else
    @episode = result.episode
    flash.now[:alert] = @episode.error_message if @episode.error_message
    render :new, status: :unprocessable_entity
  end
end
```

**Step 4: Update new episode form to show flash alerts**

Check `app/views/episodes/new.html.erb` has flash display (should already exist in layout)

**Step 5: Manual test**

Start server: `rails server`

Navigate to: http://localhost:3000/episodes/new

Submit form without file, verify error message displays

**Step 6: Commit**

```bash
git add app/controllers/episodes_controller.rb test/controllers/episodes_controller_test.rb
git commit -m "feat: display file upload errors to user

Shows clear error message when episode content file is missing
instead of silent failure"
```

---

## Task 3: Add client-side validation (optional enhancement)

**Files:**
- Modify: `app/views/episodes/new.html.erb`

**Step 1: Add required attribute to file input**

Find the file input field and add `required` attribute:

```erb
<%= form.file_field :content, required: true, accept: ".md,.txt" %>
```

**Step 2: Manual test**

Start server and verify browser prevents submission without file

**Step 3: Commit**

```bash
git add app/views/episodes/new.html.erb
git commit -m "feat: add client-side file upload validation

Prevents form submission without file, improves UX"
```

---

## Verification

**Run full test suite:**
```bash
rails test
```

Expected: All tests PASS

**Manual verification:**
1. Submit episode without file → see error message
2. Submit episode with file → processes normally
3. Check logs for proper error event logging

**Deployment:**
```bash
git push origin main
```
