# Merge Generator into Hub Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Consolidate the TTS generator (Sinatra/Cloud Run) into the Hub (Rails/Kamal) to eliminate architectural complexity.

**Architecture:** Move the TTS library and processing logic into the Hub as services. Replace Cloud Tasks dispatch with Solid Queue jobs. Generate RSS feeds from the database instead of manifest.json. Use a hardcoded podcast allowlist for safe rollout.

**Tech Stack:** Rails 8.1, Solid Queue, Google Cloud TTS API, Google Cloud Storage, concurrent-ruby

---

## Prerequisites

Before starting, these items have been verified:
- ✅ TTS gems added to Hub Gemfile (`google-cloud-text_to_speech`, `ruby-mp3info`)
- ✅ All 440 Hub tests passing
- ✅ All 135 Generator tests passing
- ✅ `concurrent-ruby` already available in Hub

**Jesse's podcast_id for testing:** `podcast_195c82bf8eeb2aae`

---

## Task 1: Copy TTS Library to Hub

**Files:**
- Create: `hub/lib/tts.rb`
- Create: `hub/lib/tts/config.rb`
- Create: `hub/lib/tts/api_client.rb`
- Create: `hub/lib/tts/text_chunker.rb`
- Create: `hub/lib/tts/chunked_synthesizer.rb`

**Step 1: Create the lib/tts directory**

Run: `mkdir -p lib/tts`

**Step 2: Copy config.rb (no changes needed)**

```ruby
# hub/lib/tts/config.rb
# frozen_string_literal: true

module Tts
  # Configuration class for TTS settings.
  class Config
    attr_accessor :voice_name, :language_code, :speaking_rate, :pitch, :audio_encoding, :timeout, :max_retries,
                  :thread_pool_size, :byte_limit

    def initialize(
      voice_name: "en-GB-Chirp3-HD-Enceladus",
      language_code: "en-GB",
      speaking_rate: 1.0,
      pitch: 0.0,
      audio_encoding: "MP3",
      timeout: 300,
      max_retries: 3,
      thread_pool_size: 10,
      byte_limit: 850
    )
      @voice_name = voice_name
      @language_code = language_code
      @speaking_rate = speaking_rate
      @pitch = pitch
      @audio_encoding = audio_encoding
      @timeout = timeout
      @max_retries = max_retries
      @thread_pool_size = thread_pool_size
      @byte_limit = byte_limit

      validate!
    end

    private

    def valid_speaking_rate?
      @speaking_rate.is_a?(Numeric) && @speaking_rate >= 0.25 && @speaking_rate <= 4.0
    end

    def valid_pitch?
      @pitch.is_a?(Numeric) && @pitch >= -20.0 && @pitch <= 20.0
    end

    def valid_thread_pool_size?
      @thread_pool_size.is_a?(Integer) && @thread_pool_size.positive?
    end

    def valid_byte_limit?
      @byte_limit.is_a?(Integer) && @byte_limit.positive?
    end

    def valid_max_retries?
      @max_retries.is_a?(Integer) && !@max_retries.negative?
    end

    def validate!
      unless valid_speaking_rate?
        raise ArgumentError,
              "speaking_rate must be between 0.25 and 4.0, got #{@speaking_rate}"
      end
      raise ArgumentError, "pitch must be between -20.0 and 20.0, got #{@pitch}" unless valid_pitch?

      unless valid_thread_pool_size?
        raise ArgumentError,
              "thread_pool_size must be a positive integer, got #{@thread_pool_size}"
      end
      raise ArgumentError, "byte_limit must be a positive integer, got #{@byte_limit}" unless valid_byte_limit?
      raise ArgumentError, "max_retries must be a non-negative integer, got #{@max_retries}" unless valid_max_retries?
    end
  end
end
```

**Step 3: Copy text_chunker.rb (change class to module nesting)**

```ruby
# hub/lib/tts/text_chunker.rb
# frozen_string_literal: true

module Tts
  # Splits text into chunks that fit within a byte limit.
  class TextChunker
    def initialize(logger: nil)
      @logger = logger || Rails.logger
    end

    def chunk(text, max_bytes)
      return [text] if text.bytesize <= max_bytes

      sentences = text.split(/(?<=[.!?])\s+/)
      chunks = []
      current_chunk = ""

      sentences.each do |sentence|
        if sentence.bytesize > max_bytes
          unless current_chunk.empty?
            chunks << current_chunk.strip
            current_chunk = ""
          end
          chunks.concat(split_long_sentence(sentence, max_bytes))
        else
          test_chunk = current_chunk.empty? ? sentence : "#{current_chunk} #{sentence}"
          if test_chunk.bytesize > max_bytes
            chunks << current_chunk.strip unless current_chunk.empty?
            current_chunk = sentence
          else
            current_chunk = test_chunk
          end
        end
      end

      chunks << current_chunk.strip unless current_chunk.empty?
      chunks
    end

    private

    def split_long_sentence(sentence, max_bytes)
      parts = sentence.split(/(?<=[,;:])\s+/)
      result = []
      current_part = ""

      parts.each do |part|
        if part.bytesize > max_bytes
          unless current_part.empty?
            result << current_part
            current_part = ""
          end
          result.concat(split_at_words(part, max_bytes))
        else
          test_part = current_part.empty? ? part : "#{current_part} #{part}"
          if test_part.bytesize > max_bytes
            result << current_part unless current_part.empty?
            current_part = part
          else
            current_part = test_part
          end
        end
      end

      result << current_part unless current_part.empty?
      result
    end

    def split_at_words(text, max_bytes)
      words = text.split(/\s+/)
      chunks = []
      current_chunk = ""

      words.each do |word|
        if word.bytesize > max_bytes
          chunks << current_chunk unless current_chunk.empty?
          @logger.warn "[TTS] Single word exceeds max_bytes: #{word[0..20]}... (#{word.bytesize} bytes)"
          chunks << word
          current_chunk = ""
        else
          test_chunk = current_chunk.empty? ? word : "#{current_chunk} #{word}"
          if test_chunk.bytesize > max_bytes
            chunks << current_chunk unless current_chunk.empty?
            current_chunk = word
          else
            current_chunk = test_chunk
          end
        end
      end

      chunks << current_chunk unless current_chunk.empty?
      chunks
    end
  end
end
```

