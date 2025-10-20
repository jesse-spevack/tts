# Text-to-Speech Converter

A Ruby script that converts markdown files to MP3 audio files using a TTS API.

## Project Status

Currently implemented:
- [x] Project setup with directory structure
- [x] Text processing module (markdown to plain text conversion)
- [x] Unit tests for text processor

## Setup

1. Install dependencies:
```bash
bundle install
```

2. Configure API keys in `.env` file (for TTS providers - not yet implemented)

## Usage

### Text Processing (Current)

Convert a markdown file to plain text:

```bash
ruby test_processor.rb input/sample.md
```

### Full TTS Conversion (Coming Soon)

```bash
ruby generate.rb input/article.md
```

This will create `output/article.mp3`.

## Project Structure

```
.
├── input/          # Place markdown files here
├── output/         # Generated MP3 files (gitignored)
├── lib/
│   └── text_processor.rb   # Markdown to text conversion
├── test/
│   └── test_text_processor.rb   # Unit tests
├── Gemfile         # Ruby dependencies
├── .env            # API keys (gitignored)
└── README.md       # This file
```

## Text Processing Features

The text processor handles:
- Headers (removes # symbols)
- Bold and italic text
- Links (keeps link text, removes URLs)
- Images (removes completely)
- Code blocks (removes completely)
- Inline code (removes backticks)
- Lists (removes markers)
- Blockquotes (removes > markers)
- HTML tags
- Horizontal rules
- Strikethrough text

## Testing

Run unit tests:

```bash
ruby test/test_text_processor.rb
```

## Next Steps

See TASKS.md for the full implementation plan. The next phase includes:
- TTS provider integration (Google Cloud TTS, OpenAI, or ElevenLabs)
- Audio file generation
- Main script integration
- End-to-end testing

## License

MIT
