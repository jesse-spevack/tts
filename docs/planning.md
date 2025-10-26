# Project Plan: Text-to-Speech Podcast Feed (Ruby)

## Phase 1: Setup & Infrastructure (Day 1)

### 1.1 Google Cloud Setup
- [ ] Create Google Cloud account (if needed)
- [ ] Create new GCP project
- [ ] Enable billing
- [ ] Enable required APIs:
  - Cloud Text-to-Speech API
  - Cloud Functions API (2nd generation)
  - Cloud Storage API
  - Firestore API
  - Cloud Build API
- [ ] Install Google Cloud SDK locally
  ```bash
  # macOS
  brew install google-cloud-sdk
  
  # Or download from https://cloud.google.com/sdk/docs/install
  ```
- [ ] Authenticate: 
  ```bash
  gcloud auth login
  gcloud auth application-default login
  ```
- [ ] Set default project: 
  ```bash
  gcloud config set project YOUR_PROJECT_ID
  ```

### 1.2 Create Cloud Storage Bucket
- [ ] Create bucket:
  ```bash
  gsutil mb -l us-central1 gs://your-podcast-bucket
  ```
- [ ] Set CORS configuration (optional, for web access):
  ```bash
  echo '[{"origin": ["*"], "method": ["GET"], "maxAgeSeconds": 3600}]' > cors.json
  gsutil cors set cors.json gs://your-podcast-bucket
  ```
- [ ] Test bucket access:
  ```bash
  gsutil ls gs://your-podcast-bucket
  ```

### 1.3 Setup Firestore
- [ ] Go to Firestore console: https://console.cloud.google.com/firestore
- [ ] Create database (Native mode)
- [ ] Choose region (same as your Cloud Functions, e.g., us-central1)
- [ ] Start in production mode
- [ ] Note your project ID for configuration

### 1.4 Local Development Environment
- [ ] Create project directory:
  ```bash
  mkdir podcast-tts
  cd podcast-tts
  ```
- [ ] Initialize Ruby project:
  ```bash
  bundle init
  ```
- [ ] Create `Gemfile`:
  ```ruby
  source 'https://rubygems.org'

  gem 'google-cloud-text_to_speech', '~> 1.0'
  gem 'google-cloud-storage', '~> 1.44'
  gem 'google-cloud-firestore', '~> 2.0'
  gem 'nokogiri', '~> 1.15'
  gem 'ruby-readability', '~> 0.7'
  gem 'httparty', '~> 0.21'
  gem 'functions_framework', '~> 1.4'
  ```
- [ ] Install dependencies:
  ```bash
  bundle install
  ```
- [ ] Create directory structure:
  ```bash
  mkdir -p lib/{extractor,tts,storage,database,rss}
  touch lib/extractor.rb
  touch lib/tts.rb
  touch lib/storage.rb
  touch lib/database.rb
  touch lib/rss_generator.rb
  ```

## Phase 2: Core Functionality (Days 2-3)

### 2.1 Text Extraction Module
- [ ] Create `lib/extractor.rb`:
  ```ruby
  require 'httparty'
  require 'readability'
  require 'nokogiri'

  module Extractor
    def self.extract(url)
      response = HTTParty.get(url, {
        headers: { 'User-Agent' => 'Mozilla/5.0 (compatible; PodcastBot/1.0)' },
        timeout: 10
      })
      
      raise "Failed to fetch URL: #{response.code}" unless response.success?
      
      doc = Readability::Document.new(response.body)
      
      {
        url: url,
        title: doc.title || extract_title_fallback(response.body),
        text: clean_text(doc.content),
        author: doc.author,
        date: Time.now
      }
    rescue StandardError => e
      raise "Extraction failed: #{e.message}"
    end

    def self.extract_title_fallback(html)
      doc = Nokogiri::HTML(html)
      doc.css('title').first&.text || 'Untitled Article'
    end

    def self.clean_text(content)
      # Strip HTML tags and clean up whitespace
      doc = Nokogiri::HTML(content)
      text = doc.text
      text.gsub(/\s+/, ' ').strip
    end
  end
  ```
