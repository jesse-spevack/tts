# Tasks for Podcast Feed Generator

## Overview
Transform the existing markdown-to-MP3 TTS tool into an automated podcast feed generator that uploads to Google Cloud Storage and maintains an RSS feed.

## Tasks

- [x] 1.0 Implement metadata extraction from markdown frontmatter
  - [x] 1.0.1 Write unit tests in `test/test_metadata_extractor.rb` covering valid frontmatter, missing fields, and invalid YAML
  - [x] 1.1 Create `config/podcast.yml` with podcast-level metadata (title, description, author, email, language, category, explicit flag)
  - [x] 1.2 Implement `MetadataExtractor` class in `lib/metadata_extractor.rb`
  - [x] 1.3 Add YAML frontmatter parsing logic (extract title, description, author from markdown)
  - [x] 1.4 Validate required fields (title and description) and raise errors if missing

- [x] 2.0 Implement Google Cloud Storage integration for file uploads
  - [x] 2.0.1 Write simple unit tests in `test/test_gcs_uploader.rb` (may require mocking or integration tests)
  - [x] 2.1 Add `google-cloud-storage` gem to Gemfile and run `bundle install`
  - [x] 2.2 Create `.env.example` documenting required environment variables (GOOGLE_CLOUD_PROJECT, GOOGLE_CLOUD_BUCKET, GOOGLE_APPLICATION_CREDENTIALS)
    - Explain necessary configuration in google cloud console
  - [x] 2.3 Implement `GCSUploader` class in `lib/gcs_uploader.rb`
  - [x] 2.4 Add `initialize` method accepting bucket name from environment
  - [x] 2.5 Add `upload_file(local_path:, remote_path:)` method that uploads and sets public read permissions
  - [x] 2.6 Add `get_public_url(remote_path:)` method returning public HTTPS URL
  - [x] 2.7 Add error handling for missing credentials and network failures

- [x] 3.0 Implement episode manifest management
  - [x] 3.0.1 Write unit tests in `test/test_episode_manifest.rb` covering load, add, save, and sorting
  - [x] 3.1 Implement `EpisodeManifest` class in `lib/episode_manifest.rb`
  - [x] 3.2 Add `initialize(gcs_uploader)` to set up GCS dependency
  - [x] 3.3 Add `load` method to download manifest.json from GCS (or initialize empty array if doesn't exist)
  - [x] 3.4 Add `add_episode(episode_data)` method that appends episode and sorts by published_at (newest first)
  - [x] 3.5 Add `save` method to upload updated manifest.json back to GCS
  - [x] 3.6 Add logic to generate unique episode GUID (timestamp + slug)

- [x] 4.0 Implement RSS feed generation with iTunes podcast tags
  - [x] 4.0.1 Write unit tests in `test/test_rss_generator.rb` validating XML structure and required fields
  - [x] 4.1 Add `builder` gem to Gemfile and run `bundle install`
  - [x] 4.2 Implement `RSSGenerator` class in `lib/rss_generator.rb`
  - [x] 4.3 Add `initialize(podcast_config, episodes)` accepting config hash and episode array
  - [x] 4.4 Add `generate` method that returns RSS 2.0 XML string using Builder gem
  - [x] 4.5 Include podcast-level tags (title, description, language, itunes:author, itunes:category, itunes:explicit)
  - [x] 4.6 Include episode-level tags for each item (title, description, enclosure with file size, guid, pubDate, itunes:author)
    - Note: itunes:duration is optional and omitted for MVP (can add later if needed)
  - [x] 4.7 Format pubDate in RFC 822 format (required by RSS spec)
  - [x] 4.8 Add optional artwork URL support if provided in podcast config

- [ ] 5.0 Integrate podcast pipeline into generate.rb
  - [ ] 5.1 Add require statements for new dependencies (MetadataExtractor, GCSUploader, EpisodeManifest, RSSGenerator)
  - [ ] 5.2 Load podcast config from `config/podcast.yml` at startup
  - [ ] 5.3 Add metadata extraction step after markdown processing (extract frontmatter before TextProcessor)
  - [ ] 5.4 Add `--local-only` flag to skip GCS upload (for testing)
  - [ ] 5.5 After MP3 generation, upload MP3 to GCS in `episodes/` directory with timestamp-slug naming
  - [ ] 5.6 Get MP3 metadata (file size, public URL) from GCS after upload
  - [ ] 5.7 Load episode manifest from GCS, add new episode, and save back
  - [ ] 5.8 Generate RSS feed from updated manifest using RSSGenerator
  - [ ] 5.9 Upload RSS feed to GCS as `feed.xml`
  - [ ] 5.10 Display final output including feed URL and episode count
  - [ ] 5.11 Add progress indicators for each pipeline phase

- [ ] 6.0 Testing, validation, and documentation
  - [ ] 6.1 Run full test suite with `rake test` and ensure all tests pass
  - [ ] 6.2 Test complete pipeline with 2-3 sample markdown files with frontmatter
  - [ ] 6.3 Validate generated RSS feed using online validator (e.g., podbase.com/validate or castfeedvalidator.com)
  - [ ] 6.4 Manually test RSS feed in at least one podcast app (Apple Podcasts, Overcast, or Pocket Casts)
  - [ ] 6.5 Update README.md with GCS setup instructions (bucket creation, service account, permissions)
  - [ ] 6.6 Update README.md with podcast configuration instructions (podcast.yml format)
  - [ ] 6.7 Update README.md with frontmatter format and example
  - [ ] 6.8 Update README.md with usage examples (basic, with --local-only, with custom voice)
  - [ ] 6.9 Add troubleshooting section for common errors (missing credentials, invalid frontmatter, GCS permissions)
  - [ ] 6.10 Run final `rake rubocop` to ensure code style compliance

## Relevant Files

### New Files to Create

- `config/podcast.yml` - Podcast-level metadata configuration (title, description, author, etc.)
- `lib/metadata_extractor.rb` - Parse YAML frontmatter from markdown files
- `lib/gcs_uploader.rb` - Upload files to Google Cloud Storage and manage public URLs
- `lib/episode_manifest.rb` - Manage episode list with metadata (stored in GCS as manifest.json)
- `lib/rss_generator.rb` - Generate RSS 2.0 XML feed with iTunes tags
- `.env.example` - Document required environment variables for GCS
- `test/test_metadata_extractor.rb` - Unit tests for metadata extraction
- `test/test_gcs_uploader.rb` - Unit tests for GCS uploader
- `test/test_episode_manifest.rb` - Unit tests for episode manifest
- `test/test_rss_generator.rb` - Unit tests for RSS generator

### Existing Files to Modify

- `Gemfile` - Add new gems: `google-cloud-storage`, `builder`
- `generate.rb` - Integrate podcast pipeline steps (metadata extraction, upload, manifest, RSS)
- `README.md` - Add setup instructions, configuration docs, and usage examples

### Files Created in GCS (Remote)

- `gs://bucket-name/episodes/*.mp3` - Episode audio files (timestamped)
- `gs://bucket-name/manifest.json` - Episode metadata manifest
- `gs://bucket-name/feed.xml` - Public RSS feed

## Notes

- Uses Minitest framework (matching existing test suite)
- Follows existing patterns: class-based design with class methods
- Test command: `rake test` or `ruby -Ilib:test test/test_*.rb`
- RuboCop linting: `rake rubocop`
- **MP3 duration omitted for MVP**: The `itunes:duration` tag is optional per RSS spec. Podcast apps will still work fine without it, though episode length won't display until playback starts. This avoids dependency on the unmaintained `ruby-mp3info` gem.
