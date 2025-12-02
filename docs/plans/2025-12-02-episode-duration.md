# Episode Duration in RSS Feed Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add episode duration to the RSS feed so podcast apps display episode length.

**Architecture:** Parse MP3 duration after synthesis using `ruby-mp3info` gem, pass duration through the publish pipeline, and emit `<itunes:duration>` in RSS feed.

**Tech Stack:** Ruby, `ruby-mp3info` gem, RSS/iTunes XML

---

## Task 1: Add ruby-mp3info gem

**Files:**
- Modify: `Gemfile:10` (after TTS providers section)

**Step 1: Add the gem to Gemfile**

Add after line 10 (after `google-cloud-text_to_speech`):

```ruby
gem "ruby-mp3info"
```

**Step 2: Install the gem**

Run: `bundle install`
Expected: Successful install with "Bundle complete!"

**Step 3: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "chore: add ruby-mp3info gem for duration parsing"
```

---

## Task 2: Add itunes:duration to RSS feed

**Files:**
- Modify: `lib/rss_generator.rb:61-77`
- Test: `test/test_rss_generator.rb`

**Step 1: Write the failing test**

Add to `test/test_rss_generator.rb` after `test_formats_pubdate_in_rfc822`:

```ruby
def test_includes_itunes_duration_when_provided
  episodes_with_duration = [
    {
      "title" => "Episode With Duration",
      "description" => "Description",
      "mp3_url" => "https://example.com/episode.mp3",
      "file_size_bytes" => 1_000_000,
      "published_at" => "2025-10-26T10:00:00Z",
      "guid" => "test-guid",
      "duration_seconds" => 754
    }
  ]

  generator = RSSGenerator.new(@podcast_config, episodes_with_duration)
  xml = generator.generate

  doc = REXML::Document.new(xml)
  item = doc.root.elements["channel/item[1]"]
  duration = item.elements["itunes:duration"]

  assert_equal "12:34", duration.text
end
```

**Step 2: Run test to verify it fails**

Run: `ruby test/test_rss_generator.rb --name test_includes_itunes_duration_when_provided`
Expected: FAIL (no `itunes:duration` element)

**Step 3: Write minimal implementation**

In `lib/rss_generator.rb`, modify `add_episode_item` method to add duration. Replace the method (lines 61-77):

```ruby
def add_episode_item(xml, episode)
  xml.item do
    xml.title episode["title"]
    xml.description episode["description"]

    author = episode["author"] || @podcast_config["author"]
    xml.tag! "itunes:author", author

    xml.enclosure url: episode["mp3_url"],
                  type: "audio/mpeg",
                  length: episode["file_size_bytes"]

    xml.guid episode["guid"], isPermaLink: "false"

    pubdate = Time.parse(episode["published_at"])
    xml.pubDate pubdate.rfc2822

    add_duration(xml, episode["duration_seconds"])
  end
end

def add_duration(xml, duration_seconds)
  return unless duration_seconds

  minutes = duration_seconds / 60
  seconds = duration_seconds % 60
  xml.tag! "itunes:duration", format("%d:%02d", minutes, seconds)
end
```

**Step 4: Run test to verify it passes**

Run: `ruby test/test_rss_generator.rb --name test_includes_itunes_duration_when_provided`
Expected: PASS

**Step 5: Run all RSS tests**

Run: `ruby test/test_rss_generator.rb`
Expected: All tests pass

**Step 6: Commit**

```bash
git add lib/rss_generator.rb test/test_rss_generator.rb
git commit -m "feat: add itunes:duration to RSS feed"
```

---

## Task 3: Calculate duration from MP3 in PodcastPublisher

**Files:**
- Modify: `lib/podcast_publisher.rb`
- Test: `test/test_podcast_publisher.rb`

**Step 1: Write the failing test**

Add to `test/test_podcast_publisher.rb` after `test_publish_returns_episode_data`:

```ruby
def test_publish_returns_duration_seconds
  metadata = { "title" => "Test Episode", "description" => "Test" }

  episode_data = @publisher.publish(audio_content: @audio_content, metadata: metadata)

  assert episode_data.key?("duration_seconds"), "Expected episode_data to include duration_seconds"
  assert_kind_of Integer, episode_data["duration_seconds"]
end
```

**Step 2: Run test to verify it fails**

Run: `ruby test/test_podcast_publisher.rb --name test_publish_returns_duration_seconds`
Expected: FAIL (no `duration_seconds` key)

**Step 3: Write minimal implementation**

In `lib/podcast_publisher.rb`:

Add require at top (after line 2):
```ruby
require "mp3info"
```

Modify `build_episode_data` method to include duration (replace lines 39-49):

```ruby
def build_episode_data(metadata:, guid:, mp3_url:, file_size:, duration_seconds:)
  {
    "id" => guid,
    "title" => metadata["title"],
    "description" => metadata["description"],
    "author" => metadata["author"],
    "mp3_url" => mp3_url,
    "file_size_bytes" => file_size,
    "duration_seconds" => duration_seconds,
    "published_at" => Time.now.utc.iso8601,
    "guid" => guid
  }