**Step 4: Copy api_client.rb (change class to module, use Rails.logger)**

```ruby
# hub/lib/tts/api_client.rb
# frozen_string_literal: true

require "google/cloud/text_to_speech"

module Tts
  # Handles communication with Google Cloud Text-to-Speech API.
  class ApiClient
    CONTENT_FILTER_ERROR = "sensitive or harmful content"
    DEADLINE_EXCEEDED_ERROR = "Deadline Exceeded"

    def initialize(config:, logger: nil)
      @config = config
      @logger = logger || Rails.logger

      @client = Google::Cloud::TextToSpeech.text_to_speech do |client_config|
        client_config.timeout = @config.timeout
      end
    end

    def call(text:, voice:)
      @logger.info "[TTS] Making API call (#{text.bytesize} bytes) with voice: #{voice}..."

      response = @client.synthesize_speech(
        input: { text: text },
        voice: build_voice_params(voice),
        audio_config: build_audio_config
      )

      @logger.info "[TTS] API call successful (#{response.audio_content.bytesize} bytes audio)"
      response.audio_content
    rescue StandardError => e
      safe_message = e.message.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
      @logger.error "[TTS] API call failed: #{safe_message}"
      raise
    end

    def call_with_retry(text:, voice:, max_retries: nil)
      max_retries ||= @config.max_retries
      retries = 0

      begin
        call(text: text, voice: voice)
      rescue Google::Cloud::ResourceExhaustedError => e
        raise unless retries < max_retries

        retries += 1
        wait_time = 2**retries
        @logger.warn "[TTS] Rate limit hit, waiting #{wait_time}s (retry #{retries}/#{max_retries})"
        sleep(wait_time)
        retry
      rescue Google::Cloud::Error => e
        safe_message = e.message.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
        raise unless retries < max_retries && safe_message.include?(DEADLINE_EXCEEDED_ERROR)

        retries += 1
        @logger.warn "[TTS] Timeout, retrying (#{retries}/#{max_retries})"
        sleep(1)
        retry
      end
    end

    private

    def build_voice_params(voice)
      {
        language_code: @config.language_code,
        name: voice
      }
    end

    def build_audio_config
      {
        audio_encoding: @config.audio_encoding,
        speaking_rate: @config.speaking_rate,
        pitch: @config.pitch
      }
    end
  end
end
```

**Step 5: Copy chunked_synthesizer.rb (change class to module, use Rails.logger)**

