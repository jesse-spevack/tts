# Very Normal TTS

A Rails application that converts web articles into podcast episodes using text-to-speech. Submit a URL, and the app extracts the article content, processes it with an LLM, and generates an audio episode you can listen to in any podcast player.

## Features

- **URL to Podcast**: Paste any article URL and get an audio episode
- **Markdown Upload**: Upload markdown files directly
- **Paste Text**: Paste text content directly
- **Personal RSS Feed**: Each user gets a private podcast feed
- **Magic Link Auth**: Passwordless authentication via email
- **User Tiers**: Free (2 episodes/month) and Premium tiers

## Tech Stack

- **Framework**: Rails 8.1
- **Ruby**: 3.4.5
- **Database**: SQLite
- **Background Jobs**: Solid Queue
- **Frontend**: Hotwire (Turbo + Stimulus), Tailwind CSS
- **Asset Pipeline**: Propshaft with Import Maps

### External Services

- **Google Cloud Text-to-Speech**: Audio generation
- **Google Cloud Storage**: Audio file and RSS feed hosting
- **Vertex AI (Gemini)**: LLM for content extraction and metadata
- **Resend**: Email delivery for magic links

## Development Setup

### Prerequisites

- Ruby 3.4.5
- SQLite 3
- Node.js (for Tailwind CSS)
- Google Cloud credentials (for TTS)

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
URL/File/Paste submitted
    ↓
Solid Queue Job (async)
    ↓
FetchesUrl + ExtractsArticle
    ↓
ProcessesWithLlm (clean content, generate metadata)
    ↓
SynthesizesAudio → Google Cloud TTS API
    ↓
GCS Upload (audio file)
    ↓
GenerateRssFeed uploaded
```

## Troubleshooting

### Kamal deploy fails with "no space left on device"

If `kamal deploy` fails with:

```
ERROR: failed to copy files: copy file range failed: no space left on device
```

The remote server is out of disk space. Common cause: orphaned buildkit volumes.

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
