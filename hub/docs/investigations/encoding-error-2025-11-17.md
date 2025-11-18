# Encoding Error Investigation - Episodes 15 & 18

## Date
2025-11-17

## Episodes Affected
- Episode 15: (no longer in database - was cleaned up)
- Episode 18: (no longer in database - was cleaned up)

## Error Message
```
incompatible character encodings: UTF-8 and BINARY (ASCII-8BIT)
```

## Findings

### Database Investigation
- Episodes 15 and 18 no longer exist in the database
- Only 2 episodes currently exist (IDs 1 and 2), both completed successfully
- No failed episodes currently in database
- Episodes were likely cleaned up after failing

### GCS Investigation
- No staging directory exists in gs://verynormal-tts-podcast/
- Bucket contains: feed.xml, manifest.json, /episodes, /podcasts
- Original episode files are no longer available for inspection

### Log Analysis
From GCP Cloud Run logs (podcast-api service):

**Error occurred at:** 2025-11-17 22:45:07

**Error details:**
```
event=process_error
error_class=Encoding::CompatibilityError
error_message="incompatible character encodings: UTF-8 and BINARY (ASCII-8BIT)"
```

**Backtrace location:**
```
/app/lib/tts/chunked_synthesizer.rb:98 in 'TTS::ChunkedSynthesizer#handle_chunk_error'
/app/lib/tts/chunked_synthesizer.rb:89 in 'TTS::ChunkedSynthesizer#synthesize_chunk_with_error_handling'
```

**Context:**
- Error occurred during chunk processing for episode 18
- Processing was at chunk 357/735 when failure notification was sent
- Hub was successfully notified of failure (status 200)

### Code Analysis

**Location:** `/lib/tts/chunked_synthesizer.rb:98`

**Problematic code:**
```ruby
def handle_chunk_error(error:, chunk_num:, total:, skipped_chunks:)
  if error.message.include?(CONTENT_FILTER_ERROR)
    @logger.warn "Chunk #{chunk_num}/#{total}: ⚠ SKIPPED - Content filter"
    skipped_chunks << chunk_num
  else
    @logger.error "Chunk #{chunk_num}/#{total}: ✗ Failed - #{error.message}"  # LINE 98
    raise
  end
end
```

**Root Cause:**
String interpolation on line 98 is combining:
- UTF-8 strings: `"Chunk #{chunk_num}/#{total}: ✗ Failed - "`
- `error.message` which may contain BINARY (ASCII-8BIT) encoding

When Ruby tries to interpolate a binary-encoded error message into a UTF-8 string literal, it raises `Encoding::CompatibilityError`.

This happens when:
1. An API error occurs with a message containing binary data
2. The error message has ASCII-8BIT encoding (common for errors from external APIs)
3. String interpolation attempts to mix UTF-8 and ASCII-8BIT encodings

## Hypothesis

The encoding error is a **secondary error** that occurs when trying to log a **primary error** from the TTS API. The actual issue is:

1. TTS API returns an error (possibly with binary content or non-UTF-8 encoding)
2. Error message has ASCII-8BIT encoding
3. When trying to log this error on line 98, string interpolation fails
4. The `Encoding::CompatibilityError` masks the original API error
5. Episodes get stuck in failed state because we never see the root cause

## Impact

**Critical:** This bug prevents debugging of TTS API errors because:
- The original error is never logged
- Only the encoding compatibility error is visible
- Operators cannot diagnose why episodes actually failed
- Episodes get stuck in failed state with no actionable information

## Next Steps

### Immediate Fix
1. Force encoding to UTF-8 on error messages before interpolation:
   ```ruby
   error_msg = error.message.force_encoding("UTF-8")
   @logger.error "Chunk #{chunk_num}/#{total}: ✗ Failed - #{error_msg}"
   ```

### Better Fix (Recommended)
2. Handle encoding robustly with replacement characters:
   ```ruby
   error_msg = error.message.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
   @logger.error "Chunk #{chunk_num}/#{total}: ✗ Failed - #{error_msg}"
   ```

### Additional Improvements
3. Also fix other string interpolations in the same file that use `error.message`
4. Add encoding validation to all logger calls that include error messages
5. Consider a helper method for safe error logging

## Related Files

### `/lib/tts/chunked_synthesizer.rb`
**Contains encoding bugs:**
- Line 94: `if error.message.include?(CONTENT_FILTER_ERROR)` - String search on potentially binary error message
- Line 98: `@logger.error "Chunk #{chunk_num}/#{total}: ✗ Failed - #{error.message}"` - String interpolation with binary error message

### `/lib/tts/api_client.rb`
**Contains encoding bugs:**
- Line 44: `@logger.error "API call failed: #{e.message}"` - String interpolation with binary error message
- Line 73: `raise unless retries < max_retries && e.message.include?(DEADLINE_EXCEEDED_ERROR)` - String search on potentially binary error message

### Test files needing updates:
- `/test/test_chunked_synthesizer.rb` - Tests need encoding error case
- `/test/test_api_client.rb` - Tests need encoding error case

## Verification Plan
After implementing fix:
1. Create test case with binary error message
2. Verify error is logged without encoding errors
3. Verify original error message is preserved (or safely sanitized)
4. Deploy to production
5. Monitor logs for any encoding errors