```ruby
# hub/lib/tts/chunked_synthesizer.rb
# frozen_string_literal: true

require "concurrent"

module Tts
  # Handles concurrent synthesis of multiple text chunks.
  class ChunkedSynthesizer
    CONTENT_FILTER_ERROR = "sensitive or harmful content"

    def initialize(api_client:, config:, logger: nil)
      @api_client = api_client
      @config = config
      @logger = logger || Rails.logger
    end

    def synthesize(chunks, voice)
      return "" if chunks.empty?

      log_synthesis_start(chunks)

      start_time = Time.now
      pool = Concurrent::FixedThreadPool.new(@config.thread_pool_size)
      promises = launch_chunk_promises(chunks: chunks, voice: voice, pool: pool)

      results = wait_for_completion(promises)
      audio_parts = extract_audio_parts(results)

      cleanup_pool(pool)
      log_synthesis_complete(chunks: chunks, audio_parts: audio_parts, start_time: start_time)

      audio_parts.join
    end

    private

    def log_synthesis_start(chunks)
      @logger.info "[TTS] Text too long, splitting into #{chunks.length} chunks..."
      @logger.info "[TTS] Processing with #{@config.thread_pool_size} concurrent threads"
      @logger.info "[TTS] Chunk sizes: #{chunks.map(&:bytesize).join(', ')} bytes"
    end

    def launch_chunk_promises(chunks:, voice:, pool:)
      skipped_chunks = Concurrent::Array.new
      promises = []
      total = chunks.length

      chunks.each_with_index do |chunk, i|
        promise = Concurrent::Promise.execute(executor: pool) do
          process_chunk(chunk: chunk, index: i, total: total, voice: voice, skipped_chunks: skipped_chunks)
        end
        promises << promise
      end

      @skipped_chunks = skipped_chunks
      promises
    end

    def process_chunk(chunk:, index:, total:, voice:, skipped_chunks:)
      chunk_num = index + 1
      @logger.info "[TTS] Chunk #{chunk_num}/#{total}: Starting (#{chunk.bytesize} bytes)"

      chunk_start = Time.now
      audio = synthesize_chunk_with_error_handling(chunk: chunk, chunk_num: chunk_num, total: total, voice: voice,
                                                   skipped_chunks: skipped_chunks)

      log_chunk_completion(chunk_num: chunk_num, total: total, chunk_start: chunk_start) if audio

      [index, audio]
    end

    def synthesize_chunk_with_error_handling(chunk:, chunk_num:, total:, voice:, skipped_chunks:)
      @api_client.call_with_retry(text: chunk, voice: voice, max_retries: @config.max_retries)
    rescue StandardError => e
      handle_chunk_error(error: e, chunk_num: chunk_num, total: total, skipped_chunks: skipped_chunks)
      nil
    end

    def handle_chunk_error(error:, chunk_num:, total:, skipped_chunks:)
      safe_message = error.message.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")

      if safe_message.include?(CONTENT_FILTER_ERROR)
        @logger.warn "[TTS] Chunk #{chunk_num}/#{total}: SKIPPED - Content filter"
        skipped_chunks << chunk_num
      else
        @logger.error "[TTS] Chunk #{chunk_num}/#{total}: Failed - #{safe_message}"
        raise
      end
    end

    def log_chunk_completion(chunk_num:, total:, chunk_start:)
      chunk_duration = Time.now - chunk_start
      @logger.info "[TTS] Chunk #{chunk_num}/#{total}: Done in #{chunk_duration.round(2)}s"
    end

    def wait_for_completion(promises)
      @logger.info "[TTS] Waiting for all chunks to complete..."
      promises.map(&:value!)
    end

    def extract_audio_parts(results)
      results
        .compact
        .sort_by { |idx, _| idx }
        .map { |_, audio| audio }
        .compact
    end

    def cleanup_pool(pool)
      pool.shutdown
      pool.wait_for_termination
    end

    def log_synthesis_complete(chunks:, audio_parts:, start_time:)
      total_duration = Time.now - start_time

      if @skipped_chunks.any?
        skipped_list = @skipped_chunks.sort.join(", ")
        @logger.warn "[TTS] Warning: Skipped #{@skipped_chunks.length} chunk(s) due to content filtering: #{skipped_list}"
      end

      @logger.info "[TTS] Concatenating #{audio_parts.length}/#{chunks.length} audio chunks..."
      @logger.info "[TTS] Total processing time: #{total_duration.round(2)}s"
    end
  end
end
```

**Step 6: Create main tts.rb entry point**

```ruby
# hub/lib/tts.rb
# frozen_string_literal: true

require_relative "tts/config"
require_relative "tts/api_client"
require_relative "tts/text_chunker"
require_relative "tts/chunked_synthesizer"

module Tts
  # Text-to-Speech conversion using Google Cloud TTS API.
  class Synthesizer
    def initialize(config: Config.new, logger: nil)
      @config = config
      @logger = logger || Rails.logger

      @api_client = ApiClient.new(config: config, logger: @logger)
      @text_chunker = TextChunker.new(logger: @logger)
      @chunked_synthesizer = ChunkedSynthesizer.new(api_client: @api_client, config: config, logger: @logger)
    end

    def synthesize(text, voice: nil)
      @logger.info "[TTS] Generating audio..."
      voice ||= @config.voice_name

      chunks = @text_chunker.chunk(text, @config.byte_limit)

      audio_content = if chunks.length == 1
                        @api_client.call(text: chunks[0], voice: voice)
                      else
                        @chunked_synthesizer.synthesize(chunks, voice)
                      end

      @logger.info "[TTS] Generated #{format_size(audio_content.bytesize)}"
      audio_content
    end

    private

    def format_size(bytes)
      if bytes < 1024
        "#{bytes} bytes"
      elsif bytes < 1_048_576
        "#{(bytes / 1024.0).round(1)} KB"
      else
        "#{(bytes / 1_048_576.0).round(1)} MB"
      end
    end
  end
end
```

**Step 7: Add autoload to Rails**

```ruby
# hub/config/initializers/tts.rb
# frozen_string_literal: true

require_relative "../../lib/tts"
```

**Step 8: Verify the library loads**

Run: `bin/rails runner "puts Tts::Synthesizer.new.class"`
Expected: `Tts::Synthesizer`

**Step 9: Commit**

```bash
git add lib/tts lib/tts.rb config/initializers/tts.rb
git commit -m "feat: add TTS library to Hub

Copy TTS synthesis library from generator with Rails adaptations:
- Change TTS class to Tts module namespace
- Replace puts with Rails.logger
- Add [TTS] prefix to all log messages"
```

---

## Task 2: Create RSS Feed Generator Service

**Files:**
- Create: `hub/app/services/generate_rss_feed.rb`
- Create: `hub/test/services/generate_rss_feed_test.rb`

**Step 1: Write the failing test**

