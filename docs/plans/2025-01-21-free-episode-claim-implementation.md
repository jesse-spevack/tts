# Free Episode Claim Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Allow free tier users to create exactly 1 free episode, with claim released if processing fails.

**Architecture:** New `free_episode_claims` table tracks claims per user/episode. Three services handle eligibility check, claiming, and releasing. Controller integration gates access and triggers claim/release.

**Tech Stack:** Rails 8.1, SQLite, Minitest

---

## Task 1: Create Migration for free_episode_claims Table

**Files:**
- Create: `hub/db/migrate/YYYYMMDDHHMMSS_create_free_episode_claims.rb`

**Step 1: Generate the migration**

Run:
```bash
cd hub && bin/rails generate migration CreateFreeEpisodeClaims user:references episode:references claimed_at:datetime released_at:datetime
```

**Step 2: Edit the migration to add not-null constraint on claimed_at**

Open the generated migration and ensure it looks like:

```ruby
class CreateFreeEpisodeClaims < ActiveRecord::Migration[8.1]
  def change
    create_table :free_episode_claims do |t|
      t.references :user, null: false, foreign_key: true
      t.references :episode, null: false, foreign_key: true
      t.datetime :claimed_at, null: false
      t.datetime :released_at

      t.timestamps
    end
  end
end
```

**Step 3: Run the migration**

Run:
```bash
cd hub && bin/rails db:migrate
```

Expected: Migration runs successfully, schema.rb updated with `free_episode_claims` table.

**Step 4: Commit**

```bash
git add hub/db/migrate/*_create_free_episode_claims.rb hub/db/schema.rb
git commit -m "feat: add free_episode_claims table"
```

---

## Task 2: Create FreeEpisodeClaim Model

**Files:**
- Create: `hub/app/models/free_episode_claim.rb`
- Create: `hub/test/models/free_episode_claim_test.rb`

**Step 1: Write the failing test**

Create `hub/test/models/free_episode_claim_test.rb`:

```ruby
require "test_helper"

class FreeEpisodeClaimTest < ActiveSupport::TestCase
  setup do
    @user = users(:free_user)
    @podcast = Podcast.create!(podcast_id: SecureRandom.uuid, title: "Test Podcast")
    @podcast.users << @user
    @episode = @podcast.episodes.create!(
      title: "Test Episode",
      author: "Author",
      description: "Description"
    )
  end

  test "belongs to user" do
    claim = FreeEpisodeClaim.create!(
      user: @user,
      episode: @episode,
      claimed_at: Time.current
    )

    assert_equal @user, claim.user
  end

  test "belongs to episode" do
    claim = FreeEpisodeClaim.create!(
      user: @user,
      episode: @episode,
      claimed_at: Time.current
    )

    assert_equal @episode, claim.episode
  end

  test "active scope returns claims without released_at" do
    active_claim = FreeEpisodeClaim.create!(
      user: @user,
      episode: @episode,
      claimed_at: Time.current
    )

    other_user = users(:basic_user)
    other_episode = @podcast.episodes.create!(
      title: "Other Episode",
      author: "Author",
      description: "Description"
    )
    released_claim = FreeEpisodeClaim.create!(
      user: other_user,
      episode: other_episode,
      claimed_at: 1.hour.ago,
      released_at: Time.current
    )

    assert_includes FreeEpisodeClaim.active, active_claim
    assert_not_includes FreeEpisodeClaim.active, released_claim
  end

  test "requires user" do
    claim = FreeEpisodeClaim.new(episode: @episode, claimed_at: Time.current)
    assert_not claim.valid?
    assert_includes claim.errors[:user], "must exist"
  end

  test "requires episode" do
    claim = FreeEpisodeClaim.new(user: @user, claimed_at: Time.current)
    assert_not claim.valid?
    assert_includes claim.errors[:episode], "must exist"
  end

  test "requires claimed_at" do
    claim = FreeEpisodeClaim.new(user: @user, episode: @episode)
    assert_not claim.valid?
    assert_includes claim.errors[:claimed_at], "can't be blank"
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
cd hub && bin/rails test test/models/free_episode_claim_test.rb
```

Expected: FAIL with "uninitialized constant FreeEpisodeClaim"

**Step 3: Write the model**

Create `hub/app/models/free_episode_claim.rb`:

