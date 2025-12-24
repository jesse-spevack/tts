# TTS - Text-to-Speech Podcast Platform

Convert web articles and text into podcast episodes. Submit URLs through a web interface, and the system extracts content, generates audio, and publishes to your personal podcast RSS feed.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Hub (Rails App)                          │
│  • Web interface for URL/text submission                        │
│  • Magic link authentication                                    │
│  • Article extraction + LLM processing                          │
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
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Google Cloud Storage                          │
│  • Audio files (.mp3) and RSS feeds                             │
└─────────────────────────────────────────────────────────────────┘
```

## Components

| Component | Directory | Deployment |
|-----------|-----------|------------|
| **Hub** | `hub/` | Kamal → GCP VM |
| **Generator** | Root | Cloud Run |

## Documentation

- **Hub**: [`hub/README.md`](hub/README.md)
- **Deployment**: [`docs/deployment.md`](docs/deployment.md)

## Development

```bash
# Install dependencies
bundle install

# Run tests
rake test              # Generator
cd hub && bin/rails test  # Hub

# Lint
rake rubocop
```

## Deploy

```bash
./bin/deploy           # Generator to Cloud Run
cd hub && kamal deploy # Hub to GCP VM
```

## License

[OSaaS Dev License](LICENSE) - MIT with SaaS restriction
