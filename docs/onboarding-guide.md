# Onboarding Guide: Setting Up Your First Podcast

This guide walks you through setting up a new podcast from scratch using the TTS Podcast Generator.

## Prerequisites

- Ruby 3.4+ installed
- Google Cloud account with:
  - Cloud Storage bucket created
  - Cloud Text-to-Speech API enabled
  - Service account credentials downloaded
- `bundler` gem installed

## Step 1: Clone and Install

```bash
# Clone the repository
git clone <repository-url>
cd tts

# Install dependencies
bundle install
```

## Step 2: Create Your Podcast ID

Every podcast needs a unique identifier. Generate one:

```bash
echo "podcast_$(openssl rand -hex 8)"
```

Example output: `podcast_a1b2c3d4e5f6a7b8`

**Important:** Save this ID - it's permanent for your podcast. You cannot change it after publishing episodes.

## Step 3: Configure Environment

Copy the example environment file:
```bash
cp .env.example .env
```

Edit `.env` and add your configuration:

```bash
# Google Cloud Configuration
GOOGLE_CLOUD_PROJECT=your-project-id
GOOGLE_CLOUD_BUCKET=your-bucket-name
GOOGLE_APPLICATION_CREDENTIALS=./credentials.json

# Your Podcast ID (from Step 2)
PODCAST_ID=podcast_a1b2c3d4e5f6a7b8

# Optional: API Configuration (if using the API)
SERVICE_URL=https://your-service.run.app
CLOUD_TASKS_LOCATION=us-west3
CLOUD_TASKS_QUEUE=episode-processing
```

## Step 4: Configure Podcast Metadata

Edit `config/podcast.yml` with your podcast details:

```yaml
title: "Your Podcast Title"
description: "A compelling description of your podcast"
author: "Your Name"
language: "en-us"
category: "Technology"
subcategory: "Tech News"
explicit: false
copyright: "© 2024 Your Name"
image_url: "https://your-bucket.storage.googleapis.com/artwork.jpg"
```

## Step 5: Add Google Cloud Credentials

Place your service account credentials file:
```bash
# Copy your downloaded credentials
cp ~/Downloads/your-project-credentials.json ./credentials.json

# Make sure it's in .gitignore (already included)
grep credentials.json .gitignore
```

## Step 6: Verify Setup

Test your configuration:
```bash
# Check environment variables
source .env
echo "Project: $GOOGLE_CLOUD_PROJECT"
echo "Bucket: $GOOGLE_CLOUD_BUCKET"
echo "Podcast ID: $PODCAST_ID"

# Verify bucket access
gsutil ls gs://$GOOGLE_CLOUD_BUCKET/
```

## Step 7: Create Your First Episode

### Create an input file

Create a markdown file with YAML frontmatter:

```bash
cat > input/my-first-episode.md << 'EOF'
---
title: "Welcome to My Podcast"
description: "An introduction to what this podcast is all about"
author: "Your Name"
---

Welcome to my podcast! In this first episode, I want to introduce you to what we'll be covering.

## What to Expect

Each episode will dive deep into topics I'm passionate about. We'll explore ideas, share insights, and hopefully learn something new together.

## Format

Episodes will typically run 10-20 minutes and come out weekly.

Thanks for listening!
EOF
```

### Generate the episode

```bash
ruby generate.rb input/my-first-episode.md
```

You should see:
```
============================================================
Text-to-Speech Podcast Generator
============================================================
Input file: input/my-first-episode.md
Voice: en-GB-Chirp3-HD-Enceladus
Mode: Publish to podcast feed
============================================================

[1/5] Extracting metadata...
✓ Metadata extracted
  Title: Welcome to My Podcast
  Description: An introduction to what this podcast is all about

[2/5] Processing markdown file...
✓ Converted markdown to plain text
  Text length: XXX characters

[3/5] Generating audio...
✓ Audio generated successfully
  Audio size: XXX bytes

[4/5] Saving audio file...
✓ Audio saved to: output/my-first-episode.mp3
  File size: XX KB

[5/5] Publishing to podcast feed...
✓ Episode published successfully
  Podcast ID: podcast_a1b2c3d4e5f6a7b8
  Feed URL: https://storage.googleapis.com/your-bucket/podcasts/podcast_a1b2c3d4e5f6a7b8/feed.xml
  Episodes in feed: 1
```

## Step 8: Verify Your Feed

### Check the storage structure

```bash
gsutil ls -r gs://$GOOGLE_CLOUD_BUCKET/podcasts/$PODCAST_ID/
```

You should see:
```
gs://your-bucket/podcasts/podcast_xxx/episodes/
gs://your-bucket/podcasts/podcast_xxx/feed.xml
gs://your-bucket/podcasts/podcast_xxx/manifest.json

gs://your-bucket/podcasts/podcast_xxx/episodes/:
gs://your-bucket/podcasts/podcast_xxx/episodes/20241102-123456-welcome-to-my-podcast.mp3
```

### Test the RSS feed

```bash
curl "https://storage.googleapis.com/$GOOGLE_CLOUD_BUCKET/podcasts/$PODCAST_ID/feed.xml" | head -50
```

