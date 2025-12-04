# Voice Options Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Allow users to select a voice for their TTS podcasts via a settings page.

**Architecture:** Static Voice registry (no database table), per-user `voice_preference` column, settings page with radio cards and audio preview. Episode delegates voice lookup to user.

**Tech Stack:** Rails 8, Stimulus, Tailwind CSS, Google Cloud TTS

---

## Task 1: Voice Registry Model

**Files:**
- Create: `hub/app/models/voice.rb`
- Test: `hub/test/models/voice_test.rb`

**Step 1: Write the failing tests**

```ruby
# hub/test/models/voice_test.rb
# frozen_string_literal: true

require "test_helper"

class VoiceTest < ActiveSupport::TestCase
  test "STANDARD contains four voices" do
    assert_equal %w[wren felix sloane archer], Voice::STANDARD
  end

  test "CHIRP contains four voices" do
    assert_equal %w[elara callum lark nash], Voice::CHIRP
  end

  test "ALL contains all eight voices" do
    assert_equal 8, Voice::ALL.length
    assert_includes Voice::ALL, "wren"
    assert_includes Voice::ALL, "elara"
  end

  test "for_tier returns STANDARD for free tier" do
    assert_equal Voice::STANDARD, Voice.for_tier("free")
  end

  test "for_tier returns STANDARD for premium tier" do
    assert_equal Voice::STANDARD, Voice.for_tier("premium")
  end

  test "for_tier returns ALL for unlimited tier" do
    assert_equal Voice::ALL, Voice.for_tier("unlimited")
  end

  test "find returns voice data for valid key" do
    voice = Voice.find("wren")

    assert_equal "Wren", voice[:name]
    assert_equal "British", voice[:accent]
    assert_equal "Female", voice[:gender]
    assert_equal "en-GB-Standard-C", voice[:google_voice]
  end

  test "find returns nil for invalid key" do
    assert_nil Voice.find("invalid")
  end

  test "sample_url returns GCS URL for voice" do
    ENV["GOOGLE_CLOUD_BUCKET"] = "test-bucket"

    assert_equal "https://storage.googleapis.com/test-bucket/voices/wren.mp3", Voice.sample_url("wren")
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `cd hub && bin/rails test test/models/voice_test.rb`
Expected: Error - `NameError: uninitialized constant Voice`

**Step 3: Write the Voice model**

```ruby
# hub/app/models/voice.rb
# frozen_string_literal: true

class Voice
  STANDARD = %w[wren felix sloane archer].freeze
  CHIRP = %w[elara callum lark nash].freeze
  ALL = (STANDARD + CHIRP).freeze

  CATALOG = {
    "wren"    => { name: "Wren",    accent: "British",  gender: "Female", google_voice: "en-GB-Standard-C" },
    "felix"   => { name: "Felix",   accent: "British",  gender: "Male",   google_voice: "en-GB-Standard-D" },
    "sloane"  => { name: "Sloane",  accent: "American", gender: "Female", google_voice: "en-US-Standard-C" },
    "archer"  => { name: "Archer",  accent: "American", gender: "Male",   google_voice: "en-US-Standard-J" },
    "elara"   => { name: "Elara",   accent: "British",  gender: "Female", google_voice: "en-GB-Chirp3-HD-Gacrux" },
    "callum"  => { name: "Callum",  accent: "British",  gender: "Male",   google_voice: "en-GB-Chirp3-HD-Enceladus" },
    "lark"    => { name: "Lark",    accent: "American", gender: "Female", google_voice: "en-US-Chirp3-HD-Callirrhoe" },
    "nash"    => { name: "Nash",    accent: "American", gender: "Male",   google_voice: "en-US-Chirp3-HD-Charon" }
  }.freeze

  def self.for_tier(tier)
    tier == "unlimited" ? ALL : STANDARD
  end

  def self.sample_url(key)
    bucket = ENV.fetch("GOOGLE_CLOUD_BUCKET")
    "https://storage.googleapis.com/#{bucket}/voices/#{key}.mp3"
  end

  def self.find(key)
    CATALOG[key]
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `cd hub && bin/rails test test/models/voice_test.rb`
Expected: All 9 tests pass

**Step 5: Commit**

