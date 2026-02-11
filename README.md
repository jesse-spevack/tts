# Very Normal TTS

A Ruby on Rails application that converts web articles, pasted text, and uploaded files into podcast episodes using text-to-speech. Submit content through any of three input methods, and the app extracts the content, processes it with an LLM for cleanup and metadata extraction, and generates audio episodes delivered via a private RSS feed compatible with any podcast player.

**Live Site:** [tts.verynormal.dev](https://tts.verynormal.dev)

## Features

- **Three Input Methods**:
  - **URL to Podcast**: Paste any article URL - content is fetched, extracted, and converted
  - **Paste Text**: Directly paste article text for conversion
  - **Markdown Upload**: Upload `.md` or `.txt` files with custom title, author, and description

- **Personal RSS Feed**: Each user gets a private podcast feed that works with Apple Podcasts, Spotify, Overcast, Pocket Casts, and any app supporting custom RSS feeds

- **Magic Link Authentication**: Passwordless login via email - no passwords to remember

- **Multiple Voice Options**: 8 natural-sounding voices with different accents and genders
  - Standard tier: 4 voices (Wren, Felix, Sloane, Archer)
  - Unlimited tier: 8 voices including Chirp HD voices (Elara, Callum, Lark, Nash)

- **User Tiers**:
  - **Free**: 2 episodes/month, 15,000 character limit per episode
  - **Premium**: Unlimited episodes, 50,000 character limit per episode
  - **Unlimited**: Unlimited episodes, no character limit, access to premium Chirp HD voices

- **Real-time Status Updates**: Episode cards update live via Turbo Streams as processing completes

- **Dark/Light Theme**: Theme toggle with preference persistence

- **Admin Analytics**: Page view tracking and analytics dashboard for administrators

## Tech Stack

### Backend
- **Framework**: Ruby on Rails 8.1
- **Ruby**: 3.4.5
- **Database**: SQLite (production uses persistent storage via Kamal)
- **Background Jobs**: Solid Queue (runs in-process with Puma in production)
- **Cache**: Solid Cache
- **Real-time**: Action Cable with Solid Cable

### Frontend
- **JavaScript**: Hotwire (Turbo + Stimulus) with Import Maps
- **CSS**: Tailwind CSS via tailwindcss-rails
- **Asset Pipeline**: Propshaft

### External Services
- **Google Cloud Text-to-Speech**: Audio synthesis (supports both Standard and Chirp HD voices)
- **Google Cloud Storage**: Audio file and RSS feed hosting
- **Vertex AI (Gemini 2.5 Flash)**: LLM for content extraction, cleanup, and metadata generation
- **Resend**: Email delivery for magic links and notifications

## Development Setup

### Prerequisites

- Ruby 3.4.5
- SQLite 3
- Node.js (for Tailwind CSS build)
- Google Cloud credentials (for TTS, Storage, and Vertex AI)

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd tts

# Install Ruby dependencies
bundle install

# Setup database
bin/rails db:setup

# Start the development server
bin/dev
```

### Development Server

`bin/dev` starts:
- Rails server on port 3000
- Tailwind CSS watch process
- Solid Queue job processor (via Puma in development)

### Running Tests

```bash
# Run all tests
bin/rails test

# Run system tests (requires Chrome)
bin/rails test:system

# Run a specific test file
bin/rails test test/services/process_url_episode_test.rb

# Run with parallel workers
PARALLEL_WORKERS=4 bin/rails test
```

### Code Quality

```bash
# Lint with RuboCop
bin/rubocop

# Security scan
bin/brakeman --no-pager

# Gem vulnerability audit
bin/bundler-audit

# JavaScript dependency audit
bin/importmap audit
```

## Environment Variables

### Required for Production

| Variable | Description |
|----------|-------------|
| `RAILS_MASTER_KEY` | Rails credentials encryption key |
| `RESEND_API_KEY` | Resend API key for email delivery |
| `GOOGLE_CLOUD_PROJECT` | Google Cloud project ID |
| `GOOGLE_CLOUD_BUCKET` | GCS bucket name for audio/feeds |
| `SERVICE_ACCOUNT_EMAIL` | GCP service account email |
| `VERTEX_AI_LOCATION` | Vertex AI region (e.g., `us-central1`) |
| `APP_HOST` | Production hostname |
| `MAILER_FROM_ADDRESS` | Email sender address |

### Optional

| Variable | Description | Default |
|----------|-------------|---------|
| `GENERATOR_CALLBACK_SECRET` | Secret for internal episode API callbacks | - |

## Architecture

### Request Flow

```
User submits URL/Text/File
         │
         ▼
┌─────────────────────┐
│ EpisodesController  │  Creates Episode record (status: processing)
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│ Process*EpisodeJob  │  Background job via Solid Queue
└─────────────────────┘
         │
         ├── URL: FetchesUrl → ExtractsArticle → ProcessesWithLlm
         ├── Paste: ProcessesWithLlm
         └── File: StripsMarkdown (no LLM needed)
         │
         ▼
┌─────────────────────┐
│ GeneratesEpisodeAudio│  Google Cloud TTS synthesis
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│ CloudStorage        │  Upload audio + regenerate RSS feed
└─────────────────────┘
         │
         ▼
Episode status → complete
Turbo Stream updates UI
Email notification (first episode only)
```

### Key Models

| Model | Purpose |
|-------|---------|
| `User` | Account with email, tier, voice preference |
| `Podcast` | Container for episodes, has unique `podcast_id` for GCS paths |
| `Episode` | Individual audio episode with status, metadata, source content |
| `PodcastMembership` | Join table linking users to podcasts |
| `Session` | Authentication session (cookie-based) |
| `EpisodeUsage` | Monthly episode count for free tier limits |
| `LlmUsage` | Tracks LLM token usage and costs per episode |
| `SentMessage` | Prevents duplicate notification emails |
| `PageView` | Anonymous analytics for landing pages |

### Service Objects

The application uses service objects extensively for business logic:

- **Episode Creation**: `CreatesUrlEpisode`, `CreatesPasteEpisode`, `CreatesFileEpisode`
- **Episode Processing**: `ProcessesUrlEpisode`, `ProcessesPasteEpisode`, `ProcessesFileEpisode`
- **Audio Generation**: `SynthesizesAudio`, `Tts::ApiClient`, `Tts::ChunkedSynthesizer`
- **Content Processing**: `FetchesUrl`, `ExtractsArticle`, `ProcessesWithLlm`, `StripsMarkdown`
- **Authentication**: `SendsMagicLink`, `AuthenticatesMagicLink`, `GeneratesAuthToken`, `VerifiesHashedToken`
- **Permissions**: `ChecksEpisodeCreationPermission`, `CalculatesMaxCharactersForUser`

### Result Pattern

Services return `Result` or `Outcome` objects:

```ruby
# Result: for data-returning operations
result = CreatesUrlEpisode.call(podcast: podcast, user: user, url: url)
if result.success?
  episode = result.data
else
  error = result.error
end

# Outcome: for yes/no operations with optional data
outcome = ChecksEpisodeCreationPermission.call(user: user)
if outcome.success?
  remaining = outcome.data[:remaining]
else
  message = outcome.message
end
```

## Deployment

Deployed via [Kamal](https://kamal-deploy.org/) to Google Cloud Platform.

### Deploy Commands

```bash
# Deploy to production
bin/kamal deploy

# Rails console on production
bin/kamal console

# View logs
bin/kamal logs

# SSH shell access
bin/kamal shell

# Database console
bin/kamal dbc
```

### Infrastructure

- **Container Registry**: Google Artifact Registry (`us-docker.pkg.dev`)
- **Web Server**: Puma with Thruster (HTTP/2, asset compression)
- **SSL**: Auto-provisioned via Let's Encrypt (Kamal proxy)
- **Storage**: Persistent Docker volume for SQLite database

## Project Structure

```
app/
├── controllers/
│   ├── api/internal/      # Internal callbacks from job processing
│   ├── admin/             # Admin-only controllers
│   └── concerns/          # Authentication, Trackable
├── helpers/               # View helpers (UI, Episodes, Logging)
├── javascript/controllers/ # Stimulus controllers
├── jobs/                  # Solid Queue background jobs
├── mailers/               # Magic link and notification emails
├── models/                # ActiveRecord models + Result/Outcome
├── services/              # Business logic service objects
│   ├── tts/              # TTS-specific classes
│   └── concerns/         # EpisodeLogging
└── views/
    ├── episodes/         # Episode CRUD views
    ├── pages/            # Landing page, static pages
    ├── settings/         # Voice preference settings
    └── shared/           # Partials, icons, layouts

config/
├── deploy.yml            # Kamal deployment configuration
├── routes.rb             # Application routes
└── initializers/         # Resend, RubyLLM configuration

test/
├── controllers/          # Controller tests
├── fixtures/             # Test data
├── helpers/              # Helper tests
├── integration/          # Integration tests
├── jobs/                 # Job tests
├── mailers/              # Mailer tests
├── models/               # Model tests
├── services/             # Service object tests
└── test_helpers/         # Session helper for authentication
```

## License

This project is licensed under the [O'Saasy License](LICENSE.md). Copyright © 2025, Jesse Spevack.