- [ ] Test with sample URLs:
  ```ruby
  # test_extractor.rb
  require_relative 'lib/extractor'

  urls = [
    'https://example.com/article1',
    'https://example.com/article2',
    'https://example.com/article3'
  ]

  urls.each do |url|
    article = Extractor.extract(url)
    puts "Title: #{article[:title]}"
    puts "Length: #{article[:text].length} characters"
    puts "---"
  end
  ```
- [ ] Handle edge cases (paywalls, JavaScript-heavy sites, etc.)

### 2.2 Text-to-Speech Module
- [ ] Create `lib/tts.rb`:
  ```ruby
  require 'google/cloud/text_to_speech'

  module TTS
    MAX_CHARS = 5000 # Google TTS limit

    def self.synthesize(text, voice_name: 'en-US-Neural2-F')
      client = Google::Cloud::TextToSpeech.text_to_speech
      
      # Split text if too long
      chunks = split_text(text)
      audio_parts = []

      chunks.each do |chunk|
        input = { text: chunk }
        voice = {
          language_code: 'en-US',
          name: voice_name
        }
        audio_config = {
          audio_encoding: 'MP3',
          speaking_rate: 1.0,
          pitch: 0.0
        }

        response = client.synthesize_speech(
          input: input,
          voice: voice,
          audio_config: audio_config
        )

        audio_parts << response.audio_content
      end

      # If multiple chunks, concatenate (or return array for separate files)
      audio_parts.length == 1 ? audio_parts.first : concatenate_audio(audio_parts)
    end

    def self.split_text(text)
      return [text] if text.length <= MAX_CHARS

      chunks = []
      sentences = text.split(/(?<=[.!?])\s+/)
      current_chunk = ''

      sentences.each do |sentence|
        if (current_chunk + sentence).length <= MAX_CHARS
          current_chunk += sentence + ' '
        else
          chunks << current_chunk.strip unless current_chunk.empty?
          current_chunk = sentence + ' '
        end
      end

      chunks << current_chunk.strip unless current_chunk.empty?
      chunks
    end

    def self.concatenate_audio(audio_parts)
      # Simple concatenation (MP3 frames can be concatenated)
      audio_parts.join
    end
  end
  ```
- [ ] Test with sample text:
  ```ruby
  # test_tts.rb
  require_relative 'lib/tts'

  sample_text = "This is a test of the text to speech system. " * 100
  audio = TTS.synthesize(sample_text)
  
  File.write('test_audio.mp3', audio, mode: 'wb')
  puts "Generated audio: #{audio.bytesize} bytes"
  ```
- [ ] Test voice options (listen to output)
- [ ] Verify audio quality

### 2.3 Storage Module
- [ ] Create `lib/storage.rb`:
  ```ruby
  require 'google/cloud/storage'
  require 'digest'

  module Storage
    BUCKET_NAME = ENV['PODCAST_BUCKET'] || 'your-podcast-bucket'

    def self.client
      @client ||= Google::Cloud::Storage.new
    end

    def self.bucket
      @bucket ||= client.bucket(BUCKET_NAME)
    end

    def self.upload_audio(user_id, audio_content, title)
      filename = generate_filename(title)
      path = "podcasts/#{user_id}/audio/#{filename}"

      file = bucket.create_file(
        StringIO.new(audio_content),
        path,
        content_type: 'audio/mpeg',
        cache_control: 'public, max-age=3600'
      )

      # Make publicly accessible
      file.acl.public!

      {
        url: file.public_url,
        path: path,
        size: audio_content.bytesize
      }
    end

    def self.upload_feed(user_id, feed_xml)
      path = "podcasts/#{user_id}/feed.xml"

      file = bucket.create_file(
        StringIO.new(feed_xml),
        path,
        content_type: 'application/rss+xml',
        cache_control: 'public, max-age=300'
      )

      file.acl.public!
      file.public_url
    end

    def self.generate_filename(title)
      timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
      sanitized = title.downcase.gsub(/[^a-z0-9]+/, '-')[0..50]
      "#{timestamp}_#{sanitized}.mp3"
    end
  end
  ```