```bash
git add hub/app/models/voice.rb hub/test/models/voice_test.rb
git commit -m "feat: add Voice registry model"
```

---

## Task 2: Database Migration

**Files:**
- Create: `hub/db/migrate/YYYYMMDDHHMMSS_add_voice_preference_to_users.rb`

**Step 1: Generate the migration**

Run: `cd hub && bin/rails generate migration AddVoicePreferenceToUsers voice_preference:string`

**Step 2: Verify the migration file**

The generated migration should look like:

```ruby
class AddVoicePreferenceToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :voice_preference, :string
  end
end
```

**Step 3: Run the migration**

Run: `cd hub && bin/rails db:migrate`
Expected: Migration runs successfully

**Step 4: Verify schema updated**

Run: `grep voice_preference hub/db/schema.rb`
Expected: Shows `t.string "voice_preference"` in users table

**Step 5: Commit**

```bash
git add hub/db/migrate/*_add_voice_preference_to_users.rb hub/db/schema.rb
git commit -m "feat: add voice_preference column to users"
```

---

## Task 3: Update User Model

**Files:**
- Modify: `hub/app/models/user.rb`
- Modify: `hub/test/models/user_test.rb`

**Step 1: Write the failing tests**

Add to `hub/test/models/user_test.rb`:

```ruby
test "voice_preference validates inclusion in Voice::ALL" do
  user = users(:one)
  user.voice_preference = "invalid_voice"

  assert_not user.valid?
  assert_includes user.errors[:voice_preference], "is not included in the list"
end

test "voice_preference allows nil" do
  user = users(:one)
  user.voice_preference = nil

  assert user.valid?
end

test "voice_preference allows valid standard voice" do
  user = users(:one)
  user.voice_preference = "wren"

  assert user.valid?
end

test "voice_preference allows valid chirp voice" do
  user = users(:one)
  user.voice_preference = "elara"

  assert user.valid?
end

test "voice returns google_voice for selected voice_preference" do
  user = users(:one)
  user.voice_preference = "wren"

  assert_equal "en-GB-Standard-C", user.voice
end

test "voice returns default Standard voice when voice_preference is nil and tier is free" do
  user = users(:one)
  user.tier = :free
  user.voice_preference = nil

  assert_equal "en-GB-Standard-D", user.voice
end

test "voice returns default Chirp voice when voice_preference is nil and tier is unlimited" do
  user = users(:one)
  user.tier = :unlimited
  user.voice_preference = nil

  assert_equal "en-GB-Chirp3-HD-Enceladus", user.voice
end

test "available_voices returns STANDARD for free tier" do
  user = users(:one)
  user.tier = :free

  assert_equal Voice::STANDARD, user.available_voices
end

test "available_voices returns ALL for unlimited tier" do
  user = users(:one)
  user.tier = :unlimited

  assert_equal Voice::ALL, user.available_voices
end
```

**Step 2: Run tests to verify they fail**

Run: `cd hub && bin/rails test test/models/user_test.rb`
Expected: Multiple failures - validation missing, methods not defined

**Step 3: Update User model**

Replace the `voice_name` method and add new methods in `hub/app/models/user.rb`:

```ruby
class User < ApplicationRecord
  has_many :sessions, dependent: :destroy
  has_many :podcast_memberships, dependent: :destroy
  has_many :podcasts, through: :podcast_memberships
  has_many :sent_messages, dependent: :destroy

  enum :tier, { free: 0, premium: 1, unlimited: 2 }

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :voice_preference, inclusion: { in: Voice::ALL }, allow_nil: true

  scope :with_valid_auth_token, -> {
    where.not(auth_token: nil)
         .where("auth_token_expires_at > ?", Time.current)
  }

  def voice
    return Voice.find(voice_preference)[:google_voice] if voice_preference.present?

    unlimited? ? "en-GB-Chirp3-HD-Enceladus" : "en-GB-Standard-D"
  end

  def available_voices
    Voice.for_tier(tier)
  end

  def email
    email_address
  end
end
```

**Step 4: Update existing tests**

In `hub/test/models/user_test.rb`, update the old `voice_name` tests to use `voice`:

