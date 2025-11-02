# Deployment Guide

This document describes how to deploy the TTS API to Google Cloud Run.

## Overview

The TTS API is deployed as a containerized service on Google Cloud Run. The deployment includes:

- **API Server**: Sinatra-based REST API for episode publishing
- **Background Processing**: Cloud Tasks integration for async episode processing
- **Storage**: Google Cloud Storage for markdown files, MP3s, and RSS feeds
- **Authentication**: Bearer token authentication for API requests

## Prerequisites

1. **Google Cloud Project**: Set up with billing enabled
2. **Required APIs**: Enable Cloud Run, Cloud Build, Cloud Storage, Cloud Tasks
3. **Service Account**: `tts-service-account` with permissions for GCS and Cloud Tasks
4. **Environment File**: Create `.env` with required variables (see below)

## Environment Variables

Create a `.env` file in the project root:

```bash
GOOGLE_CLOUD_PROJECT=your-project-id
GOOGLE_CLOUD_BUCKET=your-bucket-name
API_SECRET_TOKEN=your-secure-token
CLOUD_TASKS_LOCATION=us-west3
CLOUD_TASKS_QUEUE=episode-processing
```

## Deployment Command

```bash
./bin/deploy
```

This script performs:
1. **Build**: Creates Docker image with 20-minute timeout (for grpc compilation)
2. **Deploy**: Deploys to Cloud Run with production configuration
3. **Update**: Adds SERVICE_URL for Cloud Tasks callbacks

## Build Optimizations

### Precompiled Binaries
The `Gemfile.lock` includes the `x86_64-linux` platform to use precompiled binaries for:
- `grpc` (19.8 MB precompiled vs 18+ minutes compilation)
- `google-protobuf` (precompiled)

To add platform support:
```bash
bundle lock --add-platform x86_64-linux
```

### Build Timeout
The deploy script uses a 20-minute timeout to handle cases where grpc needs compilation. With precompiled binaries, builds typically complete in 2-3 minutes.

## Production Configuration

### RACK_ENV=production
Setting `RACK_ENV=production` is critical for:
- **Sinatra**: Disables default host authorization that would block external requests
- **GCS SDK**: Allows automatic service account authentication (no `GOOGLE_APPLICATION_CREDENTIALS` needed)

### Rack Protection
The API disables specific Rack::Protection middleware:
- `json_csrf`: Not needed with Bearer token authentication
- `host_authorization`: Not needed with token auth, would block Cloud Run requests

Other protections (XSS, frame options, path traversal) remain enabled.

### Service Account
Cloud Run uses the service account for:
- Reading/writing to Google Cloud Storage
- Creating Cloud Tasks for background processing
- No credential files needed in production

## Deployment Architecture

```
./bin/deploy
    ↓
1. Build Docker Image (Cloud Build)
    - Uses Dockerfile with Ruby 3.4-slim
    - Installs gems (including precompiled grpc)
    - Copies application code
    ↓
2. Deploy to Cloud Run
    - Sets environment variables (including RACK_ENV=production)
    - Configures 2Gi memory, 4 CPU, 600s timeout
    - Max 1 instance, min 0 instances
    ↓
3. Update with SERVICE_URL
    - Adds service URL for Cloud Tasks callbacks
    - Preserves all other environment variables
```

## Deployed Service

**URL**: `https://podcast-api-{hash}.us-west3.run.app`

### Endpoints

#### Health Check
```bash
curl https://your-service-url/health
```

Returns service health and validates environment variables.

#### Publish Episode
```bash
curl -X POST https://your-service-url/publish \
  -H "Authorization: Bearer $API_SECRET_TOKEN" \
  -F "title=Episode Title" \
  -F "author=Author Name" \
  -F "description=Episode description" \
  -F "content=@article.md"
```

This endpoint:
1. Validates authentication
2. Uploads markdown to GCS staging
3. Enqueues background processing task
4. Returns immediately with success response

#### Process Episode (Internal)
```bash
POST /process
```

This endpoint is called by Cloud Tasks to:
1. Download markdown from staging
2. Convert to plain text
3. Synthesize speech with Google TTS
4. Upload MP3 and update RSS feed
5. Clean up staging files

## Troubleshooting

### Build Timeout
If builds timeout (10 minutes default):
- Verify `x86_64-linux` platform is in `Gemfile.lock`
- Check that precompiled grpc binaries are being used
- Build logs should show `Installing grpc 1.76.0 (x86_64-linux-gnu)`

### Host Not Permitted Error
If you get "Host not permitted" errors:
- Verify `RACK_ENV=production` is set in Cloud Run
- Check that `:host_authorization` is in the `except:` list in `api.rb`

### GCS Authentication Error
If you get "GOOGLE_APPLICATION_CREDENTIALS not set":
- Verify `RACK_ENV=production` is set
- Check that service account has Storage permissions
- The GCS uploader skips credential checks in production

### Environment Variables Missing
If env vars aren't set after deployment:
- Check that the final update includes ALL variables
- `--set-env-vars` replaces (doesn't merge) all variables
- Review the deploy script's update command

## Monitoring

View logs:
```bash
gcloud run services logs read podcast-api \
  --project=your-project \
  --region=us-west3 \
  --limit=50
```

Check service status:
```bash
gcloud run services describe podcast-api \
  --project=your-project \
  --region=us-west3
```

## Rollback

To rollback to a previous revision:
```bash
gcloud run services update-traffic podcast-api \
  --to-revisions=podcast-api-00010-abc=100 \
  --region=us-west3
```

List revisions:
```bash
gcloud run revisions list \
  --service=podcast-api \
  --region=us-west3
```