- [ ] Test upload:
  ```ruby
  # test_storage.rb
  require_relative 'lib/storage'

  test_content = "test audio content"
  result = Storage.upload_audio('default', test_content, 'Test Article')
  
  puts "Uploaded to: #{result[:url]}"
  puts "Size: #{result[:size]} bytes"
  ```
- [ ] Verify file is publicly accessible (open URL in browser)

### 2.4 Database Module
- [ ] Create `lib/database.rb`:
  ```ruby
  require 'google/cloud/firestore'

  module Database
    def self.firestore
      @firestore ||= Google::Cloud::Firestore.new
    end

    def self.save_article(user_id, article_data)
      doc_id = Digest::SHA256.hexdigest(article_data[:url])[0..15]
      
      doc_ref = firestore.col('users').doc(user_id).col('articles').doc(doc_id)
      
      data = {
        url: article_data[:url],
        title: article_data[:title],
        author: article_data[:author],
        audio_url: article_data[:audio_url],
        audio_size: article_data[:audio_size],
        text_length: article_data[:text]&.length || 0,
        created_at: article_data[:date] || Time.now,
        status: 'completed'
      }

      doc_ref.set(data)
      doc_id
    end

    def self.get_articles(user_id, limit: 100)
      articles = []
      
      firestore
        .col('users').doc(user_id).col('articles')
        .order('created_at', 'desc')
        .limit(limit)
        .get do |article|
          articles << article.data.merge(id: article.document_id)
        end

      articles
    end

    def self.article_exists?(user_id, url)
      doc_id = Digest::SHA256.hexdigest(url)[0..15]
      doc_ref = firestore.col('users').doc(user_id).col('articles').doc(doc_id)
      doc_ref.get.exists?
    end
  end
  ```
- [ ] Test database operations:
  ```ruby
  # test_database.rb
  require_relative 'lib/database'

  test_article = {
    url: 'https://example.com/test',
    title: 'Test Article',
    author: 'Test Author',
    audio_url: 'https://example.com/audio.mp3',
    audio_size: 1234567,
    text: 'Sample text content',
    date: Time.now
  }

  doc_id = Database.save_article('default', test_article)
  puts "Saved with ID: #{doc_id}"

  articles = Database.get_articles('default')
  puts "Retrieved #{articles.length} articles"
  ```

## Phase 3: RSS Feed Generation (Day 4)

### 3.1 RSS Generator
- [ ] Create `lib/rss_generator.rb`:
  ```ruby
  require 'rss'
  require_relative 'database'
  require_relative 'storage'

  module RSSGenerator
    PODCAST_TITLE = ENV['PODCAST_TITLE'] || 'My Text-to-Speech Podcast'
    PODCAST_DESCRIPTION = ENV['PODCAST_DESCRIPTION'] || 'Articles converted to audio'
    PODCAST_AUTHOR = ENV['PODCAST_AUTHOR'] || 'Podcast Generator'
    PODCAST_EMAIL = ENV['PODCAST_EMAIL'] || 'podcast@example.com'
    PODCAST_IMAGE = ENV['PODCAST_IMAGE'] || 'https://example.com/podcast-art.jpg'

    def self.generate_feed(user_id)
      articles = Database.get_articles(user_id)

      rss = RSS::Maker.make('2.0') do |maker|
        # Channel info
        maker.channel.title = PODCAST_TITLE
        maker.channel.link = "https://storage.googleapis.com/#{Storage::BUCKET_NAME}/podcasts/#{user_id}/feed.xml"
        maker.channel.description = PODCAST_DESCRIPTION
        maker.channel.language = 'en-us'
        maker.channel.updated = Time.now

        # iTunes tags
        maker.channel.itunes_author = PODCAST_AUTHOR
        maker.channel.itunes_summary = PODCAST_DESCRIPTION
        maker.channel.itunes_owner.itunes_name = PODCAST_AUTHOR
        maker.channel.itunes_owner.itunes_email = PODCAST_EMAIL
        maker.channel.itunes_image = RSS::ITunesItemModel::ITunesImage.new(PODCAST_IMAGE)
        maker.channel.itunes_explicit = 'no'
        maker.channel.itunes_category.text = 'Technology'

        # Add items (episodes)
        articles.each do |article|
          maker.items.new_item do |item|
            item.title = article[:title]
            item.link = article[:url]
            item.description = "Audio version of: #{article[:title]}"
            item.pubDate = article[:created_at]
            item.guid.content = article[:audio_url]
            item.guid.isPermaLink = true

            # Enclosure (audio file)
            item.enclosure.url = article[:audio_url]
            item.enclosure.length = article[:audio_size] || 0
            item.enclosure.type = 'audio/mpeg'

            # iTunes item tags
            item.itunes_author = article[:author] || PODCAST_AUTHOR
            item.itunes_summary = "Audio version of: #{article[:title]}"
            item.itunes_explicit = 'no'
          end
        end
      end

      rss.to_s
    end

    def self.update_feed(user_id)
      feed_xml = generate_feed(user_id)
      feed_url = Storage.upload_feed(user_id, feed_xml)
      
      {
        feed_url: feed_url,
        episodes_count: Database.get_articles(user_id).length
      }
    end
  end
  ```
