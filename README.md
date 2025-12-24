# TTS - Text-to-Speech Podcast Platform

A platform for converting web articles and markdown into podcast episodes. Users submit URLs through a web interface, and the system extracts content, generates audio, and publishes to a personal podcast RSS feed.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         User Browser                            │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Hub (Rails App)                          │
│  • Web interface for URL/markdown submission                    │
│  • Magic link authentication                                    │
│  • Article extraction + LLM processing                          │
│  • Episode management                                           │
│  • Deployed via Kamal to GCP VM                                 │
└─────────────────────────────────────────────────────────────────┘
                                │
                    Cloud Tasks (async)
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Generator (Cloud Run)                         │
│  • Text-to-speech conversion (Google Cloud TTS)                 │
│  • Audio chunking + parallel processing                         │
│  • RSS feed generation                                          │
│  • Callbacks to Hub on completion                               │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Google Cloud Storage                          │
│  • Audio files (.mp3)                                           │
│  • RSS feeds (feed.xml)                                         │
│  • Episode manifests                                            │
└─────────────────────────────────────────────────────────────────┘
```

## Components

| Component | Directory | Description | Deployment |
|-----------|-----------|-------------|------------|
| **Hub** | `hub/` | Rails web app for users | Kamal → GCP VM |
| **Generator** | Root | TTS processing service | Cloud Run |

## Quick Links

- **Hub Documentation**: See [`hub/README.md`](hub/README.md)
- **Deployment Guide**: See [`docs/deployment.md`](docs/deployment.md)

---

## Generator Service

The Generator handles text-to-speech conversion and RSS feed management.

### Setup

1. Install dependencies:
```bash
bundle install
```

2. Configure environment variables (copy `.env.example` to `.env`):
   - Google Cloud credentials
   - GCS bucket configuration
   - Podcast metadata

### Local Usage

Generate a podcast episode locally:

```bash
ruby generate.rb input/article.md
```

Options:
```bash
ruby generate.rb --local-only input/article.md  # Don't publish to GCS
ruby generate.rb -v en-US-Chirp3-HD-Galahad input/article.md  # Different voice
ruby generate.rb --help  # All options
```

### API Usage

Submit an episode for processing:

```bash
TOKEN=$(gcloud auth print-identity-token)

curl -X POST https://podcast-api-ns2hvyzzra-wm.a.run.app/publish \
  -H "Authorization: Bearer $TOKEN" \
  -F "podcast_id=podcast_abc123xyz" \
  -F "title=Episode Title" \
  -F "author=Author Name" \
  -F "description=Episode description" \
  -F "content=@input/article.md"
```

### Input File Format

Markdown files with YAML frontmatter:

```yaml
---
title: "Episode Title"
description: "Brief description"
author: "Author Name"
---

Your markdown content here...
```

### Deploy Generator

```bash
./bin/deploy
```

## Storage Structure

```
podcasts/{podcast_id}/
  ├── episodes/{episode_id}.mp3
  ├── feed.xml
  ├── manifest.json
  └── staging/{filename}.md
```

## Testing

```bash
# Generator tests
rake test

# Hub tests
cd hub && bin/rails test

# Linting
rake rubocop
```

## Troubleshooting

### Cloud Tasks Retrying Endlessly

**Symptom:** Failed episodes retry for an hour instead of stopping after 3 attempts.

**Fix:** Remove `maxRetryDuration` so only `maxAttempts` limits retries:

```bash
gcloud tasks queues update episode-processing \
    --location=us-west3 \
    --max-attempts=3 \
    --max-retry-duration=0s
```

### Checking Cloud Run Logs

```bash
# Recent logs
gcloud logging read 'resource.type="cloud_run_revision"' --limit=50 \
    --format="table(timestamp,textPayload)"

# Filter by episode
gcloud logging read 'resource.type="cloud_run_revision" AND textPayload=~"episode_id=123"' \
    --limit=100
```

## Known Limitations

- No automatic retry if Generator callback to Hub fails
- No processing timeout for stuck episodes
- Single podcast per user

## License

[OSaaS Dev License](LICENSE) - MIT with SaaS restriction
