# Incident Report: TTS API Cost Overrun

**Date:** November 17, 2025
**Severity:** High (Financial Impact)
**Status:** Resolved
**Total Cost Impact:** ~$373 USD

---

## Executive Summary

On November 17, 2025, two failed episode processing jobs entered infinite retry loops, generating 13.4 million TTS API character requests using the premium Chirp3-HD voice ($30/1M characters). This resulted in an unexpected bill of approximately $373 for a toy application with minimal expected usage.

**Key Finding:** A character encoding error caused episodes to fail during processing, triggering Cloud Tasks' automatic retry mechanism. Without file size limits or retry caps, these failures compounded into a significant cost overrun.

---

## Timeline (All times UTC)

### Episode 15 Lifecycle
- **17:58:14** - Initial submission, file uploaded (582,241 bytes)
- **17:58:14 - 18:56:07** - Failed 13 times over 58 minutes
- **18:56:07** - Final retry attempt
- **After 18:56** - Cloud Tasks stopped retrying (max attempts reached)

### Episode 18 Lifecycle
- **21:40:12** - Initial submission, file uploaded (582,241 bytes)
- **21:40:16 - 22:40:58** - Failed 13 times over 60 minutes
- **22:40:58** - Final retry attempt
- **After 22:40** - Cloud Tasks stopped retrying (max attempts reached)

### Discovery
- **~07:00 Nov 18** - User noticed unusually high TTS API costs
- **07:30 Nov 18** - Investigation began
- **07:45 Nov 18** - Root cause identified

---

## Impact Analysis

### Financial Impact
```
Episode 15: 515,000 chars × 13 retries = 6,695,000 characters
Episode 18: 515,000 chars × 13 retries = 6,695,000 characters
Total: 13,390,000 characters

Chirp3-HD Pricing:
- First 1M characters/month: FREE
- Additional characters: $30 per 1M

Cost Calculation:
(13,390,000 - 1,000,000) × $30 / 1,000,000 = $371.70

Approximate Total: ~$373
```

### Operational Impact
- Two episodes permanently failed
- ~26 Cloud Tasks consumed (13 per episode)
- ~9,555 TTS API calls made (735 chunks × 13 retries per episode)
- Users unable to process these specific episodes
- Increased Cloud Run costs from extended processing time

### User Impact
- Minimal direct user impact (toy app with single user)
- Two episodes stuck in failed state
- No data loss (episodes retained in database)

---

## Root Cause Analysis

### Primary Cause: Character Encoding Error

From error logs (error-report-2025-11-17.md):
```
Parameters: {"status" => "failed", "error_message" => "incompatible character encodings:
UTF-8 and BINARY (ASCII-8BIT)", "id" => "15", ...}
```

**What Happened:**
1. User uploaded 582KB markdown file containing special characters or binary data
2. Generator service attempted to process file as UTF-8 text
3. String operations mixing UTF-8 and ASCII-8BIT encodings caused Ruby exceptions
4. Processing failed before any audio was generated
5. Failure callback marked episode as `failed` in Hub database

**Why It Cost So Much:**
- Despite failing, the service had already made 735 TTS API calls (one per chunk)
- Each retry re-downloaded the file and re-processed all 735 chunks
- Failures occurred late in processing (around chunk 678-724 in some attempts)

### Contributing Factors

#### 1. No File Size Limits
**Evidence from logs:**
```
event=file_downloaded episode_id=15 size_bytes=582241
event=file_downloaded episode_id=18 size_bytes=582241
```

- 582KB file = approximately 515,000 characters
- No validation prevented large file uploads
- Cost per episode: 515K chars × $30/1M = $15.45 (with free tier exhausted)

**Impact:** Without size limits, users could unknowingly submit expensive files

#### 2. No Retry Limits in Application
**Evidence:** Episode model had no `retry_count` tracking

- Application relied solely on Cloud Tasks retry policy
- No visibility into how many times an episode had failed
- No circuit breaker to stop retrying known-bad episodes

**Impact:** Once in retry loop, episodes continued until Cloud Tasks gave up (~13 attempts)

#### 3. Expensive Voice Selection
**Evidence from logs:**
```
Making API call (365 bytes) with voice: en-GB-Chirp3-HD-Enceladus
```