end
```

Modify `publish` method to calculate duration (replace lines 20-30):

```ruby
def publish(audio_content:, metadata:)
  guid = EpisodeManifest.generate_guid(metadata["title"])
  mp3_url = upload_mp3(audio_content: audio_content, guid: guid)
  duration_seconds = calculate_duration(audio_content)
  episode_data = build_episode_data(
    metadata: metadata,
    guid: guid,
    mp3_url: mp3_url,
    file_size: audio_content.bytesize,
    duration_seconds: duration_seconds
  )

  update_manifest(episode_data)
  upload_rss_feed

  episode_data
end
```

Add new private method after `upload_mp3`:

```ruby
def calculate_duration(audio_content)
  Tempfile.create(["episode", ".mp3"]) do |temp_file|
    temp_file.binmode
    temp_file.write(audio_content)
    temp_file.flush
    Mp3Info.open(temp_file.path) { |mp3| mp3.length.round }
  end
end
```

**Step 4: Run test to verify it passes**

Run: `ruby test/test_podcast_publisher.rb --name test_publish_returns_duration_seconds`
Expected: PASS

**Step 5: Run all publisher tests**

Run: `ruby test/test_podcast_publisher.rb`
Expected: All tests pass

**Step 6: Commit**

```bash
git add lib/podcast_publisher.rb test/test_podcast_publisher.rb
git commit -m "feat: calculate episode duration from MP3"
```

---

## Task 4: Pass duration from Generator to Hub callback

**Files:**
- Modify: `lib/hub_callback_client.rb:11-16`
- Test: `test/test_hub_callback_client.rb`

**Step 1: Read current test file**

Read `test/test_hub_callback_client.rb` to understand existing test patterns.

**Step 2: Write the failing test**

Add test that verifies duration is included in the callback payload.

**Step 3: Modify notify_complete to include duration**

In `lib/hub_callback_client.rb`, update `notify_complete` (lines 11-16):

```ruby
def notify_complete(episode_id:, episode_data:)
  patch_episode(episode_id, {
    status: "complete",
    gcs_episode_id: episode_data["id"],
    audio_size_bytes: episode_data["file_size_bytes"],
    duration_seconds: episode_data["duration_seconds"]
  })
end
```

**Step 4: Run tests**

Run: `ruby test/test_hub_callback_client.rb`
Expected: All tests pass

**Step 5: Commit**

```bash
git add lib/hub_callback_client.rb test/test_hub_callback_client.rb
git commit -m "feat: include duration_seconds in hub callback"
```

---

## Task 5: Accept duration in Hub API endpoint

**Files:**
- Modify: `hub/app/controllers/api/internal/episodes_controller.rb:26-28`
- Test: `hub/test/controllers/api/internal/episodes_controller_test.rb`

**Step 1: Read current test file**

Read `hub/test/controllers/api/internal/episodes_controller_test.rb` to understand existing patterns.

**Step 2: Write the failing test**

Add test that verifies duration_seconds is accepted and saved.

**Step 3: Add duration_seconds to permitted params**

In `hub/app/controllers/api/internal/episodes_controller.rb`, update `episode_params`:

```ruby
def episode_params
  params.permit(:status, :gcs_episode_id, :audio_size_bytes, :duration_seconds, :error_message)
end
```

**Step 4: Run tests**

Run: `bin/rails test test/controllers/api/internal/episodes_controller_test.rb`
Expected: All tests pass

**Step 5: Commit**

```bash
git add hub/app/controllers/api/internal/episodes_controller.rb hub/test/controllers/api/internal/episodes_controller_test.rb
git commit -m "feat: accept duration_seconds in episode callback API"
```

---

## Task 6: Update README to remove known limitation

**Files:**
- Modify: `README.md:175`

**Step 1: Remove the limitation line**

Remove line 175: `- Episode duration not tracked in metadata`

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: remove duration limitation from README"
```

---

## Task 7: Run full test suite and verify

**Step 1: Run all tests**

Run: `rake test`
Expected: All tests pass

**Step 2: Run rubocop**

Run: `rake rubocop`
Expected: No offenses

**Step 3: Final commit (if any fixes needed)**

If rubocop requires changes, fix and commit.

---

## Verification

After deployment:
1. Create a new episode via the Hub
2. Wait for processing to complete
3. Check the RSS feed XML for `<itunes:duration>` tag
4. Verify duration displays correctly in a podcast app
