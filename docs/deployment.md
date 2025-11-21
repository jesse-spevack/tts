# Deployment Guide

This document describes how to deploy the TTS platform, which consists of two services:

- **Hub**: Rails web application for user accounts, episode management, and API
- **Generator**: Ruby/Sinatra service for TTS audio generation

## Architecture Overview

```
Users (Web/API)
      │
      ▼
┌─────────────────────────────────────┐
│              HUB                     │
│         (Rails + SQLite)             │
│     https://tts.verynormal.dev       │
│                                      │
│  • Magic link authentication         │
│  • Episode CRUD (Web + API)          │
│  • Enqueues processing via Cloud Tasks│
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│           GENERATOR                  │
│      (Ruby/Sinatra on Cloud Run)     │
│                                      │
│  • Receives tasks from Hub           │
│  • Generates TTS audio               │
│  • Updates RSS feed                  │
│  • Callbacks to Hub on completion    │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│      Google Cloud Storage            │
│  podcasts/{podcast_id}/              │
│    ├── episodes/*.mp3                │
│    ├── feed.xml                      │
│    └── staging/*.md                  │
└─────────────────────────────────────┘
```

---

## Hub Deployment (Kamal)

The Hub is deployed to a GCP VM using [Kamal](https://kamal-deploy.org/).

### Prerequisites

1. GCP VM with Docker installed
2. Google Artifact Registry for container images
3. Kamal secrets configured in `hub/.kamal/secrets`

### Environment Variables

Secrets are stored in `hub/.kamal/secrets`:

```bash
RAILS_MASTER_KEY=...
RESEND_API_KEY=...              # For magic link emails
MAILER_HOST=tts.verynormal.dev
MAILER_FROM_ADDRESS=...
CLOUD_TASKS_LOCATION=us-central1
CLOUD_TASKS_QUEUE=episode-processing
GENERATOR_CALLBACK_SECRET=...   # Shared secret with Generator
GENERATOR_SERVICE_URL=...       # Generator's Cloud Run URL
GOOGLE_CLOUD_BUCKET=...
GOOGLE_CLOUD_PROJECT=...
SERVICE_ACCOUNT_EMAIL=...
KAMAL_REGISTRY_PASSWORD=...     # Base64-encoded GCP service account key
```

### Deployment Command

```bash
cd hub
bin/kamal deploy
```

### Useful Kamal Commands

```bash
bin/kamal logs          # Tail application logs
bin/kamal console       # Rails console
bin/kamal shell         # Bash shell in container
bin/kamal app restart   # Restart the application
```

### Hub URL

**Production**: https://tts.verynormal.dev

---

## Generator Deployment (Cloud Run)

The Generator is deployed to Google Cloud Run.

### Prerequisites

1. Google Cloud Project with billing enabled
2. APIs enabled: Cloud Run, Cloud Build, Cloud Storage, Cloud Tasks
3. Service account with GCS and Cloud Tasks permissions

### Environment Variables

Create a `.env` file in the project root:

```bash
GOOGLE_CLOUD_PROJECT=your-project-id
GOOGLE_CLOUD_BUCKET=your-bucket-name
API_SECRET_TOKEN=your-secure-token
CLOUD_TASKS_LOCATION=us-central1
CLOUD_TASKS_QUEUE=episode-processing
SERVICE_ACCOUNT_EMAIL=...
HUB_CALLBACK_URL=https://tts.verynormal.dev
HUB_CALLBACK_SECRET=...         # Must match Hub's GENERATOR_CALLBACK_SECRET
```

### Deployment Command

```bash
./bin/deploy
```

This script:
1. Builds Docker image via Cloud Build (20-minute timeout for grpc)
2. Deploys to Cloud Run with production configuration
3. Updates with SERVICE_URL for Cloud Tasks callbacks

### Build Optimizations

The `Gemfile.lock` includes `x86_64-linux` platform for precompiled binaries:

```bash
bundle lock --add-platform x86_64-linux
```

This speeds up builds from 18+ minutes to 2-3 minutes by using precompiled `grpc`.

### Cloud Run Configuration

- **Memory**: 2Gi
- **CPU**: 4
- **Timeout**: 600s (10 minutes for long TTS jobs)
- **Instances**: 0-1 (scales to zero)
- **RACK_ENV**: production (required for GCS auth and Sinatra config)

---

## Service Communication

### Hub → Generator

- **Method**: Google Cloud Tasks with OIDC authentication
- **Endpoint**: `POST /process` on Generator
- **Payload**: Episode metadata and staging file path

### Generator → Hub

- **Method**: HTTP callback with shared secret
- **Endpoint**: `PATCH /api/internal/episodes/:id` on Hub
- **Header**: `X-Generator-Secret: {HUB_CALLBACK_SECRET}`
- **Payload**: Completion status, audio metadata

---

## Troubleshooting

### Hub Issues

**Kamal deploy fails with "no space left on device"**

Orphaned buildkit volumes from IP changes. See `hub/README.md` for cleanup steps.

**Magic link emails not sending**

Check `RESEND_API_KEY` and `MAILER_FROM_ADDRESS` in Kamal secrets.

### Generator Issues

**Build timeout**

- Verify `x86_64-linux` platform is in `Gemfile.lock`
- Build logs should show `Installing grpc x.x.x (x86_64-linux-gnu)`

**Host not permitted error**

- Verify `RACK_ENV=production` is set
- Check `:host_authorization` is in the `except:` list in `api.rb`

**GCS authentication error**

- Verify `RACK_ENV=production` is set
- Check service account has Storage permissions

**Callback to Hub failing**

- Verify `HUB_CALLBACK_URL` and `HUB_CALLBACK_SECRET` match Hub's config
- Check Hub logs for authentication errors

---

## Monitoring

### Hub Logs

```bash
cd hub
bin/kamal logs
```

### Generator Logs

```bash
gcloud run services logs read podcast-api \
  --project=$GOOGLE_CLOUD_PROJECT \
  --region=us-central1 \
  --limit=50
```

### Cloud Tasks

```bash
gcloud tasks queues describe episode-processing \
  --location=us-central1
```

---

## Rollback

### Hub

```bash
cd hub
bin/kamal rollback
```

### Generator

```bash
gcloud run services update-traffic podcast-api \
  --to-revisions=podcast-api-00010-abc=100 \
  --region=us-central1
```

List revisions:
```bash
gcloud run revisions list --service=podcast-api --region=us-central1
```