Replace:
```ruby
test "voice_name returns Standard voice for free tier" do
  user = users(:one)
  user.update!(tier: :free)
  assert_equal "en-GB-Standard-D", user.voice_name
end

test "voice_name returns Standard voice for premium tier" do
  user = users(:one)
  user.update!(tier: :premium)
  assert_equal "en-GB-Standard-D", user.voice_name
end

test "voice_name returns Chirp3-HD voice for unlimited tier" do
  user = users(:one)
  user.update!(tier: :unlimited)
  assert_equal "en-GB-Chirp3-HD-Enceladus", user.voice_name
end
```

With:
```ruby
test "voice returns Standard voice for free tier with no preference" do
  user = users(:one)
  user.tier = :free
  user.voice_preference = nil

  assert_equal "en-GB-Standard-D", user.voice
end

test "voice returns Standard voice for premium tier with no preference" do
  user = users(:one)
  user.tier = :premium
  user.voice_preference = nil

  assert_equal "en-GB-Standard-D", user.voice
end

test "voice returns Chirp3-HD voice for unlimited tier with no preference" do
  user = users(:one)
  user.tier = :unlimited
  user.voice_preference = nil

  assert_equal "en-GB-Chirp3-HD-Enceladus", user.voice
end
```

**Step 5: Run tests to verify they pass**

Run: `cd hub && bin/rails test test/models/user_test.rb`
Expected: All tests pass

**Step 6: Commit**

```bash
git add hub/app/models/user.rb hub/test/models/user_test.rb
git commit -m "feat: add voice_preference to User with validation"
```

---

## Task 4: Update Episode Model

**Files:**
- Modify: `hub/app/models/episode.rb`
- Create: `hub/test/models/episode_test.rb`

**Step 1: Write the failing test**

```ruby
# hub/test/models/episode_test.rb
# frozen_string_literal: true

require "test_helper"

class EpisodeTest < ActiveSupport::TestCase
  test "voice delegates to user" do
    episode = episodes(:one)
    episode.user.voice_preference = "sloane"

    assert_equal "en-US-Standard-C", episode.voice
  end

  test "voice returns user default when no preference set" do
    episode = episodes(:one)
    episode.user.voice_preference = nil
    episode.user.tier = :free

    assert_equal "en-GB-Standard-D", episode.voice
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `cd hub && bin/rails test test/models/episode_test.rb`
Expected: `NoMethodError: undefined method 'voice' for #<Episode>`

**Step 3: Add delegation to Episode model**

Add to `hub/app/models/episode.rb` after the `belongs_to` declarations:

```ruby
delegate :voice, to: :user
```

Full file should look like:

```ruby
class Episode < ApplicationRecord
  belongs_to :podcast
  belongs_to :user
  has_one :llm_usage, dependent: :destroy

  delegate :voice, to: :user

  enum :status, { pending: "pending", processing: "processing", complete: "complete", failed: "failed" }
  enum :source_type, { file: 0, url: 1 }

  # ... rest of file unchanged
end
```

**Step 4: Run tests to verify they pass**

Run: `cd hub && bin/rails test test/models/episode_test.rb`
Expected: All tests pass

**Step 5: Commit**

```bash
git add hub/app/models/episode.rb hub/test/models/episode_test.rb
git commit -m "feat: delegate voice to user on Episode"
```

---

## Task 5: Update UploadAndEnqueueEpisode Service

**Files:**
- Modify: `hub/app/services/upload_and_enqueue_episode.rb`
- Modify: `hub/test/services/upload_and_enqueue_episode_test.rb`

**Step 1: Write the failing test**

Add to `hub/test/services/upload_and_enqueue_episode_test.rb`:

```ruby
test "passes episode.voice to enqueue_episode_processing" do
  @episode.user.voice_preference = "sloane"

  mock_gcs = Mocktail.of(GcsUploader)
  stubs { |m| mock_gcs.upload_staging_file(content: m.any, filename: m.any) }.with { "staging/test.txt" }
  stubs { |m| GcsUploader.new(m.any, podcast_id: m.any) }.with { mock_gcs }

  mock_tasks = Mocktail.of(CloudTasksEnqueuer)
  stubs { |m| mock_tasks.enqueue_episode_processing(episode_id: m.any, podcast_id: m.any, staging_path: m.any, metadata: m.any, voice_name: m.any) }.with { "task-123" }
  stubs { CloudTasksEnqueuer.new }.with { mock_tasks }

  UploadAndEnqueueEpisode.call(episode: @episode, content: @plain_text_content)

  verify { |m| mock_tasks.enqueue_episode_processing(episode_id: m.any, podcast_id: m.any, staging_path: m.any, metadata: m.any, voice_name: "en-US-Standard-C") }
end
```

