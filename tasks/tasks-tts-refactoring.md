# Tasks for TTS Library Refactoring

## Overview
This document tracks the refactoring of `/Users/jesse/code/tts/lib/tts.rb` to improve maintainability, testability, and configurability while maintaining 100% backward compatibility.

---

## Task 1.0: Create TTS::Config class with all configuration options ✅

**Priority:** HIGH
**Estimated Time:** 45-60 minutes
**Status:** COMPLETED

### Sub-tasks:

- [x] 1.1 Create new file `lib/tts/config.rb`
  - Create the `TTS` module if not already present
  - Define `TTS::Config` class
  - Add `require_relative 'tts/config'` to `lib/tts.rb`

- [x] 1.2 Add configuration attributes with defaults
  - Add `attr_accessor :voice_name` (default: "en-GB-Chirp3-HD-Enceladus")
  - Add `attr_accessor :language_code` (default: "en-GB")
  - Add `attr_accessor :speaking_rate` (default: 1.5)
  - Add `attr_accessor :pitch` (default: 0.0)
  - Add `attr_accessor :audio_encoding` (default: "MP3")
  - Add `attr_accessor :timeout` (default: 300)
  - Add `attr_accessor :max_retries` (default: 3)
  - Add `attr_accessor :thread_pool_size` (default: 10)
  - Add `attr_accessor :byte_limit` (default: 850)

- [x] 1.3 Implement initialize method
  - Accept optional hash of configuration overrides
  - Set all attributes to their default values
  - Apply any overrides passed in the hash
  - Example: `config = TTS::Config.new(speaking_rate: 2.0, thread_pool_size: 5)`

- [x] 1.4 Add validation (optional but recommended)
  - Validate `speaking_rate` is between 0.25 and 4.0 (Google TTS limits)
  - Validate `pitch` is between -20.0 and 20.0 (Google TTS limits)
  - Validate `thread_pool_size` is positive integer
  - Validate `byte_limit` is positive integer
  - Validate `max_retries` is non-negative integer

- [x] 1.5 Add class-level documentation
  - Document each configuration option
  - Include usage examples
  - Document validation ranges

### Relevant Files:
- **CREATED:** `/Users/jesse/code/tts/lib/tts/config.rb` - Configuration class with 9 attributes, validation, and documentation
- **CREATED:** `/Users/jesse/code/tts/test/test_config.rb` - 17 unit tests for TTS::Config
- **MODIFIED:** `/Users/jesse/code/tts/lib/tts.rb` - Added require_relative for config

### Testing:
```bash
# Create test file: test/tts/config_test.rb
ruby test/tts/config_test.rb

# Test cases to cover:
# - Default configuration values
# - Custom configuration overrides
# - Validation of invalid values
# - Configuration immutability after creation
```

### Backward Compatibility Notes:
- This task adds new code only, doesn't modify existing behavior
- No breaking changes expected

---

## Task 2.0: Implement logger abstraction to replace puts statements

**Priority:** HIGH
**Estimated Time:** 30-45 minutes

**Note:** Use Ruby's standard library `Logger` class (not a custom solution or third-party gem).

### Sub-tasks:

- [x] 2.1 Add logger dependency and attribute
  - Add `require 'logger'` to `lib/tts.rb` (Ruby standard library)
  - Add `@logger` instance variable to TTS class
  - Accept optional `logger:` parameter in `initialize` method
  - Default to `Logger.new($stdout)` if not provided (standard Ruby Logger)
  - Example: `def initialize(provider:, config: nil, logger: Logger.new($stdout))`

- [x] 2.2 Replace puts in `synthesize_google` method (lines 44, 63, 66)
  - Line 44: Replace `puts` with `@logger.info`
  - Line 63: Replace `puts` with `@logger.info`
  - Line 66: Replace `puts` with `@logger.error`

- [x] 2.3 Replace puts in `synthesize_google_chunked` method (lines 73-76, 87, 95, 98, 101, 113-114, 132-133, 136-138)
  - Lines 73-76: Replace `puts` with `@logger.info` (4 statements)
  - Line 87: Replace `puts` with `@logger.info`
  - Line 95: Replace `puts` with `@logger.info`
  - Line 98: Replace `puts` with `@logger.warn`
  - Line 101: Replace `puts` with `@logger.error`
  - Lines 113-114: Replace `puts` with `@logger.info` (2 statements)
  - Line 133: Replace `puts` with `@logger.warn`
  - Lines 136-138: Replace `puts` with `@logger.info` (3 statements)

