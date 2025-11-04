# Monorepo Structure

**Decision:** Use a monorepo for Hub and Generator services

## Target Structure

```
tts-platform/                    # Root (current tts/ repo)
├── docs/                        # Shared documentation
│   ├── architecture/
│   │   ├── multiuser-architecture.md
│   │   ├── api-contracts.md
│   │   └── adr-001-multiuser-architecture.md
│   ├── deployment.md
│   └── migration-guide.md
│
├── generator/                   # Ruby TTS service (moved from root)
│   ├── lib/
│   │   ├── tts.rb
│   │   ├── text_processor.rb
│   │   ├── gcs_uploader.rb
│   │   └── ...
│   ├── test/
│   ├── api.rb
│   ├── generate.rb
│   ├── Gemfile
│   ├── Rakefile
│   ├── config/
│   │   └── podcast.yml
│   └── bin/
│       └── deploy
│
├── hub/                         # Rails app (new)
│   ├── app/
│   │   ├── controllers/
│   │   ├── models/
│   │   ├── views/
│   │   └── ...
│   ├── config/
│   ├── db/
│   ├── test/
│   ├── Gemfile
│   ├── Rakefile
│   └── bin/
│       └── deploy
│
├── bin/                         # Shared scripts
│   ├── deploy-all
│   └── setup
│
├── .github/
│   └── workflows/
│       ├── generator-ci.yml
│       └── hub-ci.yml
│
└── README.md                    # Overview of monorepo
```

## Migration Steps

### Phase 1: Restructure Current Repo (Generator)

1. **Create directory structure:**
   ```bash
   mkdir -p generator
   ```

2. **Move Generator files:**
   ```bash
   # Move code
   mv lib/ generator/
   mv test/ generator/
   mv api.rb generator/
   mv generate.rb generator/
   mv Gemfile generator/
   mv Gemfile.lock generator/
   mv Rakefile generator/
   mv config/ generator/

   # Move deployment
   mkdir -p generator/bin
   mv bin/deploy generator/bin/
   ```

3. **Update paths in Generator:**
   - Update `require_relative` paths if needed
   - Update Dockerfile (if exists) to use `generator/` context
   - Update `.env.example` paths

4. **Keep at root:**
   - `docs/` - shared documentation
   - `README.md` - update to explain monorepo structure
   - `.gitignore` - update for both services
   - `.github/` - CI/CD workflows

5. **Test Generator still works:**
   ```bash
   cd generator
   bundle install
   rake test
   ```

### Phase 2: Add Hub (New Rails App)

1. **Scaffold Rails app in hub/ directory:**
   ```bash
   rails new hub --database=sqlite3 --skip-test --css=tailwind
   ```

2. **Set up Hub structure:**
   - Configure Firebase Auth
   - Set up Stripe
   - Create models (User, Podcast, Episode, ApiKey)
   - Build controllers and views

3. **Add deployment script:**
   ```bash
   touch hub/bin/deploy
   chmod +x hub/bin/deploy
   ```

### Phase 3: Shared Infrastructure

1. **Create root README.md:**
   ```markdown
   # TTS Platform

   Monorepo containing Hub (Rails web app) and Generator (TTS service).

   ## Services

   - **Hub** (`hub/`): Web UI, API, billing
   - **Generator** (`generator/`): Audio generation service

   ## Getting Started

   See individual service READMEs:
   - [Hub README](hub/README.md)
   - [Generator README](generator/README.md)

   ## Documentation

   See [docs/architecture/](docs/architecture/) for system design.
   ```

2. **Update CI/CD workflows:**

   `.github/workflows/generator-ci.yml`:
   ```yaml
   name: Generator CI

   on:
     push:
       paths:
         - 'generator/**'
         - '.github/workflows/generator-ci.yml'

   jobs:
     test:
       runs-on: ubuntu-latest
       defaults:
         run:
           working-directory: generator
       steps:
         - uses: actions/checkout@v3
         - uses: ruby/setup-ruby@v1
           with:
             ruby-version: 3.4
             bundler-cache: true
         - run: bundle exec rake test
         - run: bundle exec rake rubocop
   ```

   `.github/workflows/hub-ci.yml`:
   ```yaml
   name: Hub CI

   on:
     push:
       paths:
         - 'hub/**'
         - '.github/workflows/hub-ci.yml'

   jobs:
     test:
       runs-on: ubuntu-latest
       defaults:
         run:
           working-directory: hub
       steps:
         - uses: actions/checkout@v3
         - uses: ruby/setup-ruby@v1
           with:
             ruby-version: 3.4
             bundler-cache: true
         - run: bundle exec rails test
         - run: bundle exec rubocop
   ```

3. **Create shared deploy script:**

   `bin/deploy-all`:
   ```bash
   #!/bin/bash
   set -e

   echo "Deploying Generator..."
   cd generator
   ./bin/deploy
   cd ..

   echo "Deploying Hub..."
   cd hub
   ./bin/deploy
   cd ..

   echo "✓ All services deployed"
   ```

## Working in the Monorepo

### Running Generator Locally
```bash
cd generator
bundle install
ruby generate.rb input/sample.md
```

### Running Hub Locally
```bash
cd hub
bundle install
rails server
```

### Running Tests

**Generator:**
```bash
cd generator
rake test
```

**Hub:**
```bash
cd hub
rails test
```

**All:**
```bash
# From root
(cd generator && rake test) && (cd hub && rails test)
```

### Deploying

**Generator only:**
```bash
cd generator
./bin/deploy
```

**Hub only:**
```bash
cd hub
./bin/deploy
```

**Both:**
```bash
./bin/deploy-all
```

## Benefits of This Structure

1. **Clear Separation:** Each service has its own directory with its own dependencies
2. **Shared Docs:** Architecture docs apply to whole system
3. **Smart CI/CD:** Only builds/tests/deploys what changed
4. **Local Development:** Each service can be developed independently
5. **Atomic Changes:** API contract changes can be committed with both implementations

## .gitignore Updates

Add to root `.gitignore`:
```
# Generator
generator/output/
generator/.env

# Hub
hub/tmp/
hub/log/
hub/storage/
hub/.env

# Shared
.DS_Store
*.log
```

## Environment Variables

Each service has its own `.env` file:

**generator/.env:**
```bash
GOOGLE_CLOUD_PROJECT=...
GOOGLE_CLOUD_BUCKET=...
HUB_CALLBACK_URL=https://hub.example.com
GENERATOR_CALLBACK_SECRET=...
```

**hub/.env:**
```bash
DATABASE_URL=sqlite3:db/production.sqlite3
FIREBASE_PROJECT_ID=...
STRIPE_API_KEY=...
GENERATOR_SERVICE_URL=https://generator.example.com
GENERATOR_CALLBACK_SECRET=...
GOOGLE_CLOUD_BUCKET=...
```

## Next Steps

1. Restructure current repo (move files to `generator/`)
2. Test Generator still works
3. Commit restructuring
4. Begin building Hub in `hub/` directory
5. Set up CI/CD workflows
6. Add shared deployment scripts