```ruby
class FreeEpisodeClaim < ApplicationRecord
  belongs_to :user
  belongs_to :episode

  validates :claimed_at, presence: true

  scope :active, -> { where(released_at: nil) }
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
cd hub && bin/rails test test/models/free_episode_claim_test.rb
```

Expected: All tests PASS

**Step 5: Commit**

```bash
git add hub/app/models/free_episode_claim.rb hub/test/models/free_episode_claim_test.rb
git commit -m "feat: add FreeEpisodeClaim model with active scope"
```

---

## Task 3: Create CanClaimFreeEpisode Service

**Files:**
- Create: `hub/app/services/can_claim_free_episode.rb`
- Create: `hub/test/services/can_claim_free_episode_test.rb`

**Step 1: Write the failing test**

Create `hub/test/services/can_claim_free_episode_test.rb`:

```ruby
require "test_helper"

class CanClaimFreeEpisodeTest < ActiveSupport::TestCase
  setup do
    @free_user = users(:free_user)
    @basic_user = users(:basic_user)
    @unlimited_user = users(:unlimited_user)
  end

  test "returns true for non-free tier user" do
    assert CanClaimFreeEpisode.call(user: @basic_user)
    assert CanClaimFreeEpisode.call(user: @unlimited_user)
  end

  test "returns true for free tier user with no claims" do
    assert CanClaimFreeEpisode.call(user: @free_user)
  end

  test "returns false for free tier user with active claim" do
    podcast = Podcast.create!(podcast_id: SecureRandom.uuid, title: "Test")
    podcast.users << @free_user
    episode = podcast.episodes.create!(
      title: "Test",
      author: "Author",
      description: "Desc"
    )
    FreeEpisodeClaim.create!(
      user: @free_user,
      episode: episode,
      claimed_at: Time.current
    )

    assert_not CanClaimFreeEpisode.call(user: @free_user)
  end

  test "returns true for free tier user with only released claims" do
    podcast = Podcast.create!(podcast_id: SecureRandom.uuid, title: "Test")
    podcast.users << @free_user
    episode = podcast.episodes.create!(
      title: "Test",
      author: "Author",
      description: "Desc"
    )
    FreeEpisodeClaim.create!(
      user: @free_user,
      episode: episode,
      claimed_at: 1.hour.ago,
      released_at: Time.current
    )

    assert CanClaimFreeEpisode.call(user: @free_user)
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
cd hub && bin/rails test test/services/can_claim_free_episode_test.rb
```

Expected: FAIL with "uninitialized constant CanClaimFreeEpisode"

**Step 3: Write the service**

Create `hub/app/services/can_claim_free_episode.rb`:

```ruby
class CanClaimFreeEpisode
  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    return true unless user.free?

    !FreeEpisodeClaim.active.exists?(user: user)
  end

  private

  attr_reader :user
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
cd hub && bin/rails test test/services/can_claim_free_episode_test.rb
```

Expected: All tests PASS

**Step 5: Commit**

```bash
git add hub/app/services/can_claim_free_episode.rb hub/test/services/can_claim_free_episode_test.rb
git commit -m "feat: add CanClaimFreeEpisode service"
```

---

## Task 4: Create ClaimFreeEpisode Service

**Files:**
- Create: `hub/app/services/claim_free_episode.rb`
- Create: `hub/test/services/claim_free_episode_test.rb`

**Step 1: Write the failing test**

Create `hub/test/services/claim_free_episode_test.rb`:

```ruby
require "test_helper"

class ClaimFreeEpisodeTest < ActiveSupport::TestCase
  setup do
    @free_user = users(:free_user)
    @basic_user = users(:basic_user)
    @podcast = Podcast.create!(podcast_id: SecureRandom.uuid, title: "Test")
    @podcast.users << @free_user
    @episode = @podcast.episodes.create!(
      title: "Test",
      author: "Author",
      description: "Desc"
    )
  end

  test "creates claim for free tier user" do
    result = ClaimFreeEpisode.call(user: @free_user, episode: @episode)

    assert_instance_of FreeEpisodeClaim, result
    assert_equal @free_user, result.user
    assert_equal @episode, result.episode
    assert_not_nil result.claimed_at
    assert_nil result.released_at
  end

  test "returns nil for non-free tier user" do
    result = ClaimFreeEpisode.call(user: @basic_user, episode: @episode)

    assert_nil result
    assert_equal 0, FreeEpisodeClaim.count
  end

  test "persists the claim to database" do
    assert_difference "FreeEpisodeClaim.count", 1 do
      ClaimFreeEpisode.call(user: @free_user, episode: @episode)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
cd hub && bin/rails test test/services/claim_free_episode_test.rb
```