**Step 2: Run tests to verify they fail**

Run: `cd hub && bin/rails test test/services/upload_and_enqueue_episode_test.rb`
Expected: Verification failure - voice_name doesn't match expected

**Step 3: Update the service**

In `hub/app/services/upload_and_enqueue_episode.rb`, change line 43 from:

```ruby
voice_name: episode.user.voice_name
```

To:

```ruby
voice_name: episode.voice
```

**Step 4: Run tests to verify they pass**

Run: `cd hub && bin/rails test test/services/upload_and_enqueue_episode_test.rb`
Expected: All tests pass

**Step 5: Commit**

```bash
git add hub/app/services/upload_and_enqueue_episode.rb hub/test/services/upload_and_enqueue_episode_test.rb
git commit -m "refactor: use episode.voice instead of episode.user.voice_name"
```

---

## Task 6: Settings Controller

**Files:**
- Create: `hub/app/controllers/settings_controller.rb`
- Create: `hub/test/controllers/settings_controller_test.rb`
- Modify: `hub/config/routes.rb`

**Step 1: Write the failing tests**

```ruby
# hub/test/controllers/settings_controller_test.rb
# frozen_string_literal: true

require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(tier: :free)
    sign_in_as(@user)
  end

  test "show renders settings page" do
    get settings_path

    assert_response :success
    assert_select "h1", "Settings"
  end

  test "show displays available voices for free tier" do
    get settings_path

    assert_response :success
    assert_select "input[name='voice'][value='wren']"
    assert_select "input[name='voice'][value='felix']"
    assert_select "input[name='voice'][value='sloane']"
    assert_select "input[name='voice'][value='archer']"
    assert_select "input[name='voice'][value='elara']", count: 0
  end

  test "show displays all voices for unlimited tier" do
    @user.update!(tier: :unlimited)
    get settings_path

    assert_response :success
    assert_select "input[name='voice'][value='wren']"
    assert_select "input[name='voice'][value='elara']"
  end

  test "show marks current voice_preference as selected" do
    @user.update!(voice_preference: "sloane")
    get settings_path

    assert_select "input[name='voice'][value='sloane'][checked]"
  end

  test "update saves valid voice_preference" do
    patch settings_path, params: { voice: "felix" }

    assert_redirected_to settings_path
    assert_equal "Settings saved.", flash[:notice]
    assert_equal "felix", @user.reload.voice_preference
  end

  test "update rejects invalid voice" do
    patch settings_path, params: { voice: "invalid" }

    assert_redirected_to settings_path
    assert_equal "Invalid voice selection.", flash[:alert]
  end

  test "update rejects chirp voice for free tier" do
    patch settings_path, params: { voice: "elara" }

    assert_redirected_to settings_path
    assert_equal "Invalid voice selection.", flash[:alert]
  end

  test "update allows chirp voice for unlimited tier" do
    @user.update!(tier: :unlimited)
    patch settings_path, params: { voice: "elara" }

    assert_redirected_to settings_path
    assert_equal "Settings saved.", flash[:notice]
    assert_equal "elara", @user.reload.voice_preference
  end

  test "requires authentication" do
    sign_out
    get settings_path

    assert_redirected_to root_path
  end

  private

  def sign_in_as(user)
    post session_path, params: { token: generate_valid_token_for(user) }
  end

  def sign_out
    delete session_path
  end

  def generate_valid_token_for(user)
    token = SecureRandom.urlsafe_base64(32)
    user.update!(
      auth_token: Digest::SHA256.hexdigest(token),
      auth_token_expires_at: 30.minutes.from_now
    )
    token
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `cd hub && bin/rails test test/controllers/settings_controller_test.rb`
Expected: Error - routing error or controller not found

**Step 3: Add route**

In `hub/config/routes.rb`, add after `resource :session`:

```ruby
resource :settings, only: [:show, :update]
```

**Step 4: Create the controller**

```ruby
# hub/app/controllers/settings_controller.rb
# frozen_string_literal: true