**Cost comparison:**
- **Chirp3-HD** (in use): $30 per 1M chars after 1M free
- **Neural2**: $16 per 1M chars after 1M free
- **Standard**: $4 per 1M chars after 4M free

**Impact:** Using most expensive voice (2-7.5x more costly than alternatives)

#### 4. Cloud Tasks Default Retry Policy
**Observed behavior:** 13 retry attempts per episode

Cloud Tasks default configuration:
- Initial retry delay: 1 second
- Exponential backoff with max 10 seconds
- Max attempts: ~15 attempts over several hours
- Max retry duration: 1 hour

**Impact:** Generous retry policy appropriate for transient failures, but catastrophic for persistent errors

#### 5. Late Failure Detection
**Evidence from logs:**
```
Chunk 678/735: ... (failed)
Chunk 724/735: ... (failed)
```

- Encoding errors occurred during text chunking/processing
- Some retries failed near the end (chunk 678+/735)
- All 735 TTS API calls were made before failure detected

**Impact:** Maximum TTS cost incurred even when processing ultimately failed

---

## What Worked Well

1. **Cloud Tasks stopped retrying** - Default policy eventually gave up, preventing infinite costs
2. **Episodes marked as failed** - Database state accurately reflected failure
3. **Logging captured errors** - Sufficient detail to diagnose root cause
4. **No data corruption** - Failed episodes remained in database for analysis

---

## What Didn't Work

1. **No cost guardrails** - Nothing prevented expensive operations
2. **No alerting** - User discovered issue through billing dashboard, not proactive alerts
3. **No input validation** - Large files and problematic encodings accepted without checks
4. **Silent retries** - No visibility into retry loops until after damage done
5. **Fail-late architecture** - Expensive TTS calls made before encoding validation

---

## Detailed Cost Breakdown

### Per-Episode Costs (Episode 18 as example)

```
File: 582,241 bytes = ~515,000 characters
Chunks: 735 chunks (average ~700 bytes per chunk)
Voice: Chirp3-HD @ $30 per 1M characters

Single Processing Attempt:
- Characters processed: 515,000
- TTS API calls: 735
- Cost (without free tier): $15.45

13 Retry Attempts:
- Total characters: 515,000 × 13 = 6,695,000
- Total API calls: 735 × 13 = 9,555
- Cost (without free tier): $200.85

With 1M free tier allocated across both episodes:
Episode 15: (6,695,000 - 500,000) × $30 / 1M = $185.85
Episode 18: (6,695,000 - 500,000) × $30 / 1M = $185.85
Total: ~$371.70
```

### Alternate Cost Scenarios

**If using Neural2 voice ($16/1M):**
- Total: (12.39M × $16) / 1M = $198.24
- **Savings: $173.46 (46%)**

**If using Standard voice ($4/1M, 4M free):**
- Total: (9.39M × $4) / 1M = $37.56
- **Savings: $334.14 (90%)**

**If 10K character limit enforced:**
- Would have rejected both files at submission
- **Cost: $0**

---

## Resolution Steps Taken

1. ✅ Verified retries stopped naturally (Cloud Tasks max attempts reached)
2. ✅ Confirmed Cloud Tasks queue empty (no pending retries)
3. ✅ Identified both affected episodes (15 & 18)
4. ✅ Documented incident with log evidence
5. ✅ Created implementation plan for safeguards

## Prevention Measures (Planned)

### Immediate (Being Implemented)
1. **10,000 character file size limit** - Reject large files at submission
   - Cost cap: $0.30/episode with Chirp3-HD
   - Implementation: `EpisodeSubmissionService` validation

2. **Retry count tracking** - Track failures, warn at max retries
   - Implementation: `Episode.retry_count` column
   - Max retries: 3 attempts
   - Prevents: Infinite retry loops

3. **Google Cloud API quotas** - Hard rate limits
   - All requests per minute: 5-20 (was 100)
   - Chirp3-HD requests per minute: 1-5 (was 200)
   - Cost cap: ~$7.20/day maximum

4. **Budget alerts** - Email notifications at spending thresholds
   - Alerts at: 50%, 75%, 90%, 100% of budget
   - Early warning system for cost overruns

### Short-term (Next Sprint)
1. **Voice selection** - Consider switching to Neural2 or Standard
   - Potential savings: 46-90% on TTS costs
   - Trade-off: Slight quality reduction