- [x] 2.4 Replace puts in `synthesize_google_with_retry` method (lines 152, 162)
  - Line 152: Replace `puts` with `@logger.warn`
  - Line 162: Replace `puts` with `@logger.warn`

- [x] 2.5 Set appropriate log levels
  - INFO: Normal operation messages (API calls, progress)
  - WARN: Retries, skipped chunks, content filtering
  - ERROR: Failed operations, exceptions

- [x] 2.6 Test silent mode - SKIPPED (not needed per user request)
  - Verify `TTS.new(provider: :google, logger: Logger.new(File::NULL))` produces no output
  - Verify functionality still works correctly

### Relevant Files:
- **MODIFY:** `/Users/jesse/code/tts/lib/tts.rb` (all puts statements)

### Testing:
```bash
# Manual test with default Ruby Logger (outputs to STDOUT)
ruby -e "require_relative 'lib/tts'; tts = TTS.new(provider: :google); tts.synthesize('test')"

# Manual test with silent Ruby Logger
ruby -e "require 'logger'; require_relative 'lib/tts'; tts = TTS.new(provider: :google, logger: Logger.new(File::NULL)); tts.synthesize('test')"

# Manual test with Ruby Logger writing to file
ruby -e "require 'logger'; require_relative 'lib/tts'; logger = Logger.new('tts.log'); tts = TTS.new(provider: :google, logger: logger); tts.synthesize('test')"

# Manual test with Ruby Logger at different severity level
ruby -e "require 'logger'; require_relative 'lib/tts'; logger = Logger.new($stdout); logger.level = Logger::WARN; tts = TTS.new(provider: :google, logger: logger); tts.synthesize('test')"
```

### Backward Compatibility Notes:
- Default Ruby Logger outputs to STDOUT, maintaining same visible behavior
- Output format will differ: Ruby's Logger adds severity level, timestamp, and process ID
  - Old: `Making API call (838 bytes)...`
  - New: `I, [2025-01-15T10:30:45.123456 #12345]  INFO -- : Making API call (838 bytes)...`
- Users can customize format with Logger formatter if needed:
  ```ruby
  logger = Logger.new($stdout)
  logger.formatter = proc { |severity, datetime, progname, msg| "#{msg}\n" }
  ```

---

## Task 3.0: Update configuration usage throughout TTS class

**Priority:** HIGH
**Estimated Time:** 45-60 minutes

### Sub-tasks:

- [ ] 3.1 Update TTS#initialize to accept config parameter
  - Add optional `config:` keyword parameter
  - Default to `TTS::Config.new` if not provided
  - Store config in `@config` instance variable
  - Example: `def initialize(provider:, config: nil, logger: nil)`

- [ ] 3.2 Update Google client initialization to use config.timeout (line 13)
  - Change `config.timeout = 300` to `config.timeout = @config.timeout`
  - Note: This is Google Cloud client config, not TTS::Config

- [ ] 3.3 Update synthesize_google to use config values
  - Line 38: Change default voice to use `@config.voice_name`
  - Line 48: Change `language_code:` to use `@config.language_code`
  - Line 52: Change `audio_encoding:` to use `@config.audio_encoding`
  - Line 53: Change `speaking_rate:` to use `@config.speaking_rate`
  - Line 54: Change `pitch:` to use `@config.pitch`

- [ ] 3.4 Update chunk_text calls to use config.byte_limit
  - Line 40: Change `GOOGLE_BYTE_LIMIT` to `@config.byte_limit`
  - Line 71: Change `GOOGLE_BYTE_LIMIT` to `@config.byte_limit`

- [ ] 3.5 Update thread pool initialization to use config.thread_pool_size
  - Line 79: Change `Concurrent::FixedThreadPool.new(10)` to `Concurrent::FixedThreadPool.new(@config.thread_pool_size)`
  - Line 74: Update log message to use `@config.thread_pool_size` instead of hardcoded "10"

