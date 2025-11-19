# Error Report - November 17, 2025

## Error 1: Episode Submission - NoMethodError

**Example Error Message:**
```
event=episode_submission_failed episode_id=14 error_class=NoMethodError
error_message="undefined method 'read' for nil"
```

**Timestamp:** 2025-11-17T17:58:14

**Root Cause Analysis:**
The episode submission code is attempting to call `.read` on a nil object, likely a file upload parameter that is missing or failed to upload. This suggests the code assumes a file object exists without validating its presence first.

**Confidence:** 85%

**Proposed Solutions:**

1. **Add nil guard with early return**
   - Pros: Quick fix, prevents crash, easy to implement
   - Cons: May hide underlying upload issue, doesn't improve UX

2. **Validate file presence before processing + user feedback**
   - Pros: Better error handling, provides user feedback, helps debug root cause
   - Cons: Slightly more code, requires flash message/error state handling

3. **Ensure file upload in form validation**
   - Pros: Prevents submission without file, best UX, catches issue early
   - Cons: May need frontend changes, might not catch all edge cases

**Recommendation:** Solution #2 - Validate file presence and provide clear error feedback. This balances safety with diagnostics.

**Priority:** 0 (Critical) - Completely blocks episode submission

---

## Error 2: Episode Processing - Character Encoding Error

**Example Error Message:**
```
Parameters: {"status" => "failed", "error_message" => "incompatible character encodings:
UTF-8 and BINARY (ASCII-8BIT)", "id" => "15", ...}
```

**Timestamps:** Multiple occurrences throughout the day for episodes 15 and 18

**Root Cause Analysis:**
Ruby is attempting to perform string operations that mix UTF-8 encoded text with binary (ASCII-8BIT) data. This typically occurs when reading binary file data and treating it as UTF-8 text without proper encoding conversion, or when concatenating binary and text strings.

**Confidence:** 70%

**Investigation Steps to Increase Confidence:**
1. Examine the episode processing code for episodes 15 and 18
2. Check what file format/content these episodes have
3. Look for string concatenation or text processing on file content
4. Review any text extraction or conversion logic
5. Check if these episodes have special characters or binary attachments

**Priority:** 0 (Critical) - Completely blocking episodes 15 and 18, causing infinite retry loops that waste resources

---

## Error 3: TTS API - Sentence Length Limit

**Example Error Message:**
```
API call failed: 3:This request contains sentences that are too long. Consider splitting
up long sentences with sentence ending punctuation e.g. periods. Sentence starting with:
"Five(" is too long.
```

**Timestamps:** 2025-11-17 22:53:17 (Chunk 678/735), 2025-11-17 22:54:49 (Chunk 724/735)

**Root Cause Analysis:**
The text chunking algorithm is creating chunks that contain individual sentences exceeding Google TTS API's maximum sentence length. The API explicitly rejects these chunks and requests sentence splitting.

**Confidence:** 95%

**Proposed Solutions:**

1. **Add sentence length validation before API call**
   - Pros: Simple, prevents API errors, fast to implement
   - Cons: Doesn't fix the problem, just detects it (still need to handle long sentences)

2. **Implement smart sentence splitting in chunker**
   - Pros: Fixes root cause, improves chunk quality, prevents future errors
   - Cons: More complex, need to handle edge cases (quotes, parentheses, etc.)

3. **Pre-process text with sentence length normalization**
   - Pros: Handles problem upstream, could improve overall TTS quality
   - Cons: Requires text rewriting logic, might change author's voice

**Recommendation:** Solution #2 - Implement smart sentence splitting in the chunker. This addresses the root cause and aligns with what Google TTS API is suggesting.

**Priority:** 1 (Important) - Affects podcast generation quality, but chunks can be retried and most succeed

---

## Error 4: Routing Errors

**Example Error Messages:**
```
ActionController::RoutingError (No route matches [PATCH] "/episodes")
ActionController::RoutingError (No route matches [GET] "/.env")
```

**Root Cause Analysis:**
- `PATCH /episodes` - Likely old client code or incorrect route usage
- `GET /.env` - Security scanner/bot attempting to find exposed environment files

**Confidence:** 90%

**Proposed Solutions:**
1. Review route definitions for episodes controller (PATCH error)
2. Ignore /.env requests (expected bot behavior)

**Priority:** 2 (Nice to have) - Minor issue, doesn't affect core functionality

---

## Summary

**Critical Issues (Priority 0):**
- Episode submission NoMethodError (Episode 14)
- Character encoding errors (Episodes 15, 18) - needs investigation

**Important Issues (Priority 1):**
- TTS API sentence length limits

**Nice to Have (Priority 2):**
- Routing errors