You should see valid RSS XML with your episode listed.

## Step 9: Subscribe in a Podcast App

Your podcast feed URL is:
```
https://storage.googleapis.com/YOUR_BUCKET/podcasts/YOUR_PODCAST_ID/feed.xml
```

**Save this URL!** You'll need it for:
- Subscribing in podcast apps
- Sharing with listeners
- Submitting to podcast directories

### Testing in a podcast app

1. Open your favorite podcast app (Apple Podcasts, Overcast, Pocket Casts, etc.)
2. Find the "Add by URL" or "Add private podcast" option
3. Paste your feed URL
4. Your podcast should appear with your first episode
5. Test playing the episode

## Step 10: Create More Episodes

Now you can create more episodes:

```bash
# Generate locally without publishing (for testing)
ruby generate.rb --local-only input/episode-02.md

# Publish to feed
ruby generate.rb input/episode-02.md

# Use a different voice
ruby generate.rb -v en-US-Chirp3-HD-Galahad input/episode-03.md
```

## Optional: Deploy the API

If you want to use the API for remote episode submission:

1. Review the deployment docs:
   ```bash
   cat docs/deployment.md
   ```

2. Deploy to Cloud Run:
   ```bash
   ./bin/deploy
   ```

3. Test the API:
   ```bash
   TOKEN=$(gcloud auth print-identity-token)

   curl -X POST https://your-service.run.app/publish \
     -H "Authorization: Bearer $TOKEN" \
     -F "podcast_id=$PODCAST_ID" \
     -F "title=API Test Episode" \
     -F "author=Your Name" \
     -F "description=Testing the API" \
     -F "content=@input/test.md"
   ```

## Directory Structure

Your podcast files will be organized like this:

```
GCS Bucket Structure:
podcasts/
  └── podcast_a1b2c3d4e5f6a7b8/     # Your podcast ID
      ├── episodes/
      │   ├── 20241101-120000-episode-1.mp3
      │   ├── 20241102-140000-episode-2.mp3
      │   └── ...
      ├── feed.xml                   # RSS feed (what podcast apps read)
      ├── manifest.json              # Episode metadata
      └── staging/                   # Temporary uploads (API only)

Local Project Structure:
input/                              # Your markdown source files
output/                            # Generated MP3s (local copies)
config/
  └── podcast.yml                  # Podcast metadata
lib/                               # Application code
test/                              # Test suite
```

## Tips for Success

### Creating Good Episodes

1. **Frontmatter is required** - Every input file needs title, description, and author
2. **Markdown formatting** - Headers, lists, bold, italic are all stripped for TTS
3. **Keep it conversational** - Write how you'd speak, not how you'd write formally
4. **Length** - Aim for 1,000-3,000 words (10-20 minute episodes)

### Voice Selection

Available voices (set with `-v` flag):
- `en-GB-Chirp3-HD-Enceladus` (default) - British male
- `en-US-Chirp3-HD-Galahad` - American male
- `en-US-Chirp3-HD-Aoede` - American female

Test different voices to find what fits your podcast!

### Cost Management

- TTS costs: ~$16 per 1 million characters
- Storage costs: ~$0.02 per GB per month
- Transfer costs: ~$0.12 per GB (when listeners download)

A typical 2,000 word episode (~10 minutes):
- Characters: ~10,000
- TTS cost: ~$0.16
- Storage: ~10 MB (~$0.0002/month)

### Workflow Tips

1. **Test locally first**: Use `--local-only` to preview episodes
2. **Version control**: Keep your input markdown files in git
3. **Backup**: Your source files are more valuable than the generated audio
4. **Feed URL**: Save it somewhere safe - you'll need it often

## Next Steps

- Read the [README](../README.md) for more usage details
- Check out [deployment.md](deployment.md) for API deployment
- Review available voices and options with `ruby generate.rb --help`
- Create a publishing schedule and start producing content!

## Troubleshooting

### "PODCAST_ID environment variable is required"

Make sure you've added `PODCAST_ID` to your `.env` file and run:
```bash
source .env
```

### "Invalid podcast_id format"

Podcast IDs must be: `podcast_` + 16 hex characters

Generate a new one:
```bash
echo "podcast_$(openssl rand -hex 8)"
```

### "Bucket not found" or permission errors

Check your service account has these IAM roles:
- Storage Object Admin (or Storage Object Creator + Storage Object Viewer)
- Cloud Text-to-Speech User

### Feed not updating in podcast app

Podcast apps cache feeds. Try:
1. Remove and re-add the podcast
2. Wait 15-30 minutes for the cache to expire
3. Check the feed.xml directly via curl to confirm it updated

### Audio quality issues

- Try different voices with the `-v` flag
- Check your markdown - complex formatting might not convert well
- Keep sentences shorter and more conversational

## Support

For issues:
1. Check the [troubleshooting section](#troubleshooting)
2. Review logs: `cat logs/*.log` (if you've run the API)
3. Verify your GCS bucket permissions
4. Check that all environment variables are set correctly