Expected: FAIL with "uninitialized constant ClaimFreeEpisode"

**Step 3: Write the service**

Create `hub/app/services/claim_free_episode.rb`:

```ruby
class ClaimFreeEpisode
  def self.call(user:, episode:)
    new(user: user, episode: episode).call
  end

  def initialize(user:, episode:)
    @user = user
    @episode = episode
  end

  def call
    return nil unless user.free?

    FreeEpisodeClaim.create!(
      user: user,
      episode: episode,
      claimed_at: Time.current
    )
  end

  private

  attr_reader :user, :episode
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
cd hub && bin/rails test test/services/claim_free_episode_test.rb
```

Expected: All tests PASS

**Step 5: Commit**

```bash
git add hub/app/services/claim_free_episode.rb hub/test/services/claim_free_episode_test.rb
git commit -m "feat: add ClaimFreeEpisode service"
```

---

## Task 5: Create ReleaseFreeEpisodeClaim Service

**Files:**
- Create: `hub/app/services/release_free_episode_claim.rb`
- Create: `hub/test/services/release_free_episode_claim_test.rb`

**Step 1: Write the failing test**

Create `hub/test/services/release_free_episode_claim_test.rb`:

```ruby
require "test_helper"

class ReleaseFreeEpisodeClaimTest < ActiveSupport::TestCase
  setup do
    @free_user = users(:free_user)
    @podcast = Podcast.create!(podcast_id: SecureRandom.uuid, title: "Test")
    @podcast.users << @free_user
    @episode = @podcast.episodes.create!(
      title: "Test",
      author: "Author",
      description: "Desc"
    )
  end

  test "releases active claim for episode" do
    claim = FreeEpisodeClaim.create!(
      user: @free_user,
      episode: @episode,
      claimed_at: Time.current
    )

    result = ReleaseFreeEpisodeClaim.call(episode: @episode)

    assert_equal claim, result
    assert_not_nil result.released_at
  end

  test "returns nil when no active claim exists" do
    result = ReleaseFreeEpisodeClaim.call(episode: @episode)

    assert_nil result
  end

  test "returns nil when claim already released" do
    FreeEpisodeClaim.create!(
      user: @free_user,
      episode: @episode,
      claimed_at: 1.hour.ago,
      released_at: 30.minutes.ago
    )

    result = ReleaseFreeEpisodeClaim.call(episode: @episode)

    assert_nil result
  end

  test "is idempotent - calling twice is safe" do
    FreeEpisodeClaim.create!(
      user: @free_user,
      episode: @episode,
      claimed_at: Time.current
    )

    first_result = ReleaseFreeEpisodeClaim.call(episode: @episode)
    second_result = ReleaseFreeEpisodeClaim.call(episode: @episode)

    assert_not_nil first_result
    assert_nil second_result
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
cd hub && bin/rails test test/services/release_free_episode_claim_test.rb
```

Expected: FAIL with "uninitialized constant ReleaseFreeEpisodeClaim"

**Step 3: Write the service**

Create `hub/app/services/release_free_episode_claim.rb`:

```ruby
class ReleaseFreeEpisodeClaim
  def self.call(episode:)
    new(episode: episode).call
  end

  def initialize(episode:)
    @episode = episode
  end

  def call
    claim = FreeEpisodeClaim.active.find_by(episode: episode)
    return nil unless claim

    claim.update!(released_at: Time.current)
    claim
  end

  private

  attr_reader :episode
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
cd hub && bin/rails test test/services/release_free_episode_claim_test.rb
```

Expected: All tests PASS

**Step 5: Commit**

```bash
git add hub/app/services/release_free_episode_claim.rb hub/test/services/release_free_episode_claim_test.rb
git commit -m "feat: add ReleaseFreeEpisodeClaim service"
```

---

## Task 6: Update EpisodesController with Free Episode Gating

**Files:**
- Modify: `hub/app/controllers/episodes_controller.rb`
- Modify: `hub/test/controllers/episodes_controller_test.rb`

**Step 1: Write the failing tests**

Add to `hub/test/controllers/episodes_controller_test.rb`:

```ruby
test "allows free tier user to access new when no claim exists" do
  sign_in_as users(:free_user)

  get new_episode_url

  assert_response :success
end

test "redirects free tier user from new when claim exists" do
  free_user = users(:free_user)
  sign_in_as free_user

  podcast = Podcast.create!(podcast_id: SecureRandom.uuid, title: "Test")
  podcast.users << free_user
  episode = podcast.episodes.create!(title: "Test", author: "A", description: "D")
  FreeEpisodeClaim.create!(user: free_user, episode: episode, claimed_at: Time.current)

  get new_episode_url

  assert_redirected_to episodes_path
  assert_equal "Upgrade to create more episodes.", flash[:alert]
end

test "allows free tier user to create when no claim exists" do
  free_user = users(:free_user)
  sign_in_as free_user

  file = Rack::Test::UploadedFile.new(
    StringIO.new("# Test Content"),
    "text/markdown",
    original_filename: "test.md"
  )

  mock_episode = Episode.new(title: "Test", author: "A", description: "D")
  mock_episode.id = 999
  mock_result = EpisodeSubmissionService::Result.success(mock_episode)

  EpisodeSubmissionService.stub :call, mock_result do
    post episodes_url, params: {
      episode: { title: "Test", author: "A", description: "D", content: file }
    }
  end

  assert_redirected_to episodes_path
end

test "redirects free tier user from create when claim exists" do
  free_user = users(:free_user)
  sign_in_as free_user

  podcast = Podcast.create!(podcast_id: SecureRandom.uuid, title: "Test")
  podcast.users << free_user
  episode = podcast.episodes.create!(title: "Test", author: "A", description: "D")
  FreeEpisodeClaim.create!(user: free_user, episode: episode, claimed_at: Time.current)

  file = Rack::Test::UploadedFile.new(
    StringIO.new("# Test Content"),
    "text/markdown",
    original_filename: "test.md"
  )

  post episodes_url, params: {
    episode: { title: "Test", author: "A", description: "D", content: file }
  }

  assert_redirected_to episodes_path
  assert_equal "Upgrade to create more episodes.", flash[:alert]
end

test "creates claim after successful submission for free tier user" do
  free_user = users(:free_user)
  sign_in_as free_user

  file = Rack::Test::UploadedFile.new(
    StringIO.new("# Test Content"),
    "text/markdown",
    original_filename: "test.md"
  )

  podcast = Podcast.create!(podcast_id: SecureRandom.uuid, title: "Test")
  podcast.users << free_user
  episode = podcast.episodes.create!(title: "Test", author: "A", description: "D")
  mock_result = EpisodeSubmissionService::Result.success(episode)

  assert_difference "FreeEpisodeClaim.count", 1 do
    EpisodeSubmissionService.stub :call, mock_result do
      post episodes_url, params: {
        episode: { title: "Test", author: "A", description: "D", content: file }
      }
    end
  end

  claim = FreeEpisodeClaim.last
  assert_equal free_user, claim.user
  assert_equal episode, claim.episode
end

test "does not create claim for non-free tier user" do
  sign_in_as users(:unlimited_user)

  file = Rack::Test::UploadedFile.new(
    StringIO.new("# Test Content"),
    "text/markdown",
    original_filename: "test.md"
  )

  mock_episode = Episode.new(title: "Test", author: "A", description: "D")
  mock_episode.id = 999
  mock_result = EpisodeSubmissionService::Result.success(mock_episode)

  assert_no_difference "FreeEpisodeClaim.count" do
    EpisodeSubmissionService.stub :call, mock_result do
      post episodes_url, params: {
        episode: { title: "Test", author: "A", description: "D", content: file }
      }
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run:
```bash
cd hub && bin/rails test test/controllers/episodes_controller_test.rb
```

Expected: New tests FAIL (existing tests may also fail due to submission access changes)

**Step 3: Update the controller**

Replace `hub/app/controllers/episodes_controller.rb`:

```ruby
class EpisodesController < ApplicationController
  before_action :require_authentication
  before_action :require_free_episode_available, only: [ :new, :create ]
  before_action :load_podcast

  def index
    @episodes = @podcast.episodes.newest_first
  end

  def new
    @episode = @podcast.episodes.build
  end

  def create
    validation = EpisodeSubmissionValidator.call(user: Current.user)

    result = EpisodeSubmissionService.call(
      podcast: @podcast,
      params: episode_params,
      uploaded_file: params[:episode][:content],
      max_characters: validation.max_characters,
      voice_name: Current.user.voice_name
    )

    if result.success?
      ClaimFreeEpisode.call(user: Current.user, episode: result.episode)
      redirect_to episodes_path, notice: "Episode created! Processing..."
    else
      @episode = result.episode
      flash.now[:alert] = @episode.error_message if @episode.error_message

      if @episode.errors[:content].any?
        flash.now[:alert] = @episode.errors[:content].first
      end

      render :new, status: :unprocessable_entity
    end
  end

  private

  def require_free_episode_available
    return unless Current.user.free?
    return if CanClaimFreeEpisode.call(user: Current.user)

    flash[:alert] = "Upgrade to create more episodes."
    redirect_to episodes_path
  end

  def load_podcast
    @podcast = Current.user.podcasts.first
    @podcast ||= CreateDefaultPodcast.call(user: Current.user)
  end

  def episode_params
    params.require(:episode).permit(:title, :author, :description, :content)
  end