```ruby
# hub/test/services/generate_rss_feed_test.rb
# frozen_string_literal: true

require "test_helper"

class GenerateRssFeedTest < ActiveSupport::TestCase
  setup do
    @podcast = podcasts(:default)
    @episode = episodes(:complete)
  end

  test "generates valid RSS XML with podcast metadata" do
    result = GenerateRssFeed.call(podcast: @podcast)

    assert result.include?('<?xml version="1.0" encoding="UTF-8"?>')
    assert result.include?("<rss")
    assert result.include?("xmlns:itunes")
    assert result.include?("<title>Very normal podcast</title>")
  end

  test "includes completed episodes in feed" do
    result = GenerateRssFeed.call(podcast: @podcast)

    assert result.include?("<item>")
    assert result.include?("<title>#{@episode.title}</title>")
    assert result.include?("<enclosure")
  end

  test "excludes pending and failed episodes" do
    pending_episode = episodes(:pending)
    failed_episode = episodes(:failed)

    result = GenerateRssFeed.call(podcast: @podcast)

    refute result.include?(pending_episode.title)
    refute result.include?(failed_episode.title)
  end

  test "excludes deleted episodes" do
    @episode.update!(deleted_at: Time.current)

    result = GenerateRssFeed.call(podcast: @podcast)

    refute result.include?(@episode.title)
  end

  test "orders episodes by created_at descending" do
    older_episode = Episode.create!(
      podcast: @podcast,
      user: @episode.user,
      title: "Older Episode",
      author: "Test",
      description: "Older",
      status: "complete",
      gcs_episode_id: "older-episode",
      created_at: 1.day.ago
    )

    result = GenerateRssFeed.call(podcast: @podcast)

    # Newer episode should appear first in the XML
    newer_pos = result.index(@episode.title)
    older_pos = result.index(older_episode.title)
    assert newer_pos < older_pos, "Newer episode should appear before older episode"
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/generate_rss_feed_test.rb`
Expected: FAIL with "uninitialized constant GenerateRssFeed"

**Step 3: Write minimal implementation**

```ruby
# hub/app/services/generate_rss_feed.rb
# frozen_string_literal: true

class GenerateRssFeed
  PODCAST_DEFAULTS = {
    "title" => "Very normal podcast",
    "description" => "Readings turned to audio by text to speech app.",
    "author" => "Very Normal TTS",
    "email" => "noreply@tts.verynormal.dev",
    "link" => "https://tts.verynormal.dev",
    "language" => "en-us",
    "category" => "Technology",
    "explicit" => false,
    "artwork_url" => "https://verynormal.info/content/images/2022/11/verynormallogo2.png"
  }.freeze

  def self.call(podcast:)
    new(podcast: podcast).call
  end

  def initialize(podcast:)
    @podcast = podcast
  end

  def call
    xml = Builder::XmlMarkup.new(indent: 2)
    xml.instruct! :xml, version: "1.0", encoding: "UTF-8"

    xml.rss version: "2.0",
            "xmlns:itunes" => "http://www.itunes.com/dtds/podcast-1.0.dtd",
            "xmlns:content" => "http://purl.org/rss/1.0/modules/content/",
            "xmlns:atom" => "http://www.w3.org/2005/Atom" do
      xml.channel do
        add_podcast_metadata(xml)
        add_episodes(xml)
      end
    end

    xml.target!
  end

  private

  def podcast_config
    @podcast_config ||= PODCAST_DEFAULTS.merge(
      "title" => @podcast.title || PODCAST_DEFAULTS["title"],
      "description" => @podcast.description || PODCAST_DEFAULTS["description"],
      "feed_url" => @podcast.feed_url
    )
  end

  def episodes
    @episodes ||= @podcast.episodes
                          .where(status: "complete")
                          .where(deleted_at: nil)
                          .order(created_at: :desc)
  end

  def add_podcast_metadata(xml)
    xml.title podcast_config["title"]
    xml.description podcast_config["description"]
    xml.link podcast_config["link"]
    if podcast_config["feed_url"]
      xml.tag! "atom:link", href: podcast_config["feed_url"], rel: "self", type: "application/rss+xml"
    end
    xml.language podcast_config["language"]
    xml.tag! "itunes:author", podcast_config["author"]
    xml.tag! "itunes:email", podcast_config["email"]
    xml.tag! "itunes:explicit", podcast_config["explicit"].to_s
    xml.tag! "itunes:category", text: podcast_config["category"]
    xml.tag! "itunes:image", href: podcast_config["artwork_url"]
  end

  def add_episodes(xml)
    episodes.each do |episode|
      add_episode_item(xml, episode)
    end
  end

  def add_episode_item(xml, episode)
    xml.item do
      xml.title episode.title
      xml.description episode.description
      xml.tag! "itunes:author", episode.author

      xml.enclosure url: episode_mp3_url(episode),
                    type: "audio/mpeg",
                    length: episode.audio_size_bytes || 0

      xml.guid episode.gcs_episode_id, isPermaLink: "false"
      xml.pubDate episode.created_at.rfc2822

      add_duration(xml, episode.duration_seconds)
    end
  end

  def episode_mp3_url(episode)
    bucket = ENV.fetch("GOOGLE_CLOUD_BUCKET", "verynormal-tts-podcast")
    "https://storage.googleapis.com/#{bucket}/podcasts/#{@podcast.podcast_id}/episodes/#{episode.gcs_episode_id}.mp3"
  end

  def add_duration(xml, duration_seconds)
    return unless duration_seconds

    minutes = duration_seconds / 60
    seconds = duration_seconds % 60
    xml.tag! "itunes:duration", format("%<min>d:%<sec>02d", min: minutes, sec: seconds)
  end
end
```

**Step 4: Add test fixtures**

Add to `test/fixtures/episodes.yml`:

