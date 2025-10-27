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

Generate and publish a podcast episode:

```bash
ruby generate.rb input/article.md
```

This creates an MP3, uploads it to GCS, updates the episode manifest, and regenerates the RSS feed.

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

Use the `/generate-input-md` slash command in Claude Code to create properly formatted input files with frontmatter.

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

## License

MIT