- [ ] Test feed generation:
  ```ruby
  # test_rss.rb
  require_relative 'lib/rss_generator'

  result = RSSGenerator.update_feed('default')
  puts "Feed URL: #{result[:feed_url]}"
  puts "Episodes: #{result[:episodes_count]}"
  ```
- [ ] Validate RSS at https://podba.se/validate/
- [ ] Test feed URL in browser (should show XML)

### 3.2 Audio Duration Calculation (Optional Enhancement)
- [ ] Add MP3 duration detection:
  ```ruby
  # Add to Gemfile
  gem 'mp3info', '~> 0.8'
  ```
- [ ] Update storage module to calculate duration:
  ```ruby
  require 'mp3info'

  def self.get_audio_duration(audio_content)
    tempfile = Tempfile.new(['audio', '.mp3'])
    tempfile.binmode
    tempfile.write(audio_content)
    tempfile.close

    Mp3Info.open(tempfile.path) do |mp3|
      return mp3.length.to_i
    end
  ensure
    tempfile.unlink if tempfile
  end
  ```

## Phase 4: Cloud Function (Day 5)

### 4.1 Create Main Function
- [ ] Create `app.rb`:
  ```ruby
  require 'functions_framework'
  require 'json'
  require_relative 'lib/extractor'
  require_relative 'lib/tts'
  require_relative 'lib/storage'
  require_relative 'lib/database'
  require_relative 'lib/rss_generator'

  FunctionsFramework.http 'process_article' do |request|
    begin
      # Parse request
      data = JSON.parse(request.body.read) rescue {}
      url = data['url'] || request.params['url']
      user_id = request.get_header('X-User-ID') || 'default'

      # Validate input
      unless url && !url.empty?
        return [400, {}, ['Missing URL parameter']]
      end

      # Check for duplicate
      if Database.article_exists?(user_id, url)
        return [200, { 'Content-Type' => 'application/json' },
                [{ status: 'skipped', message: 'Article already processed' }.to_json]]
      end

      # Extract article text
      puts "Extracting: #{url}"
      article = Extractor.extract(url)

      # Generate audio
      puts "Generating audio for: #{article[:title]}"
      audio_content = TTS.synthesize(article[:text])

      # Upload to Cloud Storage
      puts "Uploading audio..."
      storage_result = Storage.upload_audio(user_id, audio_content, article[:title])

      # Save to Firestore
      puts "Saving to database..."
      article_data = article.merge(
        audio_url: storage_result[:url],
        audio_size: storage_result[:size]
      )
      Database.save_article(user_id, article_data)

      # Regenerate RSS feed
      puts "Updating RSS feed..."
      feed_result = RSSGenerator.update_feed(user_id)

      # Return success
      response = {
        status: 'success',
        article: {
          title: article[:title],
          audio_url: storage_result[:url],
          audio_size: storage_result[:size]
        },
        feed_url: feed_result[:feed_url]
      }

      [200, { 'Content-Type' => 'application/json' }, [response.to_json]]

    rescue StandardError => e
      puts "Error: #{e.message}"
      puts e.backtrace.join("\n")
      
      error_response = {
        status: 'error',
        message: e.message
      }
      
      [500, { 'Content-Type' => 'application/json' }, [error_response.to_json]]
    end
  end
  ```