- [ ] 3.6 Update retry logic to use config.max_retries
  - Line 93: Change method parameter to use default from config: `max_retries: @config.max_retries`
  - Or remove parameter and always use `@config.max_retries`

- [ ] 3.7 Keep GOOGLE_BYTE_LIMIT constant for reference
  - Add comment: "# Default Google TTS byte limit - can be overridden via config"
  - This allows users to reference the default if needed

### Relevant Files:
- **MODIFY:** `/Users/jesse/code/tts/lib/tts.rb` (multiple locations)

### Testing:
```bash
# Test with default config
ruby -e "require_relative 'lib/tts'; tts = TTS.new(provider: :google); puts tts.synthesize('test').bytesize"

# Test with custom config
ruby -e "require_relative 'lib/tts'; config = TTS::Config.new(speaking_rate: 2.0); tts = TTS.new(provider: :google, config: config); puts tts.synthesize('test').bytesize"

# Test thread pool customization (with long text)
ruby -e "require_relative 'lib/tts'; config = TTS::Config.new(thread_pool_size: 3); tts = TTS.new(provider: :google, config: config); tts.synthesize('a' * 5000)"
```

### Backward Compatibility Notes:
- Default config values match current hardcoded values exactly
- `TTS.new(provider: :google)` continues to work with same behavior
- Voice parameter in `synthesize(text, voice:)` still overrides config default

---

## Task 4.0: Extract magic strings to constants

**Priority:** MEDIUM
**Estimated Time:** 15-20 minutes

### Sub-tasks:

- [ ] 4.1 Extract content filter error message to constant
  - Add constant: `CONTENT_FILTER_ERROR = "sensitive or harmful content"`
  - Replace line 97: `e.message.include?("sensitive or harmful content")` with `e.message.include?(CONTENT_FILTER_ERROR)`
  - Add comment explaining this is Google's content safety filter

- [ ] 4.2 Extract error message for deadline exceeded
  - Add constant: `DEADLINE_EXCEEDED_ERROR = "Deadline Exceeded"`
  - Replace line 160: `e.message.include?("Deadline Exceeded")` with `e.message.include?(DEADLINE_EXCEEDED_ERROR)`

- [ ] 4.3 Review for other magic strings
  - Check error messages in NotImplementedError and ArgumentError
  - Consider extracting if they appear multiple times
  - Document decision to keep or extract

- [ ] 4.4 Group constants logically
  - Place constants at top of class after GOOGLE_BYTE_LIMIT
  - Add comment sections: "# Byte limits", "# Error messages"
  - Keep related constants together

### Relevant Files:
- **MODIFY:** `/Users/jesse/code/tts/lib/tts.rb` (add constants and update references)

### Testing:
```bash
# Test content filter detection still works
# This requires triggering Google's content filter (difficult to test)
# Focus on code review and ensure constant usage is correct

# Verify constants are defined
ruby -e "require_relative 'lib/tts'; puts TTS::CONTENT_FILTER_ERROR"
```

### Backward Compatibility Notes:
- No public API changes
- Internal refactoring only
- No impact on existing users

---

## Task 5.0: Update documentation and comments

**Priority:** MEDIUM
**Estimated Time:** 30-45 minutes

### Sub-tasks:

- [ ] 5.1 Update outdated comment on line 5
  - Change: `# Gemini TTS limit for text field`
  - To: `# Chirp3/Google TTS text field limit (bytes)`
  - Explain this is a byte limit, not character limit

- [ ] 5.2 Update outdated comment on line 13
  - Change: `# 5 minutes - Gemini TTS can take this long`
  - To: `# 5 minutes - Chirp3/Google TTS operations can take this long for large texts`
  - Make it clear this applies to all TTS operations

- [ ] 5.3 Add class-level documentation to TTS class
  - Add overview of what the class does
  - Document supported providers
  - Show basic usage example
  - Show configuration example
  - Show logger customization example

- [ ] 5.4 Document the Config class (in lib/tts/config.rb)
  - Add class description
  - Document each attribute with type and default
  - Include usage examples
  - Document validation ranges

- [ ] 5.5 Update method-level documentation
  - Review all public methods for accuracy
  - Ensure parameter types are documented
  - Ensure return types are documented
  - Add examples where helpful

