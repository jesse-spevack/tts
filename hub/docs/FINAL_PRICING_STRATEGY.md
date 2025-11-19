# TTS Podcast Service - Pricing Strategy

## Key Discovery: Standard = Neural2 Quality

**Testing revealed:** British Standard (en-GB-Standard-B) and Neural2 (en-GB-Neural2-B) produce **identical audio** (same MD5 hash). This means:
- Use Standard voice: $4/1M chars + **4M free/month**
- Skip Neural2: $16/1M chars + only 1M free/month
- **4x cheaper with 4x larger free tier**

---

## Voice Comparison

| Voice | Quality | Cost | Free Tier | Best For |
|-------|---------|------|-----------|----------|
| **Standard** | Professional | $4/1M | 4M/month | All tiers (same as Neural2) |
| **Chirp3-HD** | Premium | $30/1M | 1M/month | Audio purists only |

**Conversion guide:**
- 5,000 chars = ~1,000 words = ~7 min podcast
- 10,000 chars = ~2,000 words = ~15 min podcast
- 50,000 chars = ~10,000 words = ~65 min podcast

---

## Recommended Pricing: Three Tiers

| Plan | Price | Episodes | Chars/mo | ≈ Blog Posts | Voice | Your Cost | Profit | Margin |
|------|-------|----------|----------|--------------|-------|-----------|--------|--------|
| **BASIC** | $3 | 10 | 50K | ~10 | Standard | $0.35 | $2.65 | 88% |
| **PLUS** ⭐ | $9 | 40 | 200K | ~40 | Standard | $0.60 | $8.40 | 93% |
| **PREMIUM** | $15 | 40 | 200K | ~40 | Chirp3-HD | $2.00 | $13.00 | 87% |

**Per-episode safety limits:**
- BASIC: 25,000 chars max (5,000 words)
- PLUS/PREMIUM: 50,000 chars max (10,000 words)

**Differentiation:**
- BASIC → PLUS: 4x more episodes (volume upgrade)
- PLUS → PREMIUM: Chirp3-HD studio quality (audio upgrade)

---

## Real-World Usage Scenarios

### Weekly Blogger
**Content:** 1,000 word blog post per week (4/month)

**Usage:** 4 episodes × 5,000 chars = 20,000 chars/month

**Recommended:** BASIC ($3/mo)
- Fits easily in 50K limit
- 6 episodes left for other content
- Professional quality

---

### Bi-Weekly Newsletter
**Content:** 2,000 word newsletter, twice per month

**Usage:** 2 episodes × 10,000 chars = 20,000 chars/month

**Recommended:** PLUS ($9/mo)
- Only 10% of limit used
- 38 episodes left for archives
- Same voice quality as BASIC (Standard)

---

### Daily Short Posts
**Content:** 500 words, 5 days/week (20/month)

**Usage:** 20 episodes × 2,500 chars = 50,000 chars/month

**Recommended:** PLUS ($9/mo)
- 25% of limit used
- Room to grow
- Professional voice quality

---

### Premium Podcast Publisher
**Content:** High-quality weekly podcast (3,000 words each)

**Usage:** 4 episodes × 15,000 chars = 60,000 chars/month

**Recommended:** PREMIUM ($15/mo)
- Fits in 200K limit
- Chirp3-HD studio quality worth it for podcast audience
- API access for automation

---

## Cost Protection

### Character Limits (Prevent $373 Incident)

**Per episode hard limits:**
- BASIC: 25K chars (5,000 words max)
- PLUS/PREMIUM: 50K chars (10,000 words max)

**Max cost with retry limit (3 attempts):**
- BASIC: $0.30 total (vs $200+ in incident)
- PLUS: $0.60 total
- PREMIUM: $4.50 total

**API Quotas (Google Cloud):**
- All requests: 10/min
- Chirp3-HD: 5/min
- **Daily max spend:** ~$7-10/day (vs $373/day incident)

### Retry Limits
- Max 3 retries per episode
- Track retry count in database
- Alert user after 3 failures

---

## Actual Costs at Scale