### 4.2 Test Locally
- [ ] Install Functions Framework CLI:
  ```bash
  gem install functions_framework
  ```
- [ ] Run function locally:
  ```bash
  bundle exec functions-framework-ruby --target process_article --port 8080
  ```
- [ ] Test with curl:
  ```bash
  curl -X POST http://localhost:8080 \
    -H "Content-Type: application/json" \
    -d '{"url": "https://example.com/article"}'
  ```
- [ ] Verify each step:
  - [ ] Check console logs
  - [ ] Verify Firestore entry
  - [ ] Check Cloud Storage for audio file
  - [ ] Verify RSS feed updated
  - [ ] Test audio file plays

### 4.3 Deploy to Cloud
- [ ] Create `.gcloudignore`:
  ```
  .git
  .gitignore
  test_*.rb
  *.md
  .env
  ```
- [ ] Set environment variables (if needed):
  ```bash
  gcloud functions deploy process-article \
    --gen2 \
    --runtime ruby33 \
    --region us-central1 \
    --source . \
    --entry-point process_article \
    --trigger-http \
    --allow-unauthenticated \
    --timeout 540s \
    --memory 512MB \
    --set-env-vars PODCAST_BUCKET=your-podcast-bucket
  ```
- [ ] Wait for deployment (2-3 minutes)
- [ ] Note the function URL from output
- [ ] Test deployed function:
  ```bash
  curl -X POST https://REGION-PROJECT_ID.cloudfunctions.net/process-article \
    -H "Content-Type: application/json" \
    -d '{"url": "https://paulgraham.com/think.html"}'
  ```
- [ ] Check Cloud Functions logs:
  ```bash
  gcloud functions logs read process-article --gen2 --limit 50
  ```

## Phase 5: MVP Testing & Usage (Day 6)

### 5.1 End-to-End Test
- [ ] Submit 3-5 test articles:
  ```bash
  # Create test script: test_articles.sh
  #!/bin/bash
  FUNCTION_URL="https://REGION-PROJECT_ID.cloudfunctions.net/process-article"

  curl -X POST $FUNCTION_URL -H "Content-Type: application/json" \
    -d '{"url": "https://paulgraham.com/think.html"}'

  curl -X POST $FUNCTION_URL -H "Content-Type: application/json" \
    -d '{"url": "https://waitbutwhy.com/2015/01/artificial-intelligence-revolution-1.html"}'

  curl -X POST $FUNCTION_URL -H "Content-Type: application/json" \
    -d '{"url": "https://www.example.com/your-article"}'
  ```
- [ ] Verify in Google Cloud Console:
  - [ ] Check Firestore for entries
  - [ ] Check Cloud Storage for audio files
  - [ ] Download and play audio files
- [ ] Check RSS feed:
  ```bash
  curl https://storage.googleapis.com/your-podcast-bucket/podcasts/default/feed.xml
  ```

### 5.2 Subscribe to Feed
- [ ] Get your RSS feed URL:
  ```
  https://storage.googleapis.com/your-podcast-bucket/podcasts/default/feed.xml
  ```
- [ ] Choose a podcast app:
  - **iOS**: Overcast, Pocket Casts, Castro
  - **Android**: Pocket Casts, AntennaPod, Podcast Addict
- [ ] Add podcast by URL:
  - Open app → Add Podcast → Enter URL
- [ ] Verify episodes appear
- [ ] Test playing audio:
  - [ ] Check audio quality
  - [ ] Verify metadata (title, description)
  - [ ] Check episode artwork (if configured)
- [ ] Test on multiple devices (phone, tablet)