- [ ] 5.6 Add documentation for error handling
  - Document which exceptions can be raised
  - Explain retry behavior
  - Explain content filtering behavior
  - Document chunk skipping behavior

### Relevant Files:
- **MODIFY:** `/Users/jesse/code/tts/lib/tts.rb` (comments and docs)
- **MODIFY:** `/Users/jesse/code/tts/lib/tts/config.rb` (comments and docs)

### Testing:
```bash
# Verify documentation is readable
# No automated tests needed, manual review

# Generate RDoc or YARD documentation if project uses it
yard doc lib/tts.rb lib/tts/config.rb
# or
rdoc lib/tts.rb lib/tts/config.rb
```

### Backward Compatibility Notes:
- Documentation only, no code changes
- No impact on functionality

---

## Task 6.0: Ensure backward compatibility

**Priority:** CRITICAL
**Estimated Time:** 30-45 minutes

### Sub-tasks:

- [ ] 6.1 Verify default behavior is unchanged
  - Test `TTS.new(provider: :google)` works without config parameter
  - Verify default voice is "en-GB-Chirp3-HD-Enceladus"
  - Verify default speaking rate is 1.5
  - Verify default thread pool size is 10
  - Verify output logs to STDOUT by default

- [ ] 6.2 Verify voice parameter override still works
  - Test `tts.synthesize(text, voice: "custom-voice")` overrides default
  - Verify config.voice_name is used as fallback when voice: is nil
  - Ensure voice parameter takes precedence over config

- [ ] 6.3 Test with existing code patterns
  - Create test script with pre-refactor usage patterns
  - Verify no errors or behavior changes
  - Test short text (under byte limit)
  - Test long text (requiring chunking)
  - Test concurrent processing

- [ ] 6.4 Verify all constants are still accessible
  - Ensure `TTS::GOOGLE_BYTE_LIMIT` is still public
  - Verify new constants don't conflict with existing code

- [ ] 6.5 Check for any breaking changes in error handling
  - Verify same exceptions are raised
  - Verify retry behavior is identical
  - Verify content filtering still skips chunks

- [ ] 6.6 Document migration path for advanced users
  - Create examples showing new configuration options
  - Show how to use custom logger
  - Explain benefits of explicit configuration

### Relevant Files:
- **CREATE:** `/Users/jesse/code/tts/test/backward_compatibility_test.rb`
- **ALL FILES:** Review all changes

### Testing:
```bash
# Run backward compatibility tests
ruby test/backward_compatibility_test.rb

# Test with real Google TTS API (requires credentials)
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/credentials.json
ruby -e "require_relative 'lib/tts'; tts = TTS.new(provider: :google); File.write('output.mp3', tts.synthesize('Hello world'))"

# Verify output file is valid MP3
file output.mp3  # Should show: "MPEG ADTS, layer III"
```

### Backward Compatibility Notes:
- This entire task is about ensuring compatibility
- Zero breaking changes allowed
- All existing code must work identically

---

## Task 7.0: Add comprehensive tests for new configuration and logging

**Priority:** HIGH
**Estimated Time:** 60-90 minutes

### Sub-tasks:

- [ ] 7.1 Set up test infrastructure
  - Create `test/` directory if it doesn't exist
  - Create `test/test_helper.rb` with common setup
  - Add minitest or rspec dependency (if not already present)
  - Create `.env.test` for test configuration

- [ ] 7.2 Write tests for TTS::Config
  - Test default values for all attributes
  - Test custom initialization with hash
  - Test attribute setters work correctly
  - Test validation (if implemented)
  - Test edge cases (nil values, invalid types)
  - **File:** `test/tts/config_test.rb`

- [ ] 7.3 Write tests for logger integration
  - Test default logger outputs to STDOUT
  - Test custom logger receives log messages
  - Test silent logger (Logger.new(File::NULL))
  - Test log levels are appropriate (info, warn, error)
  - Mock TTS operations to avoid hitting Google API
  - **File:** `test/tts/logger_test.rb`

- [ ] 7.4 Write tests for configuration usage
  - Test custom speaking_rate affects synthesis
  - Test custom thread_pool_size is used
  - Test custom byte_limit affects chunking
  - Test custom max_retries affects retry logic
  - Mock Google API calls for these tests
  - **File:** `test/tts/configuration_usage_test.rb`