```yaml
complete:
  podcast: default
  user: jesse
  title: "Complete Episode"
  author: "Test Author"
  description: "A complete episode"
  status: "complete"
  gcs_episode_id: "20251226-120000-complete-episode"
  audio_size_bytes: 1024000
  duration_seconds: 300

pending:
  podcast: default
  user: jesse
  title: "Pending Episode"
  author: "Test Author"
  description: "A pending episode"
  status: "pending"

failed:
  podcast: default
  user: jesse
  title: "Failed Episode"
  author: "Test Author"
  description: "A failed episode"
  status: "failed"
  error_message: "Something went wrong"
```

**Step 5: Run test to verify it passes**

Run: `bin/rails test test/services/generate_rss_feed_test.rb`
Expected: All tests PASS

**Step 6: Commit**

```bash
git add app/services/generate_rss_feed.rb test/services/generate_rss_feed_test.rb test/fixtures/episodes.yml
git commit -m "feat: add GenerateRssFeed service

Generate RSS feed from Episode database records instead of manifest.json.
Includes hardcoded podcast defaults matching config/podcast.yml."
```

---

## Task 3: Create GenerateEpisodeAudio Service

**Files:**
- Create: `hub/app/services/generate_episode_audio.rb`
- Create: `hub/test/services/generate_episode_audio_test.rb`

**Step 1: Write the failing test**

```ruby
# hub/test/services/generate_episode_audio_test.rb
# frozen_string_literal: true

require "test_helper"

class GenerateEpisodeAudioTest < ActiveSupport::TestCase
  setup do
    @episode = episodes(:pending)
    @episode.update!(source_text: "Hello, this is a test episode.")
  end

  test "synthesizes audio and updates episode" do
    mock_synthesizer = Minitest::Mock.new
    mock_synthesizer.expect :synthesize, "fake audio content", [String], voice: String

    mock_gcs = Minitest::Mock.new
    mock_gcs.expect :upload_content, "https://storage.googleapis.com/bucket/episodes/test.mp3", [{ content: String, remote_path: String }]

    mock_feed_uploader = Minitest::Mock.new
    mock_feed_uploader.expect :upload_content, nil, [{ content: String, remote_path: "feed.xml" }]

    Tts::Synthesizer.stub :new, mock_synthesizer do
      GcsUploader.stub :new, ->(*) { mock_gcs } do
        # Skip feed upload for this test
        GenerateEpisodeAudio.call(episode: @episode, skip_feed_upload: true)
      end
    end

    @episode.reload
    assert_equal "complete", @episode.status
    assert_not_nil @episode.gcs_episode_id
  end

  test "marks episode as failed on error" do
    mock_synthesizer = Minitest::Mock.new
    def mock_synthesizer.synthesize(*)
      raise StandardError, "TTS API error"
    end

    Tts::Synthesizer.stub :new, mock_synthesizer do
      GenerateEpisodeAudio.call(episode: @episode)
    end

    @episode.reload
    assert_equal "failed", @episode.status
    assert_equal "TTS API error", @episode.error_message
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/generate_episode_audio_test.rb`
Expected: FAIL with "uninitialized constant GenerateEpisodeAudio"

**Step 3: Write minimal implementation**

```ruby
# hub/app/services/generate_episode_audio.rb
# frozen_string_literal: true

require "tempfile"
require "mp3info"

class GenerateEpisodeAudio
  def self.call(episode:, skip_feed_upload: false)
    new(episode: episode, skip_feed_upload: skip_feed_upload).call
  end

  def initialize(episode:, skip_feed_upload: false)
    @episode = episode
    @skip_feed_upload = skip_feed_upload
  end

  def call
    Rails.logger.info "event=generate_episode_audio_started episode_id=#{@episode.id}"

    @episode.update!(status: "processing")

    audio_content = synthesize_audio
    gcs_episode_id = generate_episode_id
    upload_audio(audio_content, gcs_episode_id)
    duration_seconds = calculate_duration(audio_content)

    @episode.update!(
      status: "complete",
      gcs_episode_id: gcs_episode_id,
      audio_size_bytes: audio_content.bytesize,
      duration_seconds: duration_seconds
    )

    upload_feed unless @skip_feed_upload

    Rails.logger.info "event=generate_episode_audio_completed episode_id=#{@episode.id} gcs_episode_id=#{gcs_episode_id}"

    notify_user
  rescue StandardError => e
    Rails.logger.error "event=generate_episode_audio_failed episode_id=#{@episode.id} error=#{e.class} message=#{e.message}"
    @episode.update!(status: "failed", error_message: e.message)
  end

  private

  def synthesize_audio
    config = Tts::Config.new(voice_name: voice_name)
    synthesizer = Tts::Synthesizer.new(config: config)
    synthesizer.synthesize(content_text)
  end

  def voice_name
    @episode.user&.voice_preference || "en-GB-Chirp3-HD-Enceladus"
  end

  def content_text
    @episode.source_text || ""
  end

  def generate_episode_id
    timestamp = Time.now.strftime("%Y%m%d-%H%M%S")
    slug = @episode.title.downcase
                   .gsub(/[^a-z0-9\s-]/, "")
                   .gsub(/\s+/, "-")
                   .gsub(/-+/, "-")
                   .strip
    "#{timestamp}-#{slug}"
  end

  def upload_audio(audio_content, gcs_episode_id)
    gcs_uploader.upload_content(
      content: audio_content,
      remote_path: "episodes/#{gcs_episode_id}.mp3"
    )
  end

  def calculate_duration(audio_content)
    Tempfile.create(["episode", ".mp3"]) do |temp_file|
      temp_file.binmode
      temp_file.write(audio_content)
      temp_file.close
      Mp3Info.open(temp_file.path) { |mp3| mp3.length.round }
    end
  end

  def upload_feed
    feed_xml = GenerateRssFeed.call(podcast: @episode.podcast)
    gcs_uploader.upload_content(content: feed_xml, remote_path: "feed.xml")
  end

  def gcs_uploader
    @gcs_uploader ||= GcsUploader.new(podcast_id: @episode.podcast.podcast_id)
  end

  def notify_user
    EpisodeCompletionNotifier.call(episode: @episode) if @episode.user&.email_address.present?
  rescue StandardError => e
    Rails.logger.warn "event=notification_failed episode_id=#{@episode.id} error=#{e.message}"
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/generate_episode_audio_test.rb`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add app/services/generate_episode_audio.rb test/services/generate_episode_audio_test.rb
git commit -m "feat: add GenerateEpisodeAudio service

