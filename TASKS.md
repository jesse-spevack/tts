# Tasks for Text-to-Speech MVP

## Goal
Build a Ruby script that converts markdown files to MP3 audio files using a TTS API.

**Scope**: Markdown → Plain Text → TTS → MP3

---

## Tasks

- [ ] 1.0 Project Setup
  - [ ] 1.1 Create project directory structure (input/, output/, lib/, test/)
  - [ ] 1.2 Initialize Gemfile with required gems
  - [ ] 1.3 Run bundle install
  - [ ] 1.4 Create .env file for API keys
  - [ ] 1.5 Create .gitignore (ignore .env, output/, input/)
  - [ ] 1.6 Add minitest gem 

- [ ] 2.0 Text Processing Module
  - [ ] 2.1 Create lib/text_processor.rb
    ```ruby
        file = File.open(path)
        text = TextProcessor.markdown_to_text(file)
        # text processor errors if file is not markdown
        # otherwise text processor returns clean text ideal for tts API call
    ```
  - [ ] 2.2 Implement markdown file reading
  - [ ] 2.3 Implement regex-based markdown to plain text conversion
  - [ ] 2.4 Handle: headers, bold, italic, links, code blocks, lists, images
  - [ ] 2.5 Write unit tests for common markdown to text cases

### STOP HERE

- [ ] 3.0 TTS Provider Selection and Integration
  - [ ] 3.0.1 Research Google, OpenAI, ElevenLabs integration docs
    - for each provider, create a step by step markdown integration guide including everything you will need me to do:
        - How to get necessary API credentials
        - Simple TTS cURL example to demonstrate interface
        - Notes on authentication scheme to
  - [ ] 3.2 Add each TTS provider gem to Gemfile
  - [ ] 3.3 Set up API credentials in .env
  - [ ] 3.4 Create lib/tts.rb module
    ```ruby
        tts = TTS.new(provider: :google | :open_ai | :eleven_labs)
    ```
  - [ ] 3.5 Implement basic TTS API call
  - [ ] 3.6 Handle text chunking if needed (API character limits)
  - [ ] 3.7 Test with short text sample

- [ ] 4.0 Audio File Generation
  - [ ] 4.1 Implement audio content saving to MP3 file
  - [ ] 4.2 Generate filename from markdown title/filename
  - [ ] 4.3 Save to output/ directory
  - [ ] 4.4 Test generated MP3 plays correctly

- [ ] 5.0 Main Script Integration
  - [ ] 5.1 Create generate.rb main script
  - [ ] 5.2 Add command-line argument parsing (input file path tts provider)
  - [ ] 5.3 Wire together: read MD → process text → generate audio → save MP3
  - [ ] 5.4 Add progress output/logging
  - [ ] 5.5 Add error handling for missing files, API failures
  - [ ] 5.6 Test end-to-end with real blog article

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

## Open Decisions

1. **TTS Provider**: Need to pick one to start (Google Cloud TTS, OpenAI, or ElevenLabs)
    - Start with Google Cloud TTS
2. **Text Cleaning**: How to handle:
   - URLs/links (just keep link text for now)
   - Code blocks (remove them)
   - Markdown headings (strip # symbols)
3. **Long Articles**: Strategy for articles exceeding TTS character limits

---

## Success Criteria

- Run: `ruby generate.rb input/article.md`
- Output: `output/article.mp3` that plays the article content in clear audio
- Time to first working MP3: 2-3 hours

---

## Future Enhancements (Out of Scope for MVP)

- Batch processing multiple markdown files
- RSS podcast feed generation
- Direct URL to article extraction
- Multiple TTS provider support
- Web interface
- Audio quality settings (speed, pitch, voice selection)
