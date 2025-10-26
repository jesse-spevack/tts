# Podcast Feed Implementation Plan

## Overview
Transform the existing markdown-to-MP3 TTS tool into an automated podcast feed generator that uploads to Google Cloud Storage and maintains an RSS feed.

## Current State
- ✅ Markdown to text conversion (`TextProcessor`)
- ✅ TTS synthesis with chunking and retry logic (`TTS`)
- ✅ Command-line interface (`generate.rb`)
- ✅ Local MP3 output to `output/` directory

## Goal
Run a single command that:
1. Converts markdown → MP3 (existing)
2. Uploads MP3 to Google Cloud Storage
3. Generates/updates podcast RSS feed
4. Uploads RSS feed to GCS
5. Makes everything publicly accessible via podcast apps

## Architecture

```
markdown file (with frontmatter)
    ↓
generate.rb (enhanced)
    ↓
1. Extract metadata from frontmatter
2. Generate MP3 (existing pipeline)
3. Upload MP3 to GCS
4. Update episode manifest
5. Generate RSS feed from manifest
6. Upload RSS feed to GCS
    ↓
Public podcast feed URL in GCS
```

## Implementation Phases

### Phase 1: Metadata & Configuration

**New Files:**
- `config/podcast.yml` - Podcast-level metadata
- `lib/metadata_extractor.rb` - Parse frontmatter from markdown

**Podcast Config Structure (`config/podcast.yml`):**
```yaml
title: "My Podcast Title"
description: "Podcast description"
author: "Your Name"
email: "your@email.com"
language: "en-us"
category: "Technology"
artwork_url: "https://example.com/artwork.jpg"  # optional
explicit: false
```

**Markdown Frontmatter Structure:**
```yaml
---
title: "Episode Title"
description: "Episode description for show notes"
author: "Episode Author"  # optional, falls back to podcast author
---

# Episode content...
```

**Tasks:**
1. Create `config/podcast.yml` with user-provided values
2. Implement `MetadataExtractor` class
   - Parse YAML frontmatter from markdown files
   - Validate required fields (title, description)
   - Fall back to filename-based title if no frontmatter
3. Add frontmatter parsing to `generate.rb` workflow

**Success Criteria:** Can extract episode metadata from markdown files with frontmatter

---

### Phase 2: Google Cloud Storage Integration

**New Files:**
- `lib/gcs_uploader.rb` - Upload files to GCS and get public URLs
- `.env.example` - Document required environment variables

**Environment Variables:**
```
GOOGLE_CLOUD_PROJECT=your-project-id
GOOGLE_CLOUD_BUCKET=your-bucket-name
GOOGLE_APPLICATION_CREDENTIALS=path/to/credentials.json
```

**GCS Structure:**
```
gs://your-bucket-name/
├── episodes/
│   ├── episode-name-2025-10-25.mp3
│   └── another-episode-2025-10-26.mp3
├── feed.xml
└── manifest.json
```

**GCSUploader Class:**
```ruby
class GCSUploader
  def initialize(bucket_name)
  def upload_file(local_path, remote_path)
  def make_public(remote_path)
  def get_public_url(remote_path)
end
```

**Tasks:**
1. Add `google-cloud-storage` gem to Gemfile
2. Implement `GCSUploader` class
   - Initialize with bucket name from env var
   - Upload file to specified path
   - Set public read permissions
   - Return public URL
3. Add bucket creation/configuration documentation
4. Test uploading MP3 files and accessing public URLs

**Success Criteria:** Can upload MP3 to GCS and get a publicly accessible URL that plays in browser

---

### Phase 3: Episode Manifest

**New Files:**
- `lib/episode_manifest.rb` - Manage episode list and metadata

**Manifest Structure (`manifest.json` in GCS):**
```json
{
  "episodes": [
    {
      "id": "episode-name-2025-10-25",
      "title": "Episode Title",
      "description": "Episode description",
      "author": "Author Name",
      "mp3_url": "https://storage.googleapis.com/.../episode.mp3",
      "duration_seconds": 1234,
      "file_size_bytes": 5678901,
      "published_at": "2025-10-25T14:30:00Z",
      "guid": "unique-episode-id"
    }
  ]
}
```