### Small Scale (130 users, 50% avg usage)
```
Users:
- 50 FREE (15K avg) = 750K chars
- 30 BASIC (25K avg) = 750K chars
- 40 PLUS (100K avg) = 4M chars
- 10 PREMIUM (100K avg) = 1M chars Chirp3-HD

Standard voice total: 5.5M chars
- Free tier: 4M chars = $0
- Paid: 1.5M × $4/1M = $6

Chirp3-HD total: 1M chars
- Free tier: 1M chars = $0
- Paid: $0

TTS Cost: $6/month
Infrastructure: $30/month
Total Cost: $36/month

Revenue: $600/month
Profit: $564/month
Margin: 94%
```

### Growth Scale (500 users, 50% avg usage)
```
Users:
- 150 FREE (15K avg) = 2.25M chars
- 150 BASIC (25K avg) = 3.75M chars
- 150 PLUS (100K avg) = 15M chars
- 50 PREMIUM (100K avg) = 5M chars Chirp3-HD

Standard voice total: 21M chars
- Free tier: 4M = $0
- Paid: 17M × $4/1M = $68

Chirp3-HD total: 5M chars
- Free tier: 1M = $0
- Paid: 4M × $30/1M = $120

TTS Cost: $188/month
Infrastructure: $50/month
Total Cost: $238/month

Revenue: $3,000/month
Profit: $2,762/month
Margin: 92%
```

**Key insight:** TTS costs stay incredibly low thanks to 4M free Standard tier!

---

## Why This Works

### Standard Voice Strategy
1. **Same quality as Neural2** (literally identical audio)
2. **4M free tier** (vs 1M for Neural2)
3. **$4/1M** (vs $16/1M for Neural2)
4. **Professional quality** good enough for 90% of users

### Chirp3-HD Premium Tier
1. **Noticeably better** than Standard (you heard the difference)
2. **Captures 10-20%** of users who care about audio quality
3. **High margins** even at $30/1M cost
4. **Differentiator** from competitors

### Volume-Based Tiers
1. **BASIC gets people in** at $3/mo (matches ListenLater.fm reference)
2. **PLUS is the sweet spot** at $9/mo with 4x episodes
3. **PREMIUM adds quality** not quantity (same 200K chars as PLUS)

---

## Competitive Positioning

| Service | Price | Your Advantage |
|---------|-------|----------------|
| Play.ht | $39/mo | You: $15/mo = 62% cheaper |
| Descript | $24/mo | You: $15/mo = 38% cheaper |
| ElevenLabs | $22/mo | You: $9/mo = 59% cheaper |
| Speechify | $29/mo | You: $15/mo = 48% cheaper |
| ListenLater.fm | $3/mo | You: Match price + better quality |

**Your angle:** "Professional podcast creation from $3/month. No surprises."

---

## Implementation Checklist

### Before Launch
- [ ] Implement character limits (25K/50K per episode)
- [ ] Add retry tracking (max 3 attempts)
- [ ] Set Google Cloud API quotas
- [ ] Set budget alerts ($50/month)
- [ ] Build usage dashboard
- [ ] Add character counter to UI

### Pricing Page Must-Haves
- [ ] Clear character → word → podcast time conversions
- [ ] Real-world examples (blogger, newsletter, etc.)
- [ ] Voice quality audio samples
- [ ] FAQ about characters
- [ ] Annual pricing (17% off)

### Post-Launch Monitoring
- [ ] Track actual TTS costs vs projections
- [ ] Monitor conversion rates between tiers
- [ ] Watch for users hitting limits
- [ ] Adjust pricing if needed

---

## Summary

**Recommended: BASIC/PLUS/PREMIUM at $3/$9/$15**

**Key insights:**
- Standard voice = Neural2 quality (4x cheaper + 4x free tier)
- Only offer Chirp3-HD for PREMIUM tier
- Differentiate on volume (BASIC→PLUS) and quality (PLUS→PREMIUM)
- 90%+ margins thanks to generous Standard free tier

**Expected outcome (500 users):**
- Revenue: $3,000/month
- Costs: $238/month
- Profit: $2,762/month
- Margin: 92%
- Annual: **$33,144 profit**

**Next step:** Implement safeguards, then build pricing page.