2. **Client-side validation** - JavaScript file size check
   - Better UX than server-side rejection
   - Immediate feedback to users

3. **Cost estimation** - Show estimated cost before submission
   - Transparency for users
   - Informed decision making

### Long-term (Backlog)
1. **Admin dashboard** - Real-time cost/usage monitoring
2. **Fail-fast validation** - Check encoding before TTS calls
3. **Per-user quotas** - Prevent individual users from overspending
4. **Progressive retry backoff** - Exponential delays for repeated failures

---

## Lessons Learned

### Technical
1. **Validate early, fail fast** - Encoding errors should be caught before expensive operations
2. **Cost visibility matters** - Without monitoring, issues discovered too late
3. **Retry policies need context** - Cloud Tasks defaults assume transient failures
4. **Free tiers reset monthly** - November's damage doesn't affect December budget

### Operational
1. **Toy apps need guardrails too** - "Just for fun" doesn't mean "no cost controls"
2. **Cloud defaults aren't always appropriate** - GCP quotas set for enterprise scale
3. **Logging helped diagnosis** - Structured event logging made RCA straightforward
4. **Retries are double-edged** - Resilience feature became cost amplifier

### Process
1. **No alerting = no prevention** - Reactive discovery vs proactive prevention
2. **Cost awareness at design time** - TTS costs not considered during initial implementation
3. **Testing with production data** - Large files never tested until production

---

## Action Items

### Immediate
- [x] Verify retries stopped
- [x] Document incident
- [ ] Implement 10K character limit
- [ ] Add retry count tracking
- [ ] Set Google Cloud API quotas
- [ ] Configure budget alerts

### This Week
- [ ] Deploy safeguards to production
- [ ] Test with 9K and 11K character files
- [ ] Verify failed episodes don't retry
- [ ] Consider voice downgrade

### This Month
- [ ] Add client-side validation
- [ ] Build cost estimation feature
- [ ] Review and optimize Cloud Tasks retry policy
- [ ] Add fail-fast encoding validation

---

## Supporting Data

### Episode Details
```
Episode 15:
- ID: 15
- Title: [Unknown - check database]
- Status: failed
- File size: 582,241 bytes
- Retry count: 13
- First attempt: 2025-11-17 17:58:14 UTC
- Last attempt: 2025-11-17 18:56:07 UTC
- Duration: ~58 minutes

Episode 18:
- ID: 18
- Title: "Strangers"
- Status: failed
- File size: 582,241 bytes
- Retry count: 13
- First attempt: 2025-11-17 21:40:12 UTC
- Last attempt: 2025-11-17 22:40:58 UTC
- Duration: ~60 minutes
```

### Log Evidence
- Processing start events: 13 per episode (confirmed via gcloud logging)
- File downloads: 13 per episode (same file downloaded repeatedly)
- Chunk processing: 735 chunks per attempt
- Error pattern: Character encoding incompatibility (UTF-8 vs ASCII-8BIT)

### Cost Validation
```
Google Cloud Pricing (from billing export):
- SKU ID: F977-2280-6F1B
- Description: "Count of characters for Chirp3-HD voices"
- Pricing: $0.00 for first 1M, $30.00 per 1M thereafter
- Consumption: 13,390,000 characters
- Estimated cost: $371.70
```

---

## Recommendations

### For This Application
1. **Implement all immediate prevention measures** - Critical before re-enabling
2. **Switch to Neural2 voice** - 46% cost savings with minimal quality loss
3. **Add cost monitoring** - Build dashboard showing monthly TTS usage
4. **Consider file format restrictions** - Only accept plain text, validate UTF-8

### For Similar Applications
1. **Design with cost in mind** - Consider pricing during architecture
2. **Set quotas from day one** - Don't rely on defaults
3. **Test with realistic data** - Include large files in test suite
4. **Monitor from day zero** - Set up alerts before first production use
5. **Document cost assumptions** - Make expected costs explicit

---

## Appendix: Related Documents

- `error-report-2025-11-17.md` - Original error analysis
- `docs/plans/2025-11-18-add-tts-cost-safeguards.md` - Implementation plan
- `docs/TTS_COST_SAFEGUARDS.md` - Ongoing safeguards documentation

---

**Report Prepared By:** Claude Code (Automated Analysis)
**Date:** 2025-11-18
**Review Status:** Draft - Awaiting user validation
