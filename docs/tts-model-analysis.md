# PodRead TTS Model Analysis

**Date:** February 2026 | **Author:** Claude (Tech Lead) | **Purpose:** Evaluate upgrading premium tier voices

## 1. Model Pricing

### How to fetch pricing data

Google's Cloud TTS pricing page loads dynamically and can't be scraped. The reliable method is querying the **Cloud Billing API** directly:

```bash
# 1. Find the service ID
curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://cloudbilling.googleapis.com/v1/services" | \
  python3 -c "import json,sys; [print(s['name'],s['displayName']) for s in json.load(sys.stdin)['services'] if 'speech' in s['displayName'].lower()]"

# Output: services/02DA-B362-D983 - Cloud Text-to-Speech API

# 2. List all SKUs with tiered pricing
curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://cloudbilling.googleapis.com/v1/services/02DA-B362-D983/skus" | \
  python3 -c "..." # parse tieredRates for each SKU
```

### Pricing table (from billing API, February 2026)

| Model | Free Tier | Price After Free Tier | Billing Unit |
|-------|-----------|----------------------|-------------|
| Standard | 4M chars/month | $4 / 1M chars | Per character |
| WaveNet | 1M chars/month | $16 / 1M chars | Per character |
| Chirp3-HD | 1M chars/month | $30 / 1M chars | Per character |
| Studio | 1M chars/month | $160 / 1M chars | Per character |
| Gemini 2.5 Flash TTS | None | $0.50/1M input tokens + $10/1M output tokens | Per token |
| Gemini 2.5 Pro TTS | None | $1/1M input tokens + $20/1M output tokens | Per token |

**Gemini token math:** Audio output = 32 tokens/second. A 15.5-minute episode (~930 sec) = ~29,760 output tokens. At $10/1M output tokens = ~$0.30/episode in output + negligible input cost.