### 5.3 Create Helper Scripts
- [ ] Create `submit_article.rb`:
  ```ruby
  #!/usr/bin/env ruby
  require 'net/http'
  require 'uri'
  require 'json'

  FUNCTION_URL = ENV['FUNCTION_URL'] || 'https://REGION-PROJECT_ID.cloudfunctions.net/process-article'

  if ARGV.empty?
    puts "Usage: ruby submit_article.rb <article_url>"
    exit 1
  end

  url = ARGV[0]
  uri = URI.parse(FUNCTION_URL)
  
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  
  request = Net::HTTP::Post.new(uri.path, { 'Content-Type' => 'application/json' })
  request.body = { url: url }.to_json
  
  puts "Submitting: #{url}"
  response = http.request(request)
  
  if response.code == '200'
    result = JSON.parse(response.body)
    puts "✓ Success!"
    puts "  Title: #{result.dig('article', 'title')}"
    puts "  Audio: #{result.dig('article', 'audio_url')}"
    puts "  Feed: #{result['feed_url']}"
  else
    puts "✗ Error: #{response.code}"
    puts response.body
  end
  ```
- [ ] Make executable:
  ```bash
  chmod +x submit_article.rb
  ```
- [ ] Test:
  ```bash
  ./submit_article.rb https://example.com/article
  ```
- [ ] Create bash wrapper (optional):
  ```bash
  # submit_article.sh
  #!/bin/bash
  ruby "$(dirname "$0")/submit_article.rb" "$@"
  ```

### 5.4 Create Feed URL Helper
- [ ] Create `get_feed_url.rb`:
  ```ruby
  #!/usr/bin/env ruby

  BUCKET = ENV['PODCAST_BUCKET'] || 'your-podcast-bucket'
  USER_ID = ENV['USER_ID'] || 'default'

  feed_url = "https://storage.googleapis.com/#{BUCKET}/podcasts/#{USER_ID}/feed.xml"

  puts "\n" + "=" * 60
  puts "Your Podcast Feed URL:"
  puts feed_url
  puts "=" * 60
  puts "\nCopy this URL and paste it into your podcast app!"
  puts "\nRecommended apps:"
  puts "  iOS: Overcast, Pocket Casts, Castro"
  puts "  Android: Pocket Casts, AntennaPod"
  puts
  ```

## Phase 6: Refinements (Day 7)

### 6.1 Error Handling Improvements
- [ ] Add retry logic for TTS:
  ```ruby
  # In lib/tts.rb
  def self.synthesize_with_retry(text, max_retries: 3)
    retries = 0
    begin
      synthesize(text)
    rescue StandardError => e
      retries += 1
      if retries < max_retries
        sleep(2 ** retries) # Exponential backoff
        retry
      else
        raise
      end
    end
  end
  ```
- [ ] Better extraction error handling:
  ```ruby
  # In lib/extractor.rb
  def self.extract_safe(url)
    extract(url)
  rescue StandardError => e
    {
      url: url,
      title: "Failed: #{url}",
      text: "Could not extract article: #{e.message}",
      author: nil,
      date: Time.now,
      error: e.message
    }
  end
  ```
- [ ] Add request validation:
  ```ruby
  # In app.rb
  def validate_url(url)
    uri = URI.parse(url)
    return false unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
    return false if uri.host.nil?
    true
  rescue URI::InvalidURIError
    false
  end
  ```

### 6.2 Monitoring & Logging
- [ ] Add structured logging:
  ```ruby
  # In app.rb
  require 'logger'

  def logger
    @logger ||= Logger.new(STDOUT)
  end

  logger.info("Processing article", { url: url, user_id: user_id })
  ```
- [ ] View logs in Cloud Console:
  ```bash
  gcloud functions logs read process-article \
    --gen2 \
    --limit 100 \
    --format json
  ```
- [ ] Set up log-based metrics (optional):
  - Go to Cloud Console → Logging → Logs Explorer
  - Create metrics for errors, processing time
- [ ] Check API usage:
  ```bash
  gcloud logging read "resource.type=cloud_function" --limit 50
  ```

