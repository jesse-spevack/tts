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
| **Standard** | Professional | $4/1M | 4M/month | All users (same as Neural2) |

**Conversion guide:**
- 5,000 chars = ~1,000 words = ~7 min podcast
- 10,000 chars = ~2,000 words = ~15 min podcast
- 50,000 chars = ~10,000 words = ~65 min podcast

---

## Recommended Pricing: Two Tiers

| Plan | Price | Episodes/mo | Chars/episode | Voice |
|------|-------|-------------|---------------|-------|
| **FREE** | $0 | 2 | 15,000 | Standard |
| **PRO** | $9/mo | Unlimited | 50,000 | Standard |

**Annual option:** $89/year (17% discount)

---

## Why Two Tiers?

### Simplicity Wins

1. **No decision fatigue** — Users either try free or upgrade to PRO
2. **No counting anxiety** — Unlimited episodes removes friction
3. **Generous limits** — 50K chars/episode covers 96% of real-world content
4. **One upgrade path** — FREE → PRO, done

### Why No $5 Tier?

| Price | Stripe Fee | % Lost | Problem |
|-------|------------|--------|---------|
| $5 | $0.45 | 9% | High churn, price-sensitive users |
| $9 | $0.56 | 6% | Sweet spot — impulse buy, sustainable |

- $5 users churn faster and generate more support tickets
- Support cost per user is the same regardless of tier
- $4 difference doesn't justify the complexity

### Why $9?

- Low enough to be an impulse purchase
- High enough to cover costs and be worth your time
- Matches successful competitors (ElevenLabs entry tier)
- Stripe fee becomes reasonable (6%)

---

## Margin Analysis (with Stripe Fees)

Previous analysis ignored Stripe fees (2.9% + $0.30). Here's the corrected math:

### FREE Tier

```
Episodes: 2/month × 15K chars = 30K chars max
TTS cost: 30,000 × $0.000004 = $0.12/user/month
```

Loss leader — converts users to paid.

### PRO Tier ($9/month)

**At typical usage (10 episodes × 15K chars = 150K):**
```
TTS cost:    150,000 × $0.000004 = $0.60
Stripe fee:  $9 × 2.9% + $0.30 = $0.56
Total cost:  $1.16
Profit:      $7.84
Margin:      87%
```

**At heavy usage (30 episodes × 50K chars = 1.5M):**
```
TTS cost:    1,500,000 × $0.000004 = $6.00
Stripe fee:  $0.56
Total cost:  $6.56
Profit:      $2.44
Margin:      27%
```

**At realistic heavy usage (20 episodes × 25K chars = 500K):**
```
TTS cost:    500,000 × $0.000004 = $2.00
Stripe fee:  $0.56
Total cost:  $2.56
Profit:      $6.44
Margin:      72%
```

### Annual PRO ($89/year)

```
Stripe fee:  $89 × 2.9% + $0.30 = $2.88 (vs $6.72 monthly)
Savings:     $3.84/year on Stripe alone
```

Annual billing is better for both parties.

---

## Real-World Episode Analysis

Analysis of 22 actual episodes in the input directory:

| Metric | Characters | Words | Podcast Time |
|--------|------------|-------|--------------|
| **Min** | 5,681 | 913 | 6 min |
| **Max** | 54,195 | 8,402 | 59 min |
| **Average** | 16,696 | 2,731 | 18 min |
| **Median** | 13,701 | 2,179 | 15 min |

### Distribution

| Size Bucket | Episodes | % | Cumulative |
|-------------|----------|---|------------|
| < 10K chars | 6 | 27% | 27% |
| 10K - 15K | 8 | 36% | 64% |
| 15K - 25K | 4 | 18% | 82% |
| 25K - 50K | 3 | 14% | 96% |
| > 50K | 1 | 4% | 100% |

### Limit Coverage

| Per-Episode Limit | Episodes That Fit | Coverage |
|-------------------|-------------------|----------|
| 15,000 chars (FREE) | 14 | 64% |
| 50,000 chars (PRO) | 21 | 96% |

**Key insight:** The 50K limit handles virtually all real content. The single outlier (54K) costs $0.22 — just let it through.

---

## Cost Protection

### Per-Episode Hard Limit: 50K chars

- Prevents abuse (someone uploading a book)
- Max TTS cost per episode: $0.20
- Users rarely notice (96% of content fits)

### Retry Limits

- Max 3 retries per episode
- Max cost with retries: $0.60 per episode
- Track retry count in database

### API Quotas (Google Cloud)

- All requests: 10/min
- Daily max spend: ~$10/day worst case

### Budget Alerts

- Set Google Cloud alert at $50/month
- Monitor actual vs projected costs

---

## Projected Economics

### Small Scale (100 paying users)

```
Users: 100 PRO @ $9/month

Revenue:     $900/month
TTS cost:    ~$25 (assuming 250K chars avg per user)
Stripe:      $56
Infra:       $30
Total cost:  $111

Profit:      $789/month
Margin:      88%
Annual:      $9,468
```

### Growth Scale (500 paying users)

```
Users: 500 PRO @ $9/month

Revenue:     $4,500/month
TTS cost:    ~$100 (assuming 200K chars avg per user)
Stripe:      $280
Infra:       $50
Total cost:  $430

Profit:      $4,070/month
Margin:      90%
Annual:      $48,840
```

---

## Competitive Positioning

| Service | Price | Your Advantage |
|---------|-------|----------------|
| Play.ht | $39/mo | You: $9/mo = 77% cheaper |
| Descript | $24/mo | You: $9/mo = 63% cheaper |
| ElevenLabs | $22/mo | You: $9/mo = 59% cheaper |
| Speechify | $29/mo | You: $9/mo = 69% cheaper |

**Your angle:** "Unlimited podcast episodes for $9/month. No complexity."

---

## Implementation Checklist

### Before Launch
- [ ] Implement 50K character limit per episode
- [ ] Add retry tracking (max 3 attempts)
- [ ] Set Google Cloud budget alerts ($50/month)
- [ ] Build usage dashboard
- [ ] Add character counter to UI
- [ ] Implement Stripe subscription ($9/mo, $89/yr)

### Pricing Page
- [ ] Simple two-tier comparison (FREE vs PRO)
- [ ] Character → word → time conversion guide
- [ ] "Unlimited episodes" prominently featured
- [ ] Annual discount callout (save 17%)
- [ ] FAQ about character limits

### Post-Launch
- [ ] Track actual TTS costs vs projections
- [ ] Monitor conversion rate (FREE → PRO)
- [ ] Watch for users hitting 50K limit
- [ ] Consider Business tier ($19?) at 500+ users

---

## Summary

**Pricing: FREE + PRO at $9/month**

| Tier | Price | Episodes | Chars/episode |
|------|-------|----------|---------------|
| FREE | $0 | 2/month | 15,000 |
| PRO | $9/mo | Unlimited | 50,000 |

**Why this works:**
- TTS is so cheap that margins are healthy regardless
- Simplicity converts better than complex tier structures
- $9 is the sweet spot (impulse buy, sustainable revenue)
- Generous limits create happy users who spread word of mouth
- Stripe's fixed fee hurts low price points — skip the $5 tier

**Expected outcome (500 users):**
- Revenue: $4,500/month
- Costs: $430/month
- Profit: $4,070/month
- Margin: 90%
- Annual: **$48,840 profit**

**Philosophy:** Don't optimize for 95% margin on TTS costs. Optimize for happy users who tell their friends. The goodwill from generous limits is worth more than squeezing every penny.