**Sources:**
- Cloud Billing API: `cloudbilling.googleapis.com/v1/services/02DA-B362-D983/skus`
- [Gemini API pricing](https://ai.google.dev/gemini-api/docs/pricing)
- [Chirp3-HD docs](https://cloud.google.com/text-to-speech/docs/chirp3-hd)

## 2. Quality Assessment

### Leaderboard ranking (Artificial Analysis TTS Arena, ELO)

| Model | ELO | Rank (of 59) |
|-------|-----|-------------|
| Inworld TTS-1 Max | 1,161 | #1 |
| ElevenLabs v2 | 1,106 | #6 |
| **Chirp3-HD** | **1,033** | **#22** |
| Standard | Not ranked | Low |

Gemini Flash/Pro TTS are too new for ELO ranking.

### Subjective comparison (same text, same voice where applicable)

Audio samples generated in `tmp/sample_*.mp3` using identical text:

| Sample | Model | Voice | Accent | Subjective |
|--------|-------|-------|--------|-----------|
| sample_1 | Standard | Wren (en-GB-Standard-C) | British | Robotic, flat |
| sample_2 | Chirp3-HD | Callum (en-GB-Chirp3-HD-Enceladus) | British | Natural, warm, preferred |
| sample_3 | Gemini Flash TTS (via Gemini API) | Enceladus | American (auto-detected) | Natural but wrong accent |
| sample_4 | Gemini Flash TTS (via Cloud TTS API) | Enceladus, en-GB | British | Natural, slightly different character |

### Can Gemini quality be improved?

**Yes.** Gemini TTS via Cloud TTS API supports a `prompt` field for style control:

```python
synthesis_input = texttospeech.SynthesisInput(
    text="Article content here...",
    prompt="Read in a warm, engaging British narrator voice, as if reading a magazine article aloud"
)
voice = texttospeech.VoiceSelectionParams(
    language_code="en-GB",
    name="Enceladus",
    model_name="gemini-2.5-flash-tts"
)
```

This is unavailable with Chirp3-HD. The `prompt` field could potentially close or reverse the quality gap, but Gemini TTS is still in **Preview** for `en-GB`. Chirp3-HD is GA.

**Important:** The `prompt` field requires the `v1beta1` API (`google.cloud.texttospeech_v1beta1`). Using the stable API causes the prompt to be read aloud as part of the audio.

### Gemini TTS consistency problem

Gemini TTS is **non-deterministic**. Three identical requests (same text, same prompt, same voice) produced three different outputs with file sizes ranging from 26KB to 41KB. Pacing, intonation, and delivery vary each time.

For a podcast app where users listen to multiple episodes in sequence, this inconsistency is a real product quality concern. Chirp3-HD produces identical output for the same input every time, giving users a consistent narrator experience across episodes.

### Competitor comparison

| Provider | Model | Price/1M chars | Free Tier | Quality (ELO) |
|----------|-------|---------------|-----------|---------------|
| **Google Chirp3-HD** | Chirp3-HD | $30 | 1M/month | #22 (1,033) |
| **OpenAI** | tts-1 | $15 | None | Not ranked |
| **OpenAI** | tts-1-hd | $30 | None | Not ranked |
| **ElevenLabs** | Multilingual v2 | ~$200 | 10K/month | #6 (1,106) |
| **Amazon Polly** | Neural | $16 | 1M/month (12 mo) | Low |
| **Amazon Polly** | Generative | $30 | None | Mid |
| **Microsoft Azure** | Neural | $16 | 500K/month | Mid |

At current scale, no competitor beats Chirp3-HD's combination of quality + permanent 1M free chars/month. Competitors that are cheaper per-character lack free tiers, making them more expensive in practice. ElevenLabs is the only clear quality upgrade but at ~7x the cost.

## 3. Current Usage Data

### Users

| Account Type | Count |
|-------------|-------|
| Standard (free) | 13 |
| Unlimited | 2 |
| **Total** | **15** |

Active subscriptions: 1 | Credit packs sold: 1

### Episodes

| Metric | Value |
|--------|-------|
| Total episodes | 278 |
| Completed | 262 |
| Failed | 12 |
| Total audio generated | 59.5 hours |
| Avg episode length | 15.5 minutes |
| Avg source text | 15,738 characters |
| Total characters processed | 3,147,664 |

### Episodes by tier

| Tier | Users | Episodes | Voice Type Used |
|------|-------|----------|----------------|
| Free | 5 | 11 | Standard |
| Unlimited | 2 | 224 | Chirp3-HD (Callum: 186, Elara: 38) |
| Premium (subscriber) | 0 | 0 | — |
| Credit pack | 1 | 1 | Standard |

**96% of episodes come from 2 unlimited users on Chirp3-HD voices.**

### LLM preprocessing costs (from production `llm_usages` table)

| Model | Calls | Cost |
|-------|-------|------|
| Gemini 2.5 Flash | 231 | $4.70 |
| Gemini 2.0 Flash | 9 | $0.01 |
| **Total** | **240** | **$4.70** |

LLM cost is negligible (~$0.02/episode).

## 4. Cost Projections

### Per-episode cost by voice model

Based on avg 15,738 chars/episode, 15.5 min audio:

| Model | Cost/Episode | Notes |
|-------|-------------|-------|
| Standard | $0.06 | After free tier exhausted |
| WaveNet | $0.25 | After free tier exhausted |
| Chirp3-HD | $0.47 | After free tier exhausted |
| Gemini Flash TTS | $0.30 | No free tier; from first episode |
| Gemini Pro TTS | $0.60 | No free tier; from first episode |

### Monthly cost at various scales (single voice model across all episodes)

| Episodes/month | Standard | WaveNet | Chirp3-HD | Gemini Flash |
|---------------|----------|---------|-----------|-------------|
| 10 (157K chars) | $0 | $0 | $0 | $3 |
| 30 (471K chars) | $0 | $0 | $0 | $9 |
| 60 (942K chars) | $0 | $0 | $0 | $18 |
| 100 (1.57M chars) | $0 | $9 | $17 | $30 |
| 200 (3.14M chars) | $0 | $34 | $64 | $60 |
| 500 (7.85M chars) | $15 | $110 | $206 | $150 |

**Crossover point:** Gemini Flash TTS becomes cheaper than Chirp3-HD at ~180 episodes/month (~2.8M chars).

### Free tier impact

Free tiers are **per-project, not per-user.** All users share one pool:

| Model | Monthly Free Chars | Episodes Covered |
|-------|-------------------|-----------------|
| Standard | 4,000,000 | ~254 episodes |
| WaveNet | 1,000,000 | ~63 episodes |
| Chirp3-HD | 1,000,000 | ~63 episodes |
| Gemini Flash TTS | 0 | 0 |

At current volume (~75 episodes/month), Standard voices are entirely free. Chirp3-HD/WaveNet cover ~63 episodes free, then bill for the rest.

## 5. Profit Margin Analysis

### Revenue per user

| Plan | Price | Per Episode (at current avg usage) |
|------|-------|------------------------------------|
| Premium Monthly | $9/month | Depends on usage |
| Premium Annual | $89/year ($7.42/month) | Depends on usage |
| Credit Pack | $4.99 / 5 episodes | $1.00/episode |
| Free | $0 | $0 |
| Unlimited | Complimentary | $0 |

### Marginal cost per episode (including LLM preprocessing)

| Voice Model | TTS Cost | LLM Cost | Total Marginal Cost |
|-------------|---------|----------|-------------------|
| Standard | $0.06 | $0.02 | **$0.08** |
| WaveNet | $0.25 | $0.02 | **$0.27** |
| Chirp3-HD | $0.47 | $0.02 | **$0.49** |
| Gemini Flash TTS | $0.30 | $0.02 | **$0.32** |

*Note: These are post-free-tier costs. With free tier, actual costs are lower.*

### Impact of upgrading premium voices from Standard to better models

**Scenario: A premium subscriber ($9/month) processes 15 episodes/month**

| Voice Model | Monthly TTS Cost | Margin on $9/month | Margin % |
|-------------|-----------------|-------------------|---------|
| Standard (current) | $0* | $8.70 | 97% |
| WaveNet | $0* | $8.70 | 97% |
| Chirp3-HD | $0* | $8.70 | 97% |
| Gemini Flash TTS | $4.50 | $4.20 | 47% |

*\*Free tier covers 15 episodes/month for Standard (254 eps free), WaveNet (63 eps free), and Chirp3-HD (63 eps free).*

**Scenario: 50 premium subscribers, each processing 15 episodes/month (750 total)**

| Voice Model | Monthly TTS Cost | Revenue | Margin |
|-------------|-----------------|---------|--------|
| Standard | $0 | $450 | $450 (100%) |
| WaveNet | $138 | $450 | $312 (69%) |
| Chirp3-HD | $338 | $450 | $112 (25%) |
| Gemini Flash TTS | $225 | $450 | $225 (50%) |

At scale, free tiers are exhausted early in the month and per-unit costs dominate.

### Recommendation

**For current scale (15 users, ~75 episodes/month):**

Upgrade premium users to **WaveNet** voices. The 1M free chars/month covers ~63 episodes. At current volume, this upgrade is essentially **free** while delivering noticeably better quality than Standard voices. WaveNet sits in the quality sweet spot between robotic Standard and premium Chirp3-HD.

**Tier structure:**

| Tier | Current Voice | Proposed Voice | Quality | Cost Impact |
|------|-------------|---------------|---------|------------|
| Free | Standard | Standard (no change) | Baseline | None |
| Premium | Standard | **WaveNet** | Better | ~$0 at current scale |
| Unlimited | Chirp3-HD | Chirp3-HD (no change) | Best | None |

**When to revisit:**
- **Gemini Flash TTS** — when `en-GB` exits Preview and volume exceeds ~180 episodes/month
- **Chirp3-HD for premium** — if WaveNet doesn't differentiate enough to drive upgrades
- **Gemini Pro TTS** — if style-prompted quality surpasses Chirp3-HD (test when GA)

## Appendix: "A.I." Pronunciation Fix

During this analysis, we identified and fixed a TTS pronunciation issue: "AI" in articles was sometimes pronounced as the syllable "ai" (rhyming with "eye") instead of spelled out as "A.I."

**Fix:** Added an instruction to the shared LLM preprocessing prompt in `BuildsProcessingPrompt`:

```ruby
- Write "A.I." instead of "AI" so it is pronounced as individual letters
```

This approach uses the existing LLM preprocessing step (Gemini 2.5 Flash) to handle the substitution contextually, avoiding false positives that a regex approach might cause. The fix applies to all episode types (URL, paste, email).
