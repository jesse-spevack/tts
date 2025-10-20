# Text-to-Speech Podcast Feed - Simplified MVP Plan

## MVP Goal
Create a working personal podcast feed that converts web articles to audio.
Timeline: 3-4 days to working product.

---

## MILESTONE 1: First Audio File (Day 1)
**Goal**: Generate one article as an audio file

### Tasks:
1. GCP Setup (30 min)
   - Create project, enable APIs (Text-to-Speech, Storage, Firestore)
   - Install gcloud CLI, authenticate
   - Create storage bucket

2. Local Ruby Setup (30 min)
   - Initialize project with Gemfile
   - Install gems: google-cloud-text_to_speech, google-cloud-storage, google-cloud-firestore, nokogiri, ruby-readability, httparty

3. Build Core Pipeline (2-3 hours)
   - Text extraction: fetch URL, extract article text
   - TTS conversion: send text to Google TTS API
   - Save audio file locally

**Success Criteria**: Run a script that takes a URL and outputs an MP3 file you can play.

---

## MILESTONE 2: Cloud Storage & Database (Day 2)
**Goal**: Store audio files and article metadata in the cloud

### Tasks:
1. Storage Module (1 hour)
   - Upload MP3 to Cloud Storage
   - Make files publicly accessible
   - Get public URLs

2. Database Module (1 hour)
   - Save article metadata to Firestore (URL, title, audio_url, date)
   - Query articles by date
   - Check for duplicates

3. Integration Test (1 hour)
   - Process 3-5 articles end-to-end
   - Verify files in Cloud Storage
   - Verify metadata in Firestore

**Success Criteria**: Articles stored in cloud with public audio URLs that play in browser.

---

## MILESTONE 3: RSS Feed (Day 3)
**Goal**: Generate a podcast feed you can subscribe to

### Tasks:
1. RSS Generator (2 hours)
   - Query Firestore for all articles
   - Generate valid RSS 2.0 XML with iTunes tags
   - Upload feed.xml to Cloud Storage
   - Make feed publicly accessible

2. Test Subscription (1 hour)
   - Get feed URL from Cloud Storage
   - Add to podcast app (Overcast, Pocket Casts, etc.)
   - Verify episodes appear and play

**Success Criteria**: Successfully listening to your articles in a podcast app.

---

## MILESTONE 4: Cloud Function (Day 4)
**Goal**: Deploy as a serverless function with a simple API

### Tasks:
1. Create HTTP Function (2 hours)
   - Wrap pipeline in Functions Framework
   - Accept URL as POST parameter
   - Return success/error JSON response

2. Test Locally (30 min)
   - Run function locally
   - Test with curl

3. Deploy to GCP (1 hour)
   - Deploy Cloud Function (2nd gen)
   - Test deployed endpoint
   - Create helper script for submitting URLs

**Success Criteria**: Send a URL via HTTP request, get article in podcast feed within 1-2 minutes.

---

## Post-MVP (Week 2+)
**Only add these after MVP is working**

### Phase 5: Polish
- Error handling and retry logic
- Better logging
- Cost monitoring setup
- Documentation

### Phase 6: Multi-User Support
- User ID handling (via header)
- Separate feeds per user
- Basic authentication (API keys)

### Phase 7: Scale Features
- Web interface
- Rate limiting
- Advanced voice options
- Custom podcast metadata

---

## Architecture (MVP)

```
User submits URL
    ↓
Cloud Function (Ruby)
    ↓
1. Extract text (Readability)
2. Convert to speech (Google TTS)
3. Upload audio (Cloud Storage)
4. Save metadata (Firestore)
5. Regenerate RSS feed
    ↓
Podcast app pulls feed every N hours
```

## File Structure (MVP)

```
podcast-tts/
├── app.rb                    # Cloud Function entry point
├── Gemfile
├── lib/
│   ├── extractor.rb         # Text extraction
│   ├── tts.rb               # Text-to-Speech
│   ├── storage.rb           # Cloud Storage
│   ├── database.rb          # Firestore
│   └── rss_generator.rb     # RSS feed
└── submit_article.rb         # Helper script
```

## Estimated Costs (Personal Use)

- 10 articles/month, ~3000 words each
- TTS: $2-4/month (Google Neural2 voices)
- Storage: $0.50/month
- Cloud Functions: Free tier
- Firestore: Free tier
- **Total: $3-5/month**

## Scaling Strategy

The architecture supports multi-user from day one:
- User ID already in storage paths: `/podcasts/{user_id}/`
- User ID already in Firestore structure: `/users/{user_id}/articles/`
- To add users: just pass different user_id in request header

No architecture changes needed to support 10, 100, or 1000 users.

---

## What We Removed From Original Plan

- Detailed step-by-step code (write as you go)
- Extensive testing sections (test as you build)
- Advanced error handling (add after MVP works)
- Authentication (use simple header for now)
- Web interface (API-first approach)
- Monitoring setup (add when you have users)
- Multiple deployment checklists (deploy once it works)

## Critical Path Only

Day 1: Can you generate audio from a URL?
Day 2: Can you store it in the cloud?
Day 3: Can you subscribe to it in a podcast app?
Day 4: Can you submit URLs via HTTP?

Everything else is post-MVP.
