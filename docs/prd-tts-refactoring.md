# PRD: TTS Library Refactoring

## Overview
Refactor the `lib/tts.rb` file to improve maintainability, testability, and configurability while maintaining backward compatibility with existing functionality.

## Goals
- Make configuration explicit and overridable
- Improve testability by removing hardcoded dependencies
- Update outdated documentation and comments
- Prepare for future provider implementations

## Current State
The TTS library works correctly but has several maintainability issues:
- Configuration scattered throughout the code (voice, rate, threads, etc.)
- Logging mixed with business logic using `puts`
- Hardcoded magic strings
- Outdated comments referencing Gemini instead of Chirp3
- No easy way to test without hitting real APIs

## Requirements

### 1. Configuration Management
**Priority: HIGH**

- Extract all configuration into a `TTS::Config` class
- Configuration should include:
  - Voice name (default: "en-GB-Chirp3-HD-Enceladus")
  - Language code (default: "en-GB")
  - Speaking rate (default: 1.5)
  - Pitch (default: 0.0)
  - Audio encoding (default: "MP3")
  - Timeout (default: 300)
  - Max retries (default: 3)
  - Thread pool size (default: 10)
  - Byte limit (default: 850)

- Allow users to override configuration:
  ```ruby
  config = TTS::Config.new
  config.speaking_rate = 2.0
  config.thread_pool_size = 5

  tts = TTS.new(provider: :google, config: config)
  ```

### 2. Logging Abstraction
**Priority: HIGH**

- Replace all `puts` statements with proper logging
- Support logger injection for testability
- Default to STDOUT logger for backward compatibility
- Allow silent mode for testing:
  ```ruby
  tts = TTS.new(provider: :google, logger: Logger.new(File::NULL))
  ```

### 3. Documentation Updates
**Priority: MEDIUM**

- Update comment on line 5: "Gemini TTS limit" → "Chirp3/Google TTS text field limit"
- Update comment on line 13: Make it clear this timeout applies to all TTS operations, not just Gemini
- Add class-level documentation explaining usage
- Document the Config class and all its options

### 4. Extract Magic Strings
**Priority: MEDIUM**

- Extract "sensitive or harmful content" to named constant
- Any other magic strings should be constants

### 5. Thread Pool Configuration
**Priority: MEDIUM**

- Thread pool size should come from config, not hardcoded
- Update the logging message to reflect actual thread count from config

### 6. Backward Compatibility
**Priority: CRITICAL**

- Existing code using `TTS.new(provider: :google)` must continue to work
- Default configuration should match current behavior exactly
- All existing tests should pass without modification

## Non-Goals

- Provider pattern refactoring (defer until adding new providers)
- Refactoring `chunk_text` method (works fine, low priority)
- Voice/language coupling improvements (nice-to-have, not essential)
- Advanced error handling strategies (current approach works)

## Success Criteria

1. All configuration is centralized in `TTS::Config`
2. No `puts` statements remain (replaced with logger)
3. All comments are accurate and up-to-date
4. No magic strings in conditional logic
5. Thread pool size is configurable
6. Existing functionality works identically
7. New tests demonstrate configurability
8. Code passes existing test suite (if one exists)

## Testing Requirements

- Unit tests for `TTS::Config` class
- Tests demonstrating custom configuration
- Tests demonstrating logger injection
- Tests for backward compatibility
- Mock tests that don't hit real Google APIs

## Timeline

This is a refactoring effort, so it should be low-risk and incrementally testable.

Estimated: 2-4 hours for a junior developer

## Future Considerations

After this refactoring:
- Provider pattern will be easier to implement
- Adding OpenAI/ElevenLabs providers will be straightforward
- Testing will be much easier
- Users can customize behavior without code changes