### 6.3 Cost Monitoring
- [ ] Check Text-to-Speech usage:
  - Go to Cloud Console → APIs & Services → Text-to-Speech API
  - View quotas and usage
- [ ] Check Cloud Storage costs:
  ```bash
  gsutil du -s gs://your-podcast-bucket
  ```
- [ ] Set up billing alerts:
  - Go to Billing → Budgets & alerts
  - Create budget alert (e.g., $10/month)
- [ ] Estimate costs:
  - TTS: $16 per 1M characters (Neural2 voices)
  - Storage: $0.02 per GB/month
  - Functions: Free tier covers ~2M invocations

### 6.4 Documentation
- [ ] Create `README.md`:
  ````markdown
  # Text-to-Speech Podcast Feed

  Convert web articles to audio and subscribe via RSS podcast feed.

  ## Your Feed URL
  ```
  https://storage.googleapis.com/your-podcast-bucket/podcasts/default/feed.xml
  ```

  ## Adding Articles

  ```bash
  ./submit_article.rb https://example.com/article
  ```

  Or use curl:
  ```bash
  curl -X POST https://REGION-PROJECT_ID.cloudfunctions.net/process-article \
    -H "Content-Type: application/json" \
    -d '{"url": "https://example.com/article"}'
  ```

  ## Subscribing

  1. Copy your feed URL above
  2. Open your podcast app (Overcast, Pocket Casts, etc.)
  3. Add podcast by URL
  4. Paste your feed URL

  ## Troubleshooting

  - **Article not extracting**: Some sites block scrapers or require JavaScript
  - **Audio quality**: Adjust TTS settings in `lib/tts.rb`
  - **Feed not updating**: Check Cloud Functions logs

  ## Architecture

  - Ruby Cloud Function (2nd gen)
  - Google Text-to-Speech API
  - Cloud Storage (audio files + RSS feed)
  - Firestore (article metadata)

  ## Costs

  Estimated $2-10/month for personal use:
  - TTS: ~$1-5 depending on article length
  - Storage: ~$0.50
  - Functions: Free tier
  - Firestore: Free tier
  ````
- [ ] Create `COSTS.md` with detailed breakdown
- [ ] Document environment variables
- [ ] Add troubleshooting guide

## Phase 7: Multi-User Preparation (Future)

### 7.1 User Structure Implementation
- [ ] Update function to handle user IDs properly:
  ```ruby
  # In app.rb
  def get_user_id(request)
    # For now, use header
    user_id = request.get_header('X-User-ID')
    
    # Later: validate API key or JWT token
    # api_key = request.get_header('Authorization')
    # user_id = validate_api_key(api_key)
    
    user_id || 'default'
  end
  ```
- [ ] Test with multiple user IDs:
  ```bash
  curl -X POST $FUNCTION_URL \
    -H "X-User-ID: user-alice" \
    -H "Content-Type: application/json" \
    -d '{"url": "https://example.com/article"}'

  curl -X POST $FUNCTION_URL \
    -H "X-User-ID: user-bob" \
    -H "Content-Type: application/json" \
    -d '{"url": "https://example.com/article"}'
  ```
- [ ] Verify separate feeds created:
  ```
  /podcasts/user-alice/feed.xml
  /podcasts/user-bob/feed.xml
  ```

### 7.2 Authentication
- [ ] Add API key validation:
  ```ruby
  # lib/auth.rb
  require 'securerandom'

  module Auth
    def self.generate_api_key
      SecureRandom.hex(32)
    end

    def self.validate_api_key(api_key)
      # Check against Firestore
      doc = Database.firestore.col('api_keys').doc(api_key).get
      doc.exists? ? doc.data[:user_id] : nil
    end
  end
  ```
- [ ] Or implement Firebase Auth:
  ```ruby
  gem 'firebase-admin-sdk'
  
  # Verify Firebase ID token
  def verify_firebase_token(id_token)
    FirebaseAdmin::Auth.verify_id_token(id_token)
  end
  ```
