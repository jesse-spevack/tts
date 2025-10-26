# Text-to-Speech Converter

Convert markdown files to MP3 audio using Google Cloud Text-to-Speech API.

## Setup

1. Install dependencies:
```bash
bundle install
```

2. Set up Google Cloud credentials:
   - Create a service account in Google Cloud Console
   - Download the JSON credentials file
   - Place it in the project root (it will be gitignored)

## Usage

Convert a markdown file to audio:

```bash
ruby generate.rb input/article.md
```

This will create `output/article.mp3`.

### Options

```bash
# Use a different voice
ruby generate.rb -v en-US-Chirp3-HD-Galahad input/article.md

# See all options
ruby generate.rb --help
```

## Features

- Converts markdown to plain text (strips formatting)
- Handles long documents by chunking text automatically
- Concurrent processing for faster generation
- Content filter handling (skips problematic chunks)
- Automatic retry for rate limits and timeouts

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
