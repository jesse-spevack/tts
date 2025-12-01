# TTS Hub

A Rails application that converts web articles into podcast episodes using text-to-speech. Submit a URL, and the app extracts the article content, processes it with an LLM, and generates an audio episode you can listen to in any podcast player.

## Features

- **URL to Podcast**: Paste any article URL and get an audio episode
- **Markdown Upload**: Alternatively, upload markdown files directly
- **Personal RSS Feed**: Each user gets a private podcast feed
- **Magic Link Auth**: Passwordless authentication via email
- **User Tiers**: Free (2 episodes/month), Premium, and Unlimited tiers

## Tech Stack

- **Framework**: Rails 8.1
- **Ruby**: 3.4.5
- **Database**: SQLite
- **Frontend**: Hotwire (Turbo + Stimulus), Tailwind CSS
- **Asset Pipeline**: Propshaft with Import Maps

### External Services

- **Google Cloud Storage**: Audio file and RSS feed hosting
- **Google Cloud Tasks**: Async job processing
- **Vertex AI (Gemini)**: LLM for content extraction and metadata
- **External TTS Service**: Audio generation

## Development Setup

### Prerequisites

- Ruby 3.4.5
- SQLite 3
- Node.js (for Tailwind CSS)

### Installation

```bash
# Install dependencies
bundle install

# Setup database
bin/rails db:setup

# Start the server
bin/dev
```

### Running Tests

```bash
bin/rails test
```

## Environment Variables

Required environment variables for production:

| Variable | Description |
|----------|-------------|
| `RAILS_MASTER_KEY` | Rails credentials key |
| `RESEND_API_KEY` | Email delivery (magic links) |
| `GOOGLE_CLOUD_PROJECT` | GCP project ID |
| `GOOGLE_CLOUD_BUCKET` | GCS bucket for audio/feeds |
| `SERVICE_ACCOUNT_EMAIL` | GCP service account |
| `VERTEX_AI_LOCATION` | Vertex AI region |
| `CLOUD_TASKS_LOCATION` | Cloud Tasks region |
| `CLOUD_TASKS_QUEUE` | Cloud Tasks queue name |
| `GENERATOR_SERVICE_URL` | TTS generator endpoint |
| `GENERATOR_CALLBACK_SECRET` | Auth for generator callbacks |

## Deployment

Deployed via [Kamal](https://kamal-deploy.org/) to Google Cloud Platform.

```bash
# Deploy
bin/kamal deploy

# Console access
bin/kamal console

# View logs
bin/kamal logs
```

## Architecture

```
URL submitted
    ↓
UrlFetcher (fetch HTML)
    ↓
ArticleExtractor (extract text + metadata)
    ↓
LlmProcessor (clean content, generate description)
    ↓
Cloud Tasks (async)
    ↓
External TTS Generator → GCS (audio file)
    ↓
RSS Feed updated
```

## Troubleshooting

### Kamal deploy fails with "no space left on device"

If `kamal deploy` fails with:

```
ERROR: failed to copy files: copy file range failed: no space left on device
```

The remote server is out of disk space. Common cause: orphaned buildkit volumes from old IP addresses.

**Diagnose:**

```bash
ssh jesse@<SERVER_IP> 'df -h /'
ssh jesse@<SERVER_IP> 'sudo bash -c "du -sh /var/lib/docker/volumes/*"'
```

**Fix:** Remove orphaned buildkit volumes:

```bash
ssh jesse@<SERVER_IP> 'docker ps -a'  # find old buildkit container IDs
ssh jesse@<SERVER_IP> 'docker rm -f <container_id>'
ssh jesse@<SERVER_IP> 'docker volume rm <old_buildkit_volume_name>'
```

**Prevention:** Reserve a static IP in GCP Console to prevent IP changes on VM restart.