class SettingsController < ApplicationController
  before_action :require_authentication

  def show
    @voices = current_user.available_voices.map do |key|
      Voice.find(key).merge(key: key, sample_url: Voice.sample_url(key))
    end
    @selected_voice = current_user.voice_preference
  end

  def update
    voice = params[:voice]

    if voice.present? && !current_user.available_voices.include?(voice)
      redirect_to settings_path, alert: "Invalid voice selection."
      return
    end

    if current_user.update(voice_preference: voice)
      redirect_to settings_path, notice: "Settings saved."
    else
      redirect_to settings_path, alert: "Invalid voice selection."
    end
  end
end
```

**Step 5: Create placeholder view (to make tests pass)**

```erb
<%# hub/app/views/settings/show.html.erb %>
<div class="max-w-2xl mx-auto">
  <h1 class="text-2xl font-semibold mb-8">Settings</h1>

  <%= render "shared/card", padding: "p-4 sm:p-8" do %>
    <%= form_with url: settings_path, method: :patch, class: "space-y-6" do %>
      <h2 class="text-lg font-medium">Voice</h2>
      <p class="text-[var(--color-subtext)] text-sm">Choose the voice for your podcast episodes.</p>

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <% @voices.each do |voice| %>
          <label class="relative block cursor-pointer">
            <input type="radio" name="voice" value="<%= voice[:key] %>"
                   <%= "checked" if @selected_voice == voice[:key] %>
                   class="peer sr-only">
            <div class="border-2 rounded-lg p-4 transition-colors
                        border-[var(--color-overlay0)] peer-checked:border-[var(--color-primary)]
                        peer-checked:bg-[var(--color-primary)]/5">
              <div class="flex items-center justify-between mb-2">
                <span class="font-medium"><%= voice[:name] %></span>
                <div class="w-4 h-4 rounded-full border-2
                            border-[var(--color-overlay0)] peer-checked:border-[var(--color-primary)]
                            peer-checked:bg-[var(--color-primary)]"></div>
              </div>
              <p class="text-sm text-[var(--color-subtext)]">
                <%= voice[:accent] %> · <%= voice[:gender] %>
              </p>
              <button type="button"
                      data-controller="audio-preview"
                      data-audio-preview-url-value="<%= voice[:sample_url] %>"
                      data-action="click->audio-preview#play"
                      class="mt-3 text-sm text-[var(--color-primary)] hover:underline">
                ▶ Preview
              </button>
            </div>
          </label>
        <% end %>
      </div>

      <%= submit_tag "Save Changes", class: button_classes(type: :primary) %>
    <% end %>
  <% end %>
</div>
```

**Step 6: Run tests to verify they pass**

Run: `cd hub && bin/rails test test/controllers/settings_controller_test.rb`
Expected: All tests pass

**Step 7: Commit**

```bash
git add hub/app/controllers/settings_controller.rb hub/test/controllers/settings_controller_test.rb hub/config/routes.rb hub/app/views/settings/show.html.erb
git commit -m "feat: add settings controller with voice selection"
```

---

## Task 7: Audio Preview Stimulus Controller

**Files:**
- Create: `hub/app/javascript/controllers/audio_preview_controller.js`

**Step 1: Create the controller**

```javascript
// hub/app/javascript/controllers/audio_preview_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }

  play(event) {
    event.preventDefault()

    if (this.audio) {
      this.audio.pause()
    }

    this.audio = new Audio(this.urlValue)
    this.audio.play()
  }
}
```

**Step 2: Verify Stimulus auto-loads controllers**

The `hub/app/javascript/controllers/index.js` already uses `eagerLoadControllersFrom`, so the controller will be auto-registered.

**Step 3: Commit**

```bash
git add hub/app/javascript/controllers/audio_preview_controller.js
git commit -m "feat: add audio preview Stimulus controller"
```

---

## Task 8: Add Settings Link to Header

**Files:**
- Modify: `hub/app/views/shared/_header.html.erb`

**Step 1: Update the header**

In `hub/app/views/shared/_header.html.erb`, add Settings link before the email display:

```erb
<header class="fixed top-0 left-0 right-0 bg-[var(--color-base)] border-b border-[var(--color-overlay0)] z-50" data-controller="theme">
  <div class="max-w-6xl mx-auto px-4 py-4 flex justify-between items-center">
    <div class="text-lg font-semibold">
      Very Normal TTS
    </div>
    <div class="flex items-center gap-4">
      <button
        data-action="click->theme#toggle"
        class="cursor-pointer hover:opacity-70"
        title="Toggle dark mode"
      >
        <span data-theme-target="sunIcon" class="hidden">
          <%= render "shared/icons/sun" %>
        </span>
        <span data-theme-target="moonIcon">
          <%= render "shared/icons/moon" %>
        </span>
      </button>
      <% if authenticated? %>
        <%= link_to "Settings", settings_path, class: "text-sm text-[var(--color-text)] hover:text-[var(--color-primary)]" %>
        <span class="text-sm text-[var(--color-subtext)]"><%= Current.user.email_address %></span>
        <%= button_to "Logout", session_path, method: :delete, class: button_classes(type: :link) %>
      <% end %>
    </div>
  </div>
