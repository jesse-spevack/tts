# Junior Developer Tasks

Each task below is a standalone prompt you can assign. Copy and paste the prompt to your junior developer.

---

## Task 1: Add frozen_string_literal to lib files

**Prompt:**
```
Create a new branch called `chore/frozen-string-literal-lib` and add the comment `# frozen_string_literal: true` as the first line to these 12 files in the lib/ directory:

- lib/cloud_tasks_enqueuer.rb
- lib/episode_manifest.rb
- lib/episode_processor.rb
- lib/filename_generator.rb
- lib/firestore_client.rb
- lib/gcs_uploader.rb
- lib/metadata_extractor.rb
- lib/podcast_publisher.rb
- lib/publish_params_validator.rb
- lib/rss_generator.rb
- lib/text_converter.rb
- lib/text_processor.rb

After adding the comment to all files, run `rake test` to ensure all tests pass, then create a PR with title "chore: add frozen_string_literal to lib files".
```

---

## Task 2: Add frozen_string_literal to root files

**Prompt:**
```
Create a new branch called `chore/frozen-string-literal-root` and add the comment `# frozen_string_literal: true` as the first line to these 3 files in the root directory:

- api.rb
- generate.rb
- test_single_chunk.rb

After adding the comment to all files, run `rake test` to ensure all tests pass, then create a PR with title "chore: add frozen_string_literal to root files".
```

---

## Task 3: Clean up test_single_chunk.rb

**Prompt:**
```
Create a new branch called `chore/cleanup-test-script`.

Investigate the file `test_single_chunk.rb` in the root directory. Determine if it's:
- Still useful (if so, move it to the test/ directory with a proper name)
- A utility script (if so, move it to bin/ and add documentation at the top)
- Obsolete (if so, delete it)

Make your decision and implement it. Run `rake test` to ensure tests still pass, then create a PR with title "chore: clean up test_single_chunk.rb" and explain your decision in the PR description.
```

---

## Task 4: Extract hardcoded test data to constants

**Prompt:**
```
Create a new branch called `refactor/test-constants`.

In the file `test/test_api.rb`, extract the hardcoded values in the setup method to constants at the top of the test file. For example:

```ruby
# At top of file after requires
TEST_API_TOKEN = "test-token-123"
TEST_PROJECT = "test-project"
TEST_BUCKET = "test-bucket"
TEST_SERVICE_URL = "http://localhost:8080"

# Then in setup method:
def setup
  ENV["API_SECRET_TOKEN"] = TEST_API_TOKEN
  ENV["GOOGLE_CLOUD_PROJECT"] = TEST_PROJECT
  # ... etc
end
```

Run `rake test` to ensure all tests pass, then create a PR with title "refactor: extract test constants in test_api.rb".
```

---

## Task 5: Write tests for PublishParamsValidator

**Prompt:**
```
Create a new branch called `test/publish-params-validator`.

The class `PublishParamsValidator` in `lib/publish_params_validator.rb` has no test file. Create a new test file `test/test_publish_params_validator.rb` following the patterns in existing test files. Reference `test/CLAUDE.md` for testing guidelines.

Your tests should cover:
- Valid parameters pass validation
- Missing required fields are caught (podcast_id, title, content_file)
- Empty content file is caught
- Invalid content_file formats are rejected

Run `rake test` to ensure all tests pass, then create a PR with title "test: add comprehensive tests for PublishParamsValidator".
```

---

## Task 6: Extract duplicate format_size method

**Prompt:**
```
Create a new branch called `refactor/extract-format-size`.

The `format_size` method is duplicated in both `lib/tts.rb` (lines 80-88) and `lib/episode_processor.rb` (lines 78-86).

1. Create a new file `lib/format_helpers.rb`
2. Extract the method into a module:
```ruby
# frozen_string_literal: true

module FormatHelpers
  def self.format_size(bytes)
    # ... implementation
  end
end
```
3. Replace both occurrences with `FormatHelpers.format_size(bytes)`
4. Update any tests that mock this method

Run `rake test` to ensure all tests pass, then create a PR with title "refactor: extract format_size to shared module".
```

---

## Task 7: Create constants file for magic numbers

**Prompt:**
```
Create a new branch called `refactor/extract-constants`.

Create a new file `lib/constants.rb` with a Constants module containing:

```ruby
# frozen_string_literal: true

module Constants
  # File size thresholds
  BYTES_PER_KB = 1024
  BYTES_PER_MB = 1_048_576

  # TTS configuration
  DEFAULT_BYTE_LIMIT = 850

  # API configuration
  DEFAULT_PORT = 8080
end
```

Then find and replace all hardcoded instances of these numbers throughout the codebase:
- 1024 → Constants::BYTES_PER_KB
- 1_048_576 → Constants::BYTES_PER_MB
- 850 (byte limits) → Constants::DEFAULT_BYTE_LIMIT
- 8080 (port) → Constants::DEFAULT_PORT

Run `rake test` and `rake rubocop` to ensure everything passes, then create a PR with title "refactor: extract magic numbers to constants".
```

---

## Task 8: Add YARD documentation

**Prompt:**
```
Create a new branch called `docs/add-yard-documentation`.

Add comprehensive YARD documentation to these two files:

1. `lib/text_converter.rb` - Add module-level documentation explaining what this module does
2. `lib/publish_params_validator.rb` - Add class-level documentation and @param/@return tags

Follow the YARD documentation style used in other files like `lib/tts.rb` as examples. Include @example tags showing typical usage.

Run `rake test` to ensure tests pass, then create a PR with title "docs: add YARD documentation to TextConverter and PublishParamsValidator".
```

---

## Task 9: Add file size validation

**Prompt:**
```
Create a new branch called `feat/file-size-validation`.