Main service for internal TTS processing:
- Synthesizes audio using Tts::Synthesizer
- Uploads MP3 to GCS
- Calculates duration with mp3info
- Updates episode record with results
- Regenerates RSS feed
- Notifies user on completion
- Marks episode as failed on error"
```

---

## Task 4: Create GenerateAudioJob

**Files:**
- Create: `hub/app/jobs/generate_audio_job.rb`
- Create: `hub/test/jobs/generate_audio_job_test.rb`

**Step 1: Write the failing test**

```ruby
# hub/test/jobs/generate_audio_job_test.rb
# frozen_string_literal: true

require "test_helper"

class GenerateAudioJobTest < ActiveJob::TestCase
  test "calls GenerateEpisodeAudio service" do
    episode = episodes(:pending)

    service_called = false
    GenerateEpisodeAudio.stub :call, ->(episode:) { service_called = true } do
      GenerateAudioJob.perform_now(episode)
    end

    assert service_called, "GenerateEpisodeAudio.call should have been called"
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/jobs/generate_audio_job_test.rb`
Expected: FAIL with "uninitialized constant GenerateAudioJob"

**Step 3: Write minimal implementation**

```ruby
# hub/app/jobs/generate_audio_job.rb
# frozen_string_literal: true

class GenerateAudioJob < ApplicationJob
  queue_as :default

  def perform(episode)
    Rails.logger.info "event=generate_audio_job_started episode_id=#{episode.id}"
    GenerateEpisodeAudio.call(episode: episode)
    Rails.logger.info "event=generate_audio_job_completed episode_id=#{episode.id}"
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/jobs/generate_audio_job_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add app/jobs/generate_audio_job.rb test/jobs/generate_audio_job_test.rb
git commit -m "feat: add GenerateAudioJob

Thin job wrapper that delegates to GenerateEpisodeAudio service."
```

---

## Task 5: Add Feature Flag to SubmitEpisodeForProcessing

**Files:**
- Modify: `hub/app/services/submit_episode_for_processing.rb`
- Modify: `hub/test/services/submit_episode_for_processing_test.rb`

**Step 1: Write the failing test**

Add to `hub/test/services/submit_episode_for_processing_test.rb`:

```ruby
test "uses internal TTS for allowlisted podcasts" do
  episode = episodes(:pending)
  episode.podcast.update!(podcast_id: "podcast_195c82bf8eeb2aae")
  episode.update!(source_text: "Test content")

  assert_enqueued_with(job: GenerateAudioJob) do
    SubmitEpisodeForProcessing.call(episode: episode, content: "Test content")
  end
end

test "uses external generator for non-allowlisted podcasts" do
  episode = episodes(:pending)
  episode.podcast.update!(podcast_id: "podcast_other")

  # Should NOT enqueue GenerateAudioJob
  GenerateAudioJob.stub :perform_later, ->(*) { raise "Should not be called" } do
    # Mock the external path
    UploadEpisodeContent.stub :call, "staging/test.txt" do
      EnqueueEpisodeProcessing.stub :call, nil do
        SubmitEpisodeForProcessing.call(episode: episode, content: "Test content")
      end
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/submit_episode_for_processing_test.rb`
Expected: FAIL (no routing to internal TTS)

**Step 3: Update implementation**

```ruby
# hub/app/services/submit_episode_for_processing.rb
# frozen_string_literal: true