</header>
```

**Step 2: Manual verification**

Run: `cd hub && bin/rails server`
Visit: http://localhost:3000
Expected: Settings link appears in header when logged in

**Step 3: Commit**

```bash
git add hub/app/views/shared/_header.html.erb
git commit -m "feat: add Settings link to header navigation"
```

---

## Task 9: Generate Voice Samples (Manual)

**Note:** This task requires manual execution with Google Cloud TTS API.

**Step 1: Create a sample generation script**

```ruby
# scripts/generate_voice_samples.rb
# Run with: GOOGLE_CLOUD_PROJECT=your-project ruby scripts/generate_voice_samples.rb

require "google/cloud/text_to_speech"

SAMPLE_TEXT = "New research suggests that listening to articles can improve comprehension and retention, especially during commutes."

VOICES = {
  "wren"    => "en-GB-Standard-C",
  "felix"   => "en-GB-Standard-D",
  "sloane"  => "en-US-Standard-C",
  "archer"  => "en-US-Standard-J",
  "elara"   => "en-GB-Chirp3-HD-Gacrux",
  "callum"  => "en-GB-Chirp3-HD-Enceladus",
  "lark"    => "en-US-Chirp3-HD-Callirrhoe",
  "nash"    => "en-US-Chirp3-HD-Charon"
}

client = Google::Cloud::TextToSpeech.text_to_speech

VOICES.each do |name, google_voice|
  puts "Generating #{name}..."

  language_code = google_voice.start_with?("en-GB") ? "en-GB" : "en-US"

  response = client.synthesize_speech(
    input: { text: SAMPLE_TEXT },
    voice: { language_code: language_code, name: google_voice },
    audio_config: { audio_encoding: "MP3" }
  )

  File.binwrite("tmp/#{name}.mp3", response.audio_content)
  puts "  Saved to tmp/#{name}.mp3"
end

puts "Done! Upload files to gs://YOUR_BUCKET/voices/"
```

**Step 2: Run the script**

Run: `cd hub && ruby ../scripts/generate_voice_samples.rb`

**Step 3: Upload to GCS**

Run: `gsutil cp tmp/*.mp3 gs://YOUR_BUCKET/voices/`

**Step 4: Verify samples accessible**

Run: `gsutil ls gs://YOUR_BUCKET/voices/`
Expected: Lists all 8 .mp3 files

---

## Task 10: Run Full Test Suite

**Step 1: Run all tests**

Run: `cd hub && bin/rails test`
Expected: All tests pass

**Step 2: Run system tests (if applicable)**

Run: `cd hub && bin/rails test:system`
Expected: All tests pass

**Step 3: Final commit**

```bash
git add -A
git commit -m "feat: voice options implementation complete"
```

---

## Summary Checklist

- [ ] Task 1: Voice registry model
- [ ] Task 2: Database migration
- [ ] Task 3: Update User model
- [ ] Task 4: Update Episode model
- [ ] Task 5: Update UploadAndEnqueueEpisode service
- [ ] Task 6: Settings controller and views
- [ ] Task 7: Audio preview Stimulus controller
- [ ] Task 8: Header navigation link
- [ ] Task 9: Generate and upload voice samples
- [ ] Task 10: Full test suite passes