- [ ] Update function to require authentication:
  ```ruby
  def authenticate_request(request)
    api_key = request.get_header('Authorization')&.sub('Bearer ', '')
    user_id = Auth.validate_api_key(api_key)
    
    raise 'Unauthorized' unless user_id
    user_id
  end
  ```

### 7.3 User Management Functions
- [ ] Create user registration endpoint:
  ```ruby
  FunctionsFramework.http 'create_user' do |request|
    data = JSON.parse(request.body.read)
    email = data['email']
    
    # Generate API key
    api_key = Auth.generate_api_key
    user_id = SecureRandom.uuid
    
    # Save to Firestore
    Database.firestore.col('api_keys').doc(api_key).set({
      user_id: user_id,
      email: email,
      created_at: Time.now
    })
    
    Database.firestore.col('users').doc(user_id).set({
      email: email,
      created_at: Time.now
    })
    
    {
      user_id: user_id,
      api_key: api_key,
      feed_url: "https://storage.googleapis.com/#{Storage::BUCKET_NAME}/podcasts/#{user_id}/feed.xml"
    }.to_json
  end
  ```

### 7.4 Web Interface (Optional)
- [ ] Create Sinatra app for web UI:
  ```ruby
  # web_app.rb
  require 'sinatra'
  require_relative 'lib/database'
  require_relative 'lib/rss_generator'

  get '/' do
    erb :index
  end

  post '/submit' do
    # Call Cloud Function
    # Or process directly
  end

  get '/feed/:user_id' do
    user_id = params[:user_id]
    content_type 'application/rss+xml'
    RSSGenerator.generate_feed(user_id)
  end
  ```
- [ ] Deploy to Cloud Run:
  ```bash
  gcloud run deploy podcast-web \
    --source . \
    --platform managed \
    --region us-central1 \
    --allow-unauthenticated
  ```

### 7.5 Usage Limits & Quotas
- [ ] Add rate limiting:
  ```ruby
  # lib/rate_limiter.rb
  module RateLimiter
    MAX_PER_DAY = 10

    def self.check_limit(user_id)
      today = Date.today.to_s
      doc = Database.firestore.col('usage').doc("#{user_id}_#{today}").get
      
      count = doc.exists? ? doc.data[:count] : 0
      count < MAX_PER_DAY
    end

    def self.increment(user_id)
      today = Date.today.to_s
      doc_ref = Database.firestore.col('usage').doc("#{user_id}_#{today}")
      doc_ref.set({ count: Firestore::FieldValue.increment(1) }, merge: true)
    end
  end
  ```

## Deployment Checklist

### Before Going Live
- [ ] Test all error cases
- [ ] Set up monitoring alerts
- [ ] Configure budget alerts
- [ ] Add proper authentication
- [ ] Rate limit API calls
- [ ] Set up custom domain (optional)
- [ ] Add terms of service
- [ ] Add privacy policy
- [ ] Test feed in multiple podcast apps

### Launch Checklist
- [ ] Deploy all functions
- [ ] Test user signup flow
- [ ] Verify billing is configured
- [ ] Monitor logs for first few users
- [ ] Prepare support documentation

## Key Milestones

**Day 1**: Infrastructure setup complete, can access all GCP services  
**Day 3**: Core modules working locally (extract → TTS → storage)  
**Day 4**: RSS feed generating correctly  
**Day 5**: Cloud Function deployed and working  
**Day 6**: Successfully subscribed to your personal feed  
**Day 7**: Polished MVP with monitoring and docs  

## Estimated Costs

### Personal Use (10 articles/month)
- TTS: ~$2-4 (depending on article length)
- Storage: ~$0.50
- Functions: Free tier
- Firestore: Free tier
- **Total: ~$3-5/month**

### Multi-User (100 users, 100 articles/month)
- TTS: ~$40-80
- Storage: ~$5
- Functions: ~$5
- Firestore: ~$5
- **Total: ~$55-95/month**

## Next Steps After MVP

1. Use for 1-2 weeks personally
2. Gather feedback from friends/beta users
3. Add most-requested features
4. Optimize costs
5. Add web interface
6. Launch publicly