class SubmitEpisodeForProcessing
  # Podcasts that use internal TTS processing (Hub) instead of external generator (Cloud Run)
  INTERNAL_TTS_PODCAST_IDS = [
    "podcast_195c82bf8eeb2aae"  # Jesse's podcast for testing
  ].freeze

  def self.call(episode:, content:)
    new(episode: episode, content: content).call
  end

  def initialize(episode:, content:)
    @episode = episode
    @content = content
  end

  def call
    if use_internal_tts?
      process_internally
    else
      process_externally
    end
  end

  private

  attr_reader :episode, :content

  def use_internal_tts?
    INTERNAL_TTS_PODCAST_IDS.include?(episode.podcast.podcast_id)
  end

  def process_internally
    Rails.logger.info "event=internal_tts_selected episode_id=#{episode.id} podcast_id=#{episode.podcast.podcast_id}"

    # Store the wrapped content for the job to use
    wrapped = wrap_content
    episode.update!(source_text: wrapped)

    GenerateAudioJob.perform_later(episode)

    Rails.logger.info "event=internal_processing_enqueued episode_id=#{episode.id}"
  end

  def process_externally
    staging_path = upload_content(wrap_content)

    Rails.logger.info "event=staging_uploaded episode_id=#{episode.id} staging_path=#{staging_path} size_bytes=#{content.bytesize}"

    enqueue_processing(staging_path)

    Rails.logger.info "event=processing_enqueued episode_id=#{episode.id}"
  end

  def wrap_content
    BuildEpisodeWrapper.call(
      title: episode.title,
      author: episode.author,
      tier: episode.user.tier,
      content: content
    )
  end

  def upload_content(wrapped_content)
    UploadEpisodeContent.call(episode: episode, content: wrapped_content)
  end

  def enqueue_processing(staging_path)
    EnqueueEpisodeProcessing.call(episode: episode, staging_path: staging_path)
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/submit_episode_for_processing_test.rb`
Expected: All tests PASS

**Step 5: Run full test suite**

Run: `bin/rails test`
Expected: All tests PASS

**Step 6: Commit**

```bash
git add app/services/submit_episode_for_processing.rb test/services/submit_episode_for_processing_test.rb
git commit -m "feat: add internal TTS routing via podcast allowlist

Route episodes from allowlisted podcasts to GenerateAudioJob instead
of external Cloud Tasks generator. Currently enabled for Jesse's
podcast (podcast_195c82bf8eeb2aae) for testing."
```

---

## Task 6: Update DeleteEpisodeJob to Use Database-Based Feed

**Files:**
- Modify: `hub/app/jobs/delete_episode_job.rb`
- Modify: `hub/test/jobs/delete_episode_job_test.rb`

**Step 1: Read current implementation**

```ruby
# Current delete_episode_job.rb uses EpisodeManifest
# We need to replace it with GenerateRssFeed
```

**Step 2: Write updated test**

```ruby
# hub/test/jobs/delete_episode_job_test.rb
# frozen_string_literal: true

require "test_helper"

class DeleteEpisodeJobTest < ActiveJob::TestCase
  setup do
    @episode = episodes(:complete)
  end

  test "deletes MP3 from GCS" do
    deleted_path = nil
    mock_gcs = Minitest::Mock.new
    mock_gcs.expect :delete_file, true, [{ remote_path: String }]
    mock_gcs.expect :upload_content, nil, [{ content: String, remote_path: "feed.xml" }]

    GcsUploader.stub :new, ->(*) { mock_gcs } do
      DeleteEpisodeJob.perform_now(@episode)
    end

    mock_gcs.verify
  end

  test "soft deletes episode record" do
    mock_gcs = Minitest::Mock.new
    mock_gcs.expect :delete_file, true, [{ remote_path: String }]
    mock_gcs.expect :upload_content, nil, [{ content: String, remote_path: "feed.xml" }]

    GcsUploader.stub :new, ->(*) { mock_gcs } do
      DeleteEpisodeJob.perform_now(@episode)
    end

    @episode.reload
    assert_not_nil @episode.deleted_at
  end

  test "regenerates RSS feed from database" do
    feed_content = nil
    mock_gcs = Object.new
    def mock_gcs.delete_file(*); true; end
    mock_gcs.define_singleton_method(:upload_content) do |content:, remote_path:|
      feed_content = content if remote_path == "feed.xml"
    end

    GcsUploader.stub :new, ->(*) { mock_gcs } do
      DeleteEpisodeJob.perform_now(@episode)
    end

    assert_not_nil feed_content
    assert feed_content.include?("<?xml")
    refute feed_content.include?(@episode.title), "Deleted episode should not be in feed"
  end
end
```

**Step 3: Update implementation**

```ruby
# hub/app/jobs/delete_episode_job.rb
# frozen_string_literal: true

class DeleteEpisodeJob < ApplicationJob
  queue_as :default

  def perform(episode)
    Rails.logger.info "event=delete_episode_started episode_id=#{episode.id}"

    delete_audio_file(episode)
    soft_delete_episode(episode)
    regenerate_feed(episode.podcast)

    Rails.logger.info "event=delete_episode_completed episode_id=#{episode.id}"
  end

  private

  def delete_audio_file(episode)
    return unless episode.gcs_episode_id.present?

    gcs_uploader(episode).delete_file(remote_path: "episodes/#{episode.gcs_episode_id}.mp3")
    Rails.logger.info "event=audio_file_deleted episode_id=#{episode.id} gcs_episode_id=#{episode.gcs_episode_id}"
  rescue StandardError => e
    Rails.logger.warn "event=audio_delete_failed episode_id=#{episode.id} error=#{e.message}"
  end

  def soft_delete_episode(episode)
    episode.update!(deleted_at: Time.current)
  end

  def regenerate_feed(podcast)
    feed_xml = GenerateRssFeed.call(podcast: podcast)
    gcs_uploader_for_podcast(podcast).upload_content(content: feed_xml, remote_path: "feed.xml")
    Rails.logger.info "event=feed_regenerated podcast_id=#{podcast.podcast_id}"
  end

  def gcs_uploader(episode)
    GcsUploader.new(podcast_id: episode.podcast.podcast_id)
  end

  def gcs_uploader_for_podcast(podcast)
    GcsUploader.new(podcast_id: podcast.podcast_id)
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/jobs/delete_episode_job_test.rb`
Expected: All tests PASS

**Step 5: Delete the now-unused EpisodeManifest class**

Run: `rm app/services/episode_manifest.rb test/services/episode_manifest_test.rb`

**Step 6: Run full test suite**

Run: `bin/rails test`
Expected: All tests PASS

**Step 7: Commit**

```bash
git add app/jobs/delete_episode_job.rb test/jobs/delete_episode_job_test.rb
git rm app/services/episode_manifest.rb test/services/episode_manifest_test.rb
git commit -m "refactor: delete job uses GenerateRssFeed instead of manifest