In `lib/text_processor.rb`, add a new method to validate input file size:

```ruby
MAX_FILE_SIZE_MB = 10

def self.validate_file_size(file)
  size = File.size(file)
  max_bytes = MAX_FILE_SIZE_MB * 1_048_576

  if size > max_bytes
    raise InvalidFileError,
          "File too large: #{format_size(size)}. Maximum: #{MAX_FILE_SIZE_MB} MB"
  end
end
```

Call this method at the start of `process_file` before processing begins. Add tests in `test/test_text_processor.rb` to verify:
- Files under 10MB are accepted
- Files over 10MB raise InvalidFileError with clear message

Run `rake test` to ensure tests pass, then create a PR with title "feat: add file size validation (max 10MB)".
```

---

## Task 10: Improve error handling in episode_manifest.rb

**Prompt:**
```
Create a new branch called `refactor/episode-manifest-errors`.

In `lib/episode_manifest.rb`, the `load` method (lines 17-24) catches all StandardError without distinguishing between different failure types.

Refactor it to:
1. Catch specific error types separately (file not found vs JSON parse error)
2. Add logging for unexpected errors using `warn`
3. Only silently default to empty array for "file doesn't exist" (expected case)

Update or add tests in `test/test_episode_manifest.rb` to verify the new error handling behavior.

Run `rake test` to ensure tests pass, then create a PR with title "refactor: improve error handling in EpisodeManifest#load".
```

---

## Task 11: Write tests for CloudTasksEnqueuer

**Prompt:**
```
Create a new branch called `test/cloud-tasks-enqueuer`.

The class `CloudTasksEnqueuer` in `lib/cloud_tasks_enqueuer.rb` has no test file. Create a new test file `test/test_cloud_tasks_enqueuer.rb` following patterns in existing test files.

Your tests should cover:
- Task creation with valid payload
- Queue path construction (project_id, location, queue_name)
- Service URL handling
- Authentication token generation

Since this integrates with Google Cloud, use mocks/stubs to avoid real API calls. Reference how other tests mock external services.

Run `rake test` to ensure all tests pass, then create a PR with title "test: add comprehensive tests for CloudTasksEnqueuer".
```

---

## Task 12: Create AppConfig singleton

**Prompt:**
```
Create a new branch called `refactor/centralize-config`.

Environment variables are fetched with `ENV.fetch` in 14 different places across the codebase. Create a centralized configuration singleton:

1. Create `lib/app_config.rb`:
```ruby
# frozen_string_literal: true

class AppConfig
  class << self
    def google_cloud_project
      @google_cloud_project ||= ENV.fetch("GOOGLE_CLOUD_PROJECT")
    end

    def google_cloud_bucket
      @google_cloud_bucket ||= ENV.fetch("GOOGLE_CLOUD_BUCKET")
    end

    def service_url
      @service_url ||= ENV.fetch("SERVICE_URL", nil)
    end

    # Add other config methods...
  end
end
```

2. Replace all `ENV.fetch` calls in lib/, api.rb, and generate.rb with AppConfig methods
3. Update tests to stub AppConfig instead of ENV where appropriate

Run `rake test` to ensure tests pass, then create a PR with title "refactor: centralize environment variable access in AppConfig".
```

---

## Task 13: Refactor episode_processor print methods

**Prompt:**
```
Create a new branch called `refactor/episode-processor-printing`.

In `lib/episode_processor.rb`, the methods `print_start` (lines 88-93) and `print_success` (lines 95-100) have similar code.

Extract the common divider logic into a shared helper method:
```ruby
def print_divider(message = nil)
  puts "=" * 60
  puts message if message
  puts "Podcast ID: #{@podcast_id}"
  puts "=" * 60
end
```

Then simplify the existing methods to use this helper.

Run `rake test` to ensure tests pass, then create a PR with title "refactor: reduce duplication in EpisodeProcessor print methods".
```

---

## Task 14: Extract api.rb helper methods

**Prompt:**
```
Create a new branch called `refactor/extract-api-helpers`.

The file `api.rb` contains routing logic mixed with helper methods. Extract the helper methods into a new file `lib/api_helpers.rb`.

Methods to extract:
- `authenticate!` (lines ~10-15)
- `json_response` (if present)
- Any other private helper methods

Keep the routing thin in api.rb and delegate to the helpers module.

Run `rake test` to ensure all tests pass, then create a PR with title "refactor: extract api.rb helper methods to separate module".

**Note:** This is a larger refactor. Take your time and ensure all API tests still pass.
```

---

## Task 15: Add episode count to health check

**Prompt:**
```
Create a new branch called `feat/health-check-episode-count`.

Enhance the health check endpoint in `api.rb` to include the episode count in its JSON response.

Current response:
```json
{"status": "ok"}
```

New response:
```json
{"status": "ok", "episode_count": 42}
```

The health check should:
1. Load the manifest to get episode count
2. Handle missing manifest gracefully (return 0)
3. Not fail if there's an error (return null or 0)

Update `test/test_api.rb` to verify the new field is present in health check responses.

Run `rake test` to ensure tests pass, then create a PR with title "feat: add episode count to health check endpoint".
```

---

## General Instructions for All Tasks

When starting any task:
1. Pull latest from main: `git checkout main && git pull`
2. Create your branch: `git checkout -b <branch-name>`
3. Make your changes
4. Run the test suite: `rake test`
5. Run the linter: `rake rubocop`
6. Commit your changes with a clear message
7. Push your branch: `git push -u origin <branch-name>`
8. Create a PR on GitHub with the specified title

**Questions?** Check `docs/onboarding-guide.md` and `test/CLAUDE.md` for testing guidelines.
