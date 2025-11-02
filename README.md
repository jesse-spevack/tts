# Text-to-Speech Podcast Generator

Convert markdown articles to podcast episodes with automated publishing to RSS feed.

## Setup

1. Install dependencies:
```bash
bundle install
```

2. Configure environment variables (copy `.env.example` to `.env`):
   - Google Cloud credentials path
   - GCS bucket name and base URL
   - Podcast metadata (title, description, author, etc.)

## Usage

### Local Generation

Generate and publish a podcast episode locally:

```bash
ruby generate.rb input/article.md
```

This creates an MP3, uploads it to GCS, updates the episode manifest, and regenerates the RSS feed.

### API Request

Submit an episode for processing via the deployed API:

```bash
curl -X POST https://your-service-url.run.app/publish \
  -H "Authorization: Bearer $API_SECRET_TOKEN" \
  -F "title=Episode Title" \
  -F "author=Author Name" \
  -F "description=Episode description" \
  -F "content=@input/article.md"
```

Response:
```json
{"status":"success","message":"Episode submitted for processing"}
```

The API processes episodes asynchronously via Cloud Tasks. Check Cloud Run logs to monitor processing status.

### Options

```bash
# Generate locally without publishing
ruby generate.rb --local-only input/article.md

# Use a different voice
ruby generate.rb -v en-US-Chirp3-HD-Galahad input/article.md

# See all options
ruby generate.rb --help
```

### Creating Input Files

Input files should be markdown documents with YAML frontmatter at the top. Use the `/generate-input-md` slash command in Claude Code to create properly formatted input files.

#### YAML Frontmatter Format

All input markdown files must include YAML frontmatter with the following fields:

```yaml
---
title: "Your Episode Title"
description: "A brief description of the episode content"
author: "Author Name"
---
```

**Required fields:**
- `title`: The episode title (enclosed in quotes if it contains special characters)
- `description`: A short description of the episode (enclosed in quotes)
- `author`: The author's name (enclosed in quotes)

**Example:**
```yaml
---
title: "The New Calculus of AI-based Coding"
description: "An exploration of how AI-assisted development can achieve 10x productivity gains, and why succeeding at this scale requires fundamental changes to testing, deployment, and team coordination practices."
author: "Joe Magerramov"
---
```

After the frontmatter, include your markdown content. The system will strip markdown formatting (headers, bold, links, etc.) and convert it to plain text suitable for text-to-speech processing.

## Features

- **Text-to-Speech**: Converts markdown to natural-sounding audio using Google Cloud TTS
- **Podcast Publishing**: Automatically publishes to RSS feed with iTunes tags
- **Episode Management**: Tracks all episodes in a manifest with metadata
- **Cloud Storage**: Uploads audio files to Google Cloud Storage
- **Frontmatter Support**: Extracts title, description, and author from YAML frontmatter
- **Chunking & Concurrency**: Handles long documents with parallel processing
- **Error Handling**: Automatic retry for rate limits, timeouts, and content filters

## Testing

Run all tests:

```bash
rake test
```

Run RuboCop linter:

```bash
rake rubocop
```

## Deploy

The API is deployed to Google Cloud Run for asynchronous episode processing.

```bash
./bin/deploy
```

See [docs/deployment.md](docs/deployment.md) for detailed deployment instructions, architecture overview, and troubleshooting guide.


## License

MIT
