# Paste Text Episode Input

## Overview

Add a third input option "Paste Text" to the episode creation form, alongside the existing "From URL" and "Upload File" options. Users paste raw text, and the system extracts metadata (title, author, description) via LLM - following the same async pattern as URL episodes.

## Data Model

**Episodes table changes:**
- Add `source_text` text column to store pasted content
- Add `:paste` to `source_type` enum

The `source_text` column mirrors how URL episodes store `source_url`. Content can be cleaned up after processing in a future optimization.

## Backend Services

### CreatePasteEpisode

Mirrors `CreateUrlEpisode`:
- Validates text is present and meets minimum length (100 characters)
- Creates episode with `source_type: :paste`, placeholder metadata ("Processing...")
- Stores pasted text in `source_text`
- Enqueues `ProcessPasteEpisodeJob`
- Returns Result object (success/failure)

### ProcessPasteEpisodeJob

Simple job that calls `ProcessPasteEpisode` service, matching the pattern of `ProcessUrlEpisodeJob`.

### ProcessPasteEpisode

Simpler than `ProcessUrlEpisode` - skips URL fetching and article extraction:
1. Check character limit via `MaxCharactersForUser`
2. Call `LlmProcessor` with the pasted text to extract title/author/description
3. Update episode metadata
4. Call `UploadAndEnqueueEpisode` to upload content and enqueue for TTS

Reuses existing error handling pattern with `fail_episode`.

## Frontend Changes

### Form (new.html.erb)

Add third tab to segmented control:
- "From URL" | "Upload File" | "Paste Text"

Add third panel containing:
- `<textarea>` with placeholder text explaining what to paste
- Helper text (e.g., "Paste article text. We'll extract the title and author automatically.")
- Same submit/cancel buttons as other forms

### Controller Routing

The textarea submits as `params[:text]`. Controller routes:
- `params[:url].present?` → `create_from_url`
- `params[:text].present?` → `create_from_paste`
- Otherwise → `create_from_markdown` (file upload)

### Stimulus

Existing `tab-switch` controller handles the third tab without modification.

## Validation & Error Handling

**Sync validation (before job):**
- Empty text → Flash error, re-render form
- Text under 100 characters → Flash error, re-render form

**Async errors (in job):**
- Character limit exceeded → Episode marked `failed` with error message
- LLM processing fails → Episode marked `failed` with error message

No new error handling patterns - reuses existing `fail_episode` flow.

## Files to Create

- `hub/app/services/create_paste_episode.rb`
- `hub/app/services/process_paste_episode.rb`
- `hub/app/jobs/process_paste_episode_job.rb`
- `hub/test/services/create_paste_episode_test.rb`
- `hub/test/services/process_paste_episode_test.rb`
- `hub/test/jobs/process_paste_episode_job_test.rb`
- Database migration for `source_text` column and enum update

## Files to Modify

- `hub/app/controllers/episodes_controller.rb` - add `create_from_paste` method
- `hub/app/views/episodes/new.html.erb` - add third tab and panel
- `hub/app/models/episode.rb` - add `:paste` to enum (if not auto-handled)
- `hub/test/controllers/episodes_controller_test.rb` - add tests for paste flow

## Reused Components

- `LlmProcessor` - extracts title/author/description from text
- `UploadAndEnqueueEpisode` - uploads content, enqueues TTS job
- `MaxCharactersForUser` - enforces tier-based character limits
- `tab-switch` Stimulus controller - handles tab UI
- `EpisodeLogging` concern - consistent logging
- Result object pattern - consistent service return values