**EpisodeManifest Class:**
```ruby
class EpisodeManifest
  def initialize(gcs_uploader)
  def load  # Download from GCS, parse JSON
  def add_episode(episode_data)  # Add new episode, sort by published_at
  def save  # Upload to GCS
  def episodes  # Return sorted episode array
end
```

**Tasks:**
1. Implement `EpisodeManifest` class
   - Download existing manifest from GCS (or create empty if doesn't exist)
   - Add new episode with metadata
   - Sort episodes by `published_at` (newest first)
   - Upload updated manifest back to GCS
2. Generate episode GUID (use URL-safe slug + timestamp)
3. Calculate MP3 duration using `mp3info` gem
4. Store file size from uploaded MP3

**Success Criteria:** Can maintain a persistent list of episodes across multiple runs

---

### Phase 4: RSS Feed Generation

**New Files:**
- `lib/rss_generator.rb` - Generate podcast RSS 2.0 XML with iTunes tags

**RSS Feed Structure:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"
     xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"
     xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Podcast Title</title>
    <description>Podcast Description</description>
    <language>en-us</language>
    <itunes:author>Author Name</itunes:author>
    <itunes:category text="Technology"/>
    <itunes:explicit>false</itunes:explicit>
    <item>
      <title>Episode Title</title>
      <description>Episode Description</description>
      <enclosure url="..." type="audio/mpeg" length="5678901"/>
      <guid isPermaLink="false">episode-guid</guid>
      <pubDate>Sat, 25 Oct 2025 14:30:00 +0000</pubDate>
      <itunes:duration>1234</itunes:duration>
      <itunes:author>Episode Author</itunes:author>
    </item>
  </channel>
</rss>
```

**RSSGenerator Class:**
```ruby
class RSSGenerator
  def initialize(podcast_config, episodes)
  def generate  # Return XML string
end
```

**Tasks:**
1. Add `builder` gem to Gemfile (for XML generation)
2. Implement `RSSGenerator` class
   - Load podcast config from `config/podcast.yml`
   - Generate valid RSS 2.0 XML
   - Include iTunes podcast tags
   - Format dates in RFC 822 format
   - Include all required episode fields
3. Validate RSS feed with online validator
4. Test with multiple episodes

**Success Criteria:** Generate valid RSS 2.0 XML that passes podcast feed validators

---

### Phase 5: Pipeline Integration

**Modified Files:**
- `generate.rb` - Orchestrate the full pipeline

**New Workflow:**
```ruby
1. Parse command-line arguments (markdown file)
2. Extract metadata from frontmatter
3. Generate MP3 (existing TTS pipeline)
4. Upload MP3 to GCS
5. Get MP3 metadata (duration, file size, public URL)
6. Load episode manifest from GCS
7. Add new episode to manifest
8. Save manifest to GCS
9. Generate RSS feed from manifest
10. Upload RSS feed to GCS
11. Display feed URL
```

**Command-line Interface:**
```bash
# Basic usage
ruby generate.rb input/article.md

# With voice option
ruby generate.rb -v en-US-Chirp3-HD-Galahad input/article.md

# Output shows:
# - MP3 generation progress (existing)
# - Upload progress
# - RSS feed URL
# - Episode count
```

**Tasks:**
1. Refactor `generate.rb` to include new steps
2. Add progress indicators for each phase
3. Handle errors gracefully (GCS upload failures, etc.)
4. Display final feed URL for podcast app subscription
5. Add `--local-only` flag to skip upload (for testing)

**Success Criteria:** Single command converts markdown → published podcast episode

---

### Phase 6: Testing & Documentation

**Tasks:**
1. Test complete pipeline with 3-5 episodes
2. Verify RSS feed in multiple podcast apps (Apple Podcasts, Overcast, Pocket Casts)
3. Update README with:
   - GCS setup instructions
   - Podcast configuration
   - Frontmatter format
   - RSS feed subscription instructions
4. Add troubleshooting section
5. Document costs (GCS storage + egress)

**Success Criteria:** Documentation allows someone to set up and use the tool independently

---

## Dependencies

**New Gems:**
```ruby
gem 'google-cloud-storage'  # GCS integration
gem 'ruby-mp3info'          # MP3 duration calculation
gem 'builder'               # XML generation
```

**Existing Gems:**
- `google-cloud-text_to_speech` (already in use)
- `dotenv` (already in use)

---

## File Structure (After Implementation)

```
tts/
├── config/
│   └── podcast.yml              # Podcast metadata
├── lib/
│   ├── metadata_extractor.rb    # NEW: Parse frontmatter
│   ├── gcs_uploader.rb          # NEW: Upload to GCS
│   ├── episode_manifest.rb      # NEW: Manage episode list
│   ├── rss_generator.rb         # NEW: Generate RSS feed
│   ├── text_processor.rb        # EXISTING
│   └── tts/                     # EXISTING
│       ├── api_client.rb
│       ├── chunked_synthesizer.rb
│       ├── config.rb
│       └── text_chunker.rb
├── input/                       # Markdown files with frontmatter
├── output/                      # Local MP3 cache (optional)
├── test/
│   ├── test_metadata_extractor.rb
│   ├── test_gcs_uploader.rb
│   ├── test_episode_manifest.rb
│   └── test_rss_generator.rb
├── generate.rb                  # MODIFIED: Full pipeline
├── Gemfile                      # MODIFIED: Add new gems
├── .env.example                 # NEW: Document env vars
└── README.md                    # MODIFIED: Add podcast instructions
```

---

## GCS Setup Instructions

### One-time Setup:

1. **Create GCS Bucket:**
   ```bash
   gsutil mb -p your-project-id -c STANDARD -l us-central1 gs://your-bucket-name
   ```

2. **Enable Public Access:**
   ```bash
   gsutil iam ch allUsers:objectViewer gs://your-bucket-name
   ```

3. **Set CORS (optional, for web players):**
   ```bash
   gsutil cors set cors.json gs://your-bucket-name
   ```

4. **Create Service Account:**
   - GCP Console → IAM → Service Accounts → Create
   - Grant "Storage Object Admin" role
   - Create JSON key
   - Save as `gcp-credentials.json`

5. **Set Environment Variables:**
   ```bash
   GOOGLE_CLOUD_PROJECT=your-project-id
   GOOGLE_CLOUD_BUCKET=your-bucket-name
   GOOGLE_APPLICATION_CREDENTIALS=./gcp-credentials.json
   ```

---

## Expected Timeline

- **Phase 1 (Metadata):** 2-3 hours
- **Phase 2 (GCS):** 3-4 hours
- **Phase 3 (Manifest):** 2-3 hours
- **Phase 4 (RSS):** 3-4 hours
- **Phase 5 (Integration):** 2-3 hours
- **Phase 6 (Testing):** 2-3 hours

**Total:** ~15-20 hours of development

---

## Cost Estimates (Personal Use)

Assuming 10 episodes/month, ~5MB per episode:

- **Cloud Storage:** $0.02/GB/month = $0.001/month
- **Network Egress:** First 1GB free, then $0.12/GB
  - 10 listens/episode × 5MB × 10 episodes = 500MB/month = FREE
- **API Calls:** Negligible (read/write manifest + RSS)

**Total: ~$0.00-0.10/month** (essentially free for personal use)

TTS costs remain the same as before (~$4-16 per 1M characters).

---

## Future Enhancements (Post-MVP)

1. **Artwork Generation:** Auto-generate episode artwork from title
2. **Chapters:** Add chapter markers for long episodes
3. **Transcripts:** Include full text transcripts in feed
4. **Web Interface:** Simple web page showing all episodes
5. **Multiple Feeds:** Support multiple podcast feeds from one tool
6. **Analytics:** Track episode downloads via GCS logs
7. **Automation:** Watch folder for new markdown files
8. **CDN:** Add CloudFlare in front of GCS for faster delivery

---

## Success Metrics

✅ Can run single command to publish episode
✅ RSS feed validates in podcast validators
✅ Episodes appear in podcast apps within 1 hour
✅ Audio files play correctly in all tested apps
✅ Episode metadata displays correctly
✅ New episodes automatically appear in existing subscriptions
✅ Total cost < $1/month for personal use