end
```

**Step 4: Run tests to verify they pass**

Run:
```bash
cd hub && bin/rails test test/controllers/episodes_controller_test.rb
```

Expected: All tests PASS

**Step 5: Commit**

```bash
git add hub/app/controllers/episodes_controller.rb hub/test/controllers/episodes_controller_test.rb
git commit -m "feat: add free episode gating to EpisodesController"
```

---

## Task 7: Update Internal Episodes Controller to Release Claims on Failure

**Files:**
- Modify: `hub/app/controllers/api/internal/episodes_controller.rb`
- Modify: `hub/test/controllers/api/internal/episodes_controller_test.rb`

**Step 1: Write the failing test**

Add to `hub/test/controllers/api/internal/episodes_controller_test.rb`:

```ruby
test "releases free episode claim when status is failed" do
  free_user = users(:free_user)
  @podcast.users << free_user
  claim = FreeEpisodeClaim.create!(
    user: free_user,
    episode: @episode,
    claimed_at: Time.current
  )

  patch api_internal_episode_url(@episode),
    params: {
      status: "failed",
      error_message: "Processing failed"
    }.to_json,
    headers: {
      "Content-Type" => "application/json",
      "X-Generator-Secret" => @secret
    }

  assert_response :success
  claim.reload
  assert_not_nil claim.released_at
end

test "does not release claim when status is complete" do
  free_user = users(:free_user)
  @podcast.users << free_user
  claim = FreeEpisodeClaim.create!(
    user: free_user,
    episode: @episode,
    claimed_at: Time.current
  )

  patch api_internal_episode_url(@episode),
    params: {
      status: "complete",
      gcs_episode_id: "abc123"
    }.to_json,
    headers: {
      "Content-Type" => "application/json",
      "X-Generator-Secret" => @secret
    }

  assert_response :success
  claim.reload
  assert_nil claim.released_at
end

test "handles failure update when no claim exists" do
  patch api_internal_episode_url(@episode),
    params: {
      status: "failed",
      error_message: "Processing failed"
    }.to_json,
    headers: {
      "Content-Type" => "application/json",
      "X-Generator-Secret" => @secret
    }

  assert_response :success
  @episode.reload
  assert_equal "failed", @episode.status
end
```

**Step 2: Run tests to verify they fail**

Run:
```bash
cd hub && bin/rails test test/controllers/api/internal/episodes_controller_test.rb
```

Expected: New tests FAIL (release service not called)

**Step 3: Update the controller**

Edit `hub/app/controllers/api/internal/episodes_controller.rb`:

```ruby
module Api
  module Internal
    class EpisodesController < BaseController
      before_action :set_episode

      def update
        if @episode.update(episode_params)
          ReleaseFreeEpisodeClaim.call(episode: @episode) if @episode.failed?
          Rails.logger.info "event=episode_callback_received episode_id=#{@episode.id} status=#{@episode.status}"
          render json: { status: "success" }
        else
          render json: { status: "error", errors: @episode.errors.full_messages }, status: :unprocessable_entity
        end
      rescue ArgumentError => e
        render json: { status: "error", message: e.message }, status: :unprocessable_entity
      end

      private

      def set_episode
        @episode = Episode.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { status: "error", message: "Episode not found" }, status: :not_found
      end

      def episode_params
        params.permit(:status, :gcs_episode_id, :audio_size_bytes, :error_message)
      end
    end
  end