Replace manifest.json-based feed regeneration with database-based
GenerateRssFeed service. Remove now-unused EpisodeManifest class."
```

---

## Task 7: Deploy and Test

**Step 1: Run full test suite locally**

Run: `bin/rails test`
Expected: All tests PASS

**Step 2: Commit any remaining changes**

```bash
git status
# If clean, proceed. Otherwise commit.
```

**Step 3: Deploy to production**

Run: `bin/kamal deploy`
Expected: Successful deployment

**Step 4: Create a test episode**

1. Log in to https://tts.verynormal.dev
2. Submit a short URL or paste text
3. Wait for processing to complete
4. Verify:
   - Episode shows as "complete" in UI
   - Audio plays correctly
   - Episode appears in RSS feed

**Step 5: Monitor logs**

Run: `bin/kamal logs -f`
Expected: See `[TTS]` prefixed logs for internal processing

**Step 6: Commit verification notes**

```bash
git commit --allow-empty -m "chore: verified internal TTS working in production

Tested with Jesse's podcast (podcast_195c82bf8eeb2aae):
- Episode processed successfully
- Audio plays correctly
- RSS feed updated"
```

---

## Task 8: Enable for All Podcasts

**Files:**
- Modify: `hub/app/services/submit_episode_for_processing.rb`

**Step 1: Update to route all podcasts internally**

```ruby
# hub/app/services/submit_episode_for_processing.rb
# frozen_string_literal: true

class SubmitEpisodeForProcessing
  def self.call(episode:, content:)
    new(episode: episode, content: content).call
  end

  def initialize(episode:, content:)
    @episode = episode
    @content = content
  end

  def call
    Rails.logger.info "event=internal_tts_processing episode_id=#{episode.id} podcast_id=#{episode.podcast.podcast_id}"

    wrapped = wrap_content
    episode.update!(source_text: wrapped)

    GenerateAudioJob.perform_later(episode)

    Rails.logger.info "event=processing_enqueued episode_id=#{episode.id}"
  end

  private

  attr_reader :episode, :content

  def wrap_content
    BuildEpisodeWrapper.call(
      title: episode.title,
      author: episode.author,
      tier: episode.user.tier,
      content: content
    )
  end
end
```

**Step 2: Remove unused external processing services**

```bash
git rm app/services/upload_episode_content.rb
git rm app/services/enqueue_episode_processing.rb
git rm app/services/cloud_tasks_enqueuer.rb
git rm test/services/upload_episode_content_test.rb
git rm test/services/enqueue_episode_processing_test.rb
git rm test/services/cloud_tasks_enqueuer_test.rb
```

**Step 3: Remove callback API endpoint**

```bash
git rm app/controllers/api/internal/episodes_controller.rb
git rm test/controllers/api/internal/episodes_controller_test.rb
```

**Step 4: Update routes**

Remove from `config/routes.rb`:
```ruby
namespace :api do
  namespace :internal do
    resources :episodes, only: [:update]
  end
end
```

**Step 5: Run tests**

Run: `bin/rails test`
Expected: All tests PASS (some may need fixture updates)

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: all podcasts use internal TTS processing

Remove external generator path:
- Remove Cloud Tasks enqueuer and related services
- Remove callback API endpoint
- Simplify SubmitEpisodeForProcessing to always use internal path"
```

**Step 7: Deploy**

Run: `bin/kamal deploy`

---

## Task 9: Cleanup Generator Code (Post-Migration)

After confirming internal processing works for all users:

**Step 1: Remove generator from deployment**

Update `.github/workflows/deploy.yml` to remove generator deployment.

**Step 2: Delete Cloud Run service**

Run: `gcloud run services delete tts-generator --region=us-west3`

**Step 3: Delete Cloud Tasks queue**

Run: `gcloud tasks queues delete episode-processing --location=us-west3`

**Step 4: Archive generator code**

```bash
# From repo root (not hub/)
git rm -r lib/ test/ api.rb config.ru Dockerfile Gemfile Gemfile.lock Rakefile config/
git commit -m "chore: remove generator code after migration to Hub

All TTS processing now happens in Hub via Solid Queue.
Generator Cloud Run service has been deleted.
Cloud Tasks queue has been deleted."
```

---

## Summary

| Task | Description | Status |
|------|-------------|--------|
| 1 | Copy TTS library to Hub | ☐ |
| 2 | Create RSS feed generator service | ☐ |
| 3 | Create GenerateEpisodeAudio service | ☐ |
| 4 | Create GenerateAudioJob | ☐ |
| 5 | Add feature flag routing | ☐ |
| 6 | Update delete job to use DB feed | ☐ |
| 7 | Deploy and test | ☐ |
| 8 | Enable for all podcasts | ☐ |
| 9 | Cleanup generator code | ☐ |

**Rollback at any point:** Set `INTERNAL_TTS_PODCAST_IDS = []` and redeploy.
