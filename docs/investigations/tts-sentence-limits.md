# Google TTS API Sentence Length Limits

## Error Messages
From production logs (2025-11-17):

```
This request contains sentences that are too long. Consider splitting up
long sentences with sentence ending punctuation e.g. periods. Sentence
starting with: "Five(" is too long.
```

```
Sentence starting with: "Take " is too long.
```

## Limits
- **Sentence limit**: Unknown exact byte/character count
- **Recommendation**: Split at sentence boundaries (periods, question marks, exclamation points)
- **Fallback**: Split at clause boundaries (commas, semicolons, colons)

## Chunks Affected
- Chunk 678/735: "Five("
- Chunk 724/735: "Take "

## Solution
Enhance TextChunker to:
1. Detect sentences > safe threshold (suggest 300 bytes)
2. Split at clause boundaries when sentence is too long
3. Add validation before API call

## References
- Error logs: hub/error-report-2025-11-17.md
- Google TTS docs: https://cloud.google.com/text-to-speech/quotas