end
```

**Step 4: Run tests to verify they pass**

Run:
```bash
cd hub && bin/rails test test/controllers/api/internal/episodes_controller_test.rb
```

Expected: All tests PASS

**Step 5: Commit**

```bash
git add hub/app/controllers/api/internal/episodes_controller.rb hub/test/controllers/api/internal/episodes_controller_test.rb
git commit -m "feat: release free episode claim on processing failure"
```

---

## Task 8: Update EpisodeSubmissionValidator with Tier-Based Character Limits

**Files:**
- Modify: `hub/app/services/episode_submission_validator.rb`
- Modify: `hub/test/services/episode_submission_validator_test.rb`

**Step 1: Update the tests**

Replace `hub/test/services/episode_submission_validator_test.rb`:

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

  test "returns 25_000 max_characters for basic tier users" do
    user = users(:basic_user)

    result = EpisodeSubmissionValidator.call(user: user)

    assert_equal 25_000, result.max_characters
    assert_not result.unlimited?
  end

  test "returns 50_000 max_characters for plus tier users" do
    user = users(:plus_user)

    result = EpisodeSubmissionValidator.call(user: user)

    assert_equal 50_000, result.max_characters
    assert_not result.unlimited?
  end

  test "returns 50_000 max_characters for premium tier users" do
    user = users(:premium_user)

    result = EpisodeSubmissionValidator.call(user: user)

    assert_equal 50_000, result.max_characters
    assert_not result.unlimited?
  end
end
```

**Step 2: Run tests to verify they fail**

Run:
```bash
cd hub && bin/rails test test/services/episode_submission_validator_test.rb
```

Expected: Tests for basic (25K), plus (50K), premium (50K) FAIL

**Step 3: Update the service**

Replace `hub/app/services/episode_submission_validator.rb`:

```ruby
class EpisodeSubmissionValidator
  MAX_CHARACTERS_FREE = 10_000
  MAX_CHARACTERS_BASIC = 25_000
  MAX_CHARACTERS_PLUS_PREMIUM = 50_000

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
    case
    when user.unlimited? then nil
    when user.premium? || user.plus? then MAX_CHARACTERS_PLUS_PREMIUM
    when user.basic? then MAX_CHARACTERS_BASIC
    else MAX_CHARACTERS_FREE
    end
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

**Step 4: Run tests to verify they pass**

Run:
```bash
cd hub && bin/rails test test/services/episode_submission_validator_test.rb
```

Expected: All tests PASS

**Step 5: Commit**

```bash
git add hub/app/services/episode_submission_validator.rb hub/test/services/episode_submission_validator_test.rb
git commit -m "feat: add tier-based character limits to EpisodeSubmissionValidator"
```

---

## Task 9: Remove submissions_enabled? from User Model

**Files:**
- Modify: `hub/app/models/user.rb`
- Modify: `hub/test/models/user_test.rb` (if exists)

**Step 1: Check for usages of submissions_enabled?**

Run:
```bash
cd hub && grep -r "submissions_enabled" --include="*.rb" .
```

Expected: Should only find the method definition in user.rb (after controller changes)

**Step 2: Remove the method from User model**

Edit `hub/app/models/user.rb` to remove:

```ruby
def submissions_enabled?
  unlimited?
end
```

**Step 3: Run all tests to verify nothing breaks**

Run:
```bash
cd hub && bin/rails test
```

Expected: All tests PASS

**Step 4: Commit**

```bash
git add hub/app/models/user.rb
git commit -m "chore: remove unused submissions_enabled? method from User"
```

---

## Task 10: Run Full Test Suite and Verify

**Step 1: Run all tests**

Run:
```bash
cd hub && bin/rails test
```

Expected: All tests PASS

**Step 2: Manual verification checklist**

- [ ] Free tier user can create first episode
- [ ] Free tier user cannot create second episode (redirected with message)
- [ ] Free tier user can create another episode after first one fails
- [ ] Basic/Plus/Premium/Unlimited users can create episodes without restriction
- [ ] Character limits are correct per tier (10K/25K/50K/unlimited)

**Step 3: Final commit (if any fixups needed)**

```bash
git add -A
git commit -m "fix: address test failures from integration"
```
