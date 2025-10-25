# Tasks for Text-to-Speech MVP

## Goal
Build a Ruby script that converts markdown files to MP3 audio files using a TTS API.

**Scope**: Markdown → Plain Text → TTS → MP3

## Current Status
✅ **MVP Complete!** Core functionality is working end-to-end.

**Remaining**: Testing and refinement (Task 6.0)

---

## Tasks

- [x] 1.0 Project Setup
  - [x] 1.1 Create project directory structure (input/, output/, lib/, test/)
  - [x] 1.2 Initialize Gemfile with required gems
  - [x] 1.3 Run bundle install
  - [x] 1.4 Create .env file for API keys
  - [x] 1.5 Create .gitignore (ignore .env, output/, input/)
  - [x] 1.6 Add minitest gem

- [x] 2.0 Text Processing Module
  - [x] 2.1 Create lib/text_processor.rb
    ```ruby
        file = File.open(path)
        text = TextProcessor.markdown_to_text(file)
        # text processor errors if file is not markdown
        # otherwise text processor returns clean text ideal for tts API call
    ```
  - [x] 2.2 Implement markdown file reading
  - [x] 2.3 Implement regex-based markdown to plain text conversion
  - [x] 2.4 Handle: headers, bold, italic, links, code blocks, lists, images
  - [x] 2.5 Write unit tests for common markdown to text cases

- [x] 3.0 TTS Provider Selection and Integration
  - [x] 3.0.1 Research Google Cloud TTS integration
    - Set up Google Cloud project and enable Text-to-Speech API and Vertex AI API
    - Created service account with TTS and Vertex AI User roles
    - Configured authentication via JSON credentials file
  - [x] 3.2 Add Google Cloud TTS gem to Gemfile
  - [x] 3.3 Set up API credentials in .env (GOOGLE_APPLICATION_CREDENTIALS)
  - [x] 3.4 Create lib/tts.rb module
    ```ruby
        tts = TTS.new(provider: :google)
        # Using Gemini 2.5 Pro TTS model with Charon voice
    ```
  - [x] 3.5 Implement basic TTS API call (Gemini 2.5 Pro TTS, Charon voice, 1.5x speed)
  - [x] 3.6 Handle text chunking (5000 char limit with sentence boundary splitting)
  - [x] 3.7 Test with short text sample

- [x] 4.0 Audio File Generation
  - [x] 4.1 Implement audio content saving to MP3 file
  - [x] 4.2 Generate filename from markdown title/filename
  - [x] 4.3 Save to output/ directory
  - [x] 4.4 Test generated MP3 plays correctly

- [x] 5.0 Main Script Integration
  - [x] 5.1 Create generate.rb main script
  - [x] 5.2 Add command-line argument parsing (input file path, provider, voice)
  - [x] 5.3 Wire together: read MD → process text → generate audio → save MP3
  - [x] 5.4 Add progress output/logging
  - [x] 5.5 Add error handling for missing files, API failures
  - [x] 5.6 Test end-to-end with real blog article

- [ ] 6.0 Testing and Refinement
  - [ ] 6.1 Test with 3-5 different blog articles
  - [ ] 6.2 Listen to generated audio for quality issues
  - [ ] 6.3 Adjust text cleaning if needed
  - [ ] 6.4 Document usage in README.md

---

## Files to Create

- `Gemfile` - Ruby dependencies
- `.env` - API keys (gitignored)
- `.gitignore` - Ignore sensitive and generated files
- `lib/text_processor.rb` - Markdown to text conversion (regex-based)
- `lib/tts.rb` - TTS API integration
- `generate.rb` - Main entry point script
- `README.md` - Usage documentation
- `input/` - Directory for markdown files
- `output/` - Directory for generated MP3s (gitignored)

---

## Implementation Decisions

1. **TTS Provider**: ✅ Google Cloud TTS with Gemini 2.5 Pro TTS model
   - Voice: Charon (male voice)
   - Speaking rate: 1.5x
   - Model: gemini-2.5-pro-preview-tts
2. **Text Cleaning**: ✅ Implemented
   - URLs/links: Extract and keep link text only
   - Code blocks: Remove entirely
   - Markdown headings: Strip # symbols
   - Bold/italic: Remove formatting, keep text
3. **Long Articles**: ✅ Automatic chunking at 5000 character limit with sentence boundary splitting

---

## Success Criteria

- ✅ Run: `ruby generate.rb input/article.md`
- ✅ Output: `output/article.mp3` that plays the article content in clear audio
- ✅ MVP Complete - Working end-to-end pipeline

**Current Status**: MVP is functional! Successfully converting markdown to MP3 using Gemini 2.5 Pro TTS.

---

## Future Enhancements (Out of Scope for MVP)

- Batch processing multiple markdown files
- RSS podcast feed generation
- Direct URL to article extraction
- Multiple TTS provider support
- Web interface
- Audio quality settings (speed, pitch, voice selection)