- [ ] 7.5 Write backward compatibility tests
  - Test `TTS.new(provider: :google)` works without config
  - Test voice parameter override
  - Test default behavior matches pre-refactor
  - **File:** `test/tts/backward_compatibility_test.rb`

- [ ] 7.6 Write integration tests (optional, requires API access)
  - Test actual Google TTS API calls
  - Test chunking with real long text
  - Test retry behavior with rate limiting
  - Skip these tests in CI without credentials
  - **File:** `test/tts/integration_test.rb`

- [ ] 7.7 Set up test runner
  - Create `Rakefile` with test task
  - Or create `test/run_all.rb` to run all tests
  - Document how to run tests in README

### Relevant Files:
- **CREATE:** `/Users/jesse/code/tts/test/test_helper.rb`
- **CREATE:** `/Users/jesse/code/tts/test/tts/config_test.rb`
- **CREATE:** `/Users/jesse/code/tts/test/tts/logger_test.rb`
- **CREATE:** `/Users/jesse/code/tts/test/tts/configuration_usage_test.rb`
- **CREATE:** `/Users/jesse/code/tts/test/tts/backward_compatibility_test.rb`
- **CREATE:** `/Users/jesse/code/tts/test/tts/integration_test.rb` (optional)
- **CREATE:** `/Users/jesse/code/tts/Rakefile` or `/Users/jesse/code/tts/test/run_all.rb`

### Testing:
```bash
# Run all unit tests (no API calls)
rake test
# or
ruby test/run_all.rb

# Run integration tests (requires Google credentials)
GOOGLE_APPLICATION_CREDENTIALS=/path/to/creds.json rake test:integration

# Run specific test file
ruby test/tts/config_test.rb

# Run with coverage (if using simplecov)
COVERAGE=true rake test
```

### Backward Compatibility Notes:
- Tests verify backward compatibility
- Tests should pass with both old and new code
- Mock external dependencies to avoid API calls in unit tests

---

## Summary

### Total Estimated Time
**5-7 hours** for a junior developer completing all tasks

### Critical Path
1. Task 1.0 (Config class) - Foundation for everything
2. Task 3.0 (Config usage) - Integrate config into TTS class
3. Task 2.0 (Logger) - Replace puts statements
4. Task 6.0 (Backward compatibility) - Verify nothing broke

### Files to Create
- `/Users/jesse/code/tts/lib/tts/config.rb`
- `/Users/jesse/code/tts/test/test_helper.rb`
- `/Users/jesse/code/tts/test/tts/config_test.rb`
- `/Users/jesse/code/tts/test/tts/logger_test.rb`
- `/Users/jesse/code/tts/test/tts/configuration_usage_test.rb`
- `/Users/jesse/code/tts/test/tts/backward_compatibility_test.rb`
- `/Users/jesse/code/tts/test/tts/integration_test.rb` (optional)
- `/Users/jesse/code/tts/Rakefile` or `/Users/jesse/code/tts/test/run_all.rb`

### Files to Modify
- `/Users/jesse/code/tts/lib/tts.rb` (main refactoring)

### Key Backward Compatibility Requirements
1. `TTS.new(provider: :google)` must work without changes
2. Default configuration must match current hardcoded values exactly
3. Voice parameter override must continue to work
4. Default logger must output to STDOUT
5. All existing tests must pass (if any exist)
6. Same exceptions and error handling behavior

### Testing Strategy
1. Unit tests for Config class (no external dependencies)
2. Unit tests for logger integration (mocked TTS operations)
3. Unit tests for configuration usage (mocked Google API)
4. Backward compatibility tests (verify old code works)
5. Integration tests (optional, requires Google credentials)

### Success Criteria Checklist
- [ ] All configuration is centralized in `TTS::Config`
- [ ] No `puts` statements remain (replaced with logger)
- [ ] All comments are accurate and up-to-date
- [ ] No magic strings in conditional logic
- [ ] Thread pool size is configurable
- [ ] Existing functionality works identically
- [ ] New tests demonstrate configurability
- [ ] All tests pass
