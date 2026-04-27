# ElevenLabs Business Model Analysis

**Date:** April 2026 | **Author:** Claude (with Jesse) | **Purpose:** Decide how (and whether) to offer ElevenLabs voices in PodRead

## TL;DR

PodRead's current pricing is calibrated for Google TTS economics. Dropping ElevenLabs into the existing $9/mo Premium tier would invert unit economics for any heavy user. Three viable models exist; the recommended starting point is **BYOK (bring your own key)** — it costs nothing to ship, generates real signal about user demand, and defers the harder pricing-tier work until we have evidence that demand exists.

**Open precondition:** No user has explicitly asked for higher voice quality. `tts-model-analysis.md` rated the current Chirp3-HD voices "natural, warm, preferred" in subjective testing. Validate the demand before building.

## How ElevenLabs works

REST API. POST text + a `voice_id` to `https://api.elevenlabs.io/v1/text-to-speech/{voice_id}` with an `xi-api-key` header. Returns audio bytes.

Key concepts that differ from Google TTS:

- **Voices are opaque IDs, not locale+model+name strings.** Google identifies a voice as `en-GB-Chirp3-HD-Enceladus`. ElevenLabs uses 20-char IDs like `21m00Tcm4TlvDq8ikWAM`. You either pick from their Voice Library (thousands of pre-made voices, filterable by accent/gender/age/use-case) or clone a voice from a 1–3 minute audio sample.
- **Models are a separate axis from voices.** Pick model per request — not per voice.
  - `eleven_v3` — highest quality, slowest, most expensive
  - `eleven_multilingual_v2` — balanced
  - `eleven_turbo_v2_5` — faster, cheaper
  - `eleven_flash_v2_5` — fastest, cheapest, sub-second latency
- **Voice settings are per-request knobs.** `stability` (0–1: higher = more consistent, lower = more expressive), `similarity_boost`, `style`, `use_speaker_boost`. Pitch/rate are not direct params — character comes from the voice + these dials.
- **Per-request character cap differs.** ElevenLabs v3 caps around 5,000 chars per request. PodRead's existing `Tts::ChunkedSynthesizer` chunks at 850 bytes for Google's limits; the chunking strategy will need provider-specific tuning.

## Quality reference

From `tts-model-analysis.md` (Artificial Analysis TTS Arena ELO):

| Model | ELO | Rank (of 59) |
|-------|-----|-------------|
| ElevenLabs v3 (v2 in original table) | 1,106 | #6 |
| Chirp3-HD (current PodRead premium) | 1,033 | #22 |
| Standard (current PodRead free) | Not ranked | Low |

Real but not enormous. Whether it's worth the cost delta is the actual question.

## Current PodRead economics (baseline)

From `app/models/app_config.rb`:

| Tier | Price | Char limit per episode | Episodes/mo | Voices |
|------|-------|------------------------|-------------|--------|
| Free | $0 | 15,000 | 2 | 8 Standard voices |
| Premium | $9/mo | 50,000 | unlimited | 8 Standard + 4 Chirp3-HD |
| Credit pack | $4.99 / 5 episodes ($1/ep) | per-episode | metered | per user's tier |

**Chirp3-HD cost reality** (Premium user @ 10 episodes/mo × 25K chars):
- 250K chars × $30/1M chars = **~$7.50 cost** vs **$9 revenue** → ~$1.50 gross/user/month
- Tight. Survives because most users are below this.

## ElevenLabs cost projection (same usage)

Effective per-character cost depends heavily on subscription tier (credits per character vary by model):

| Model | Effective cost (rough) | Cost @ 250K chars/mo |
|-------|------------------------|----------------------|
| Flash v2.5 | ~$0.05 / 1K chars | ~$12.50 |
| Multilingual v2 | ~$0.18 / 1K chars | ~$45 |
| v3 | ~$0.30 / 1K chars | ~$75 |

**Important caveat:** these are rough numbers. Actual ElevenLabs pricing depends on which subscription plan PodRead is on (Creator $22/mo, Pro $99/mo, Scale $330/mo, etc.) and how many credits each model consumes per character. **Before committing to any model, generate 5–10 sample episodes on real article content and measure exact cost per episode.**

**The economics problem in one line:** at $9/mo Premium revenue, only Flash is in the same ballpark as Chirp3-HD. v3 is ~10× more expensive than current Chirp3-HD costs.

## Three viable business models

### Option 1 — BYOK (bring your own key)

Premium users paste their own ElevenLabs API key in settings. PodRead uses it to synthesize their episodes. Zero variable cost to PodRead.

**Pros:**
- Ship in a weekend. Zero new Stripe plumbing, zero new pricing tier UI.
- Zero margin risk. Heavy users pay ElevenLabs directly.
- Filters for users who care enough to actually want it. If ~zero users opt in, you have your demand answer for free.
- Aligns with PodRead's craft-scale, personal-tools ethos.

**Cons:**
- Friction. Most users won't sign up for an ElevenLabs account.
- Doesn't capture revenue from the feature.
- PodRead handles user keys (encryption, revocation, error UX).

### Option 2 — Flash-tier inclusion + v3 upcharge

Include ElevenLabs Flash v2.5 in the existing $9/mo Premium tier (cost roughly matches Chirp3-HD, so unit economics stay intact). Gate v3 behind a per-episode upcharge (~$2-3/episode) using the existing `PRICE_ID_CREDIT_PACK` infra.

**Pros:**
- Keeps the $9 tier profitable.
- Two quality steps (Chirp3-HD ≈ Flash, v3 = best) gives users a reason to upgrade.
- Reuses existing credit-pack billing — lowest new-Stripe-work option.

**Cons:**
- Three voice quality tiers to explain (Standard / Chirp3-HD or Flash / v3) — UI complexity.
- Still need to handle quota tracking on the v3 upcharge to prevent abuse.
- Flash quality may not be perceptibly better than Chirp3-HD — diminishes the differentiation story.

### Option 3 — New "Studio" tier at $29/mo

Launch a third subscription tier. Hard character cap on ElevenLabs use (e.g., 150K chars/mo of v3 ≈ 6 standard episodes). Overage at metered cost or hard stop.

**Pros:**
- Cleanest revenue story. Premium ARPU jumps for Studio subscribers.
- Hard cap protects against runaway costs.
- Differentiated tier name and price anchors quality positioning.

**Cons:**
- Most work: new Stripe price, new tier in `AppConfig::Tiers`, new plan info, new UI for tier selection, character-cap enforcement specifically for ElevenLabs (separate from Google chars).
- Risks being a feature nobody upgrades for if the demand isn't there.
- Building for a hypothetical user instead of a measured one.

## Recommendation

**Ship Option 1 (BYOK) first. Decide on Option 2 vs Option 3 later, based on signal.**

Rationale:

1. **No demand evidence yet.** Current Chirp3-HD voices already rate well subjectively. Building a paid tier for unmeasured demand is the classic "interesting engineering problem ≠ valuable product feature" trap.
2. **BYOK is cheap to build, cheap to remove.** A weekend's work; deletes cleanly if usage is zero.
3. **It generates real data.** Number of users who add a key, average characters synthesized, which ElevenLabs voices they pick — all signals you'd otherwise be guessing at when designing Option 2 or 3.
4. **Architectural seams already support it.** `Voice::CATALOG` is the natural extension point for a `provider` field; `Tts::ApiClient` cleanly splits into provider adapters; the `Voice` model already gates voices by tier.

**Main tradeoff:** BYOK gates the feature to technical users willing to sign up for ElevenLabs themselves. If the hypothesis is "mainstream users will pay more for better voices," BYOK won't validate that — it'll only validate "power users want this." If you believe the mainstream-appeal hypothesis is the whole point, skip to Option 2 and price Flash inclusion accordingly.

## Architectural notes (for whichever option ships)

If/when implementing:

1. **Extend `Voice::CATALOG`** in `app/models/voice.rb` with a `provider` field (`:google` | `:elevenlabs`) and `elevenlabs_voice_id`. Existing entries stay on `:google`; new ones point to ElevenLabs IDs.
2. **Split `Tts::ApiClient`** into provider-specific adapters: `Tts::GoogleClient` (rename current) and `Tts::ElevenlabsClient`. A `Tts::Synthesizer` picks the adapter based on the `Voice` entry.
3. **`Tts::Config#voice_name` is currently a string with Google's naming convention** (`en-GB-Chirp3-HD-Enceladus`). When providers diverge, this becomes leaky — pass the `Voice` entry, not a raw string.
4. **Credentials** — `ELEVENLABS_API_KEY` for system-wide use (Options 2/3), or per-user encrypted key storage (Option 1).
5. **Sample audio** — `app/services/simulates/synthesizes_audio.rb` and the `voice_sample_url` helper need an MP3 per new voice in storage.
6. **Chunking** — `Tts::ChunkedSynthesizer` chunks at 850 bytes for Google's limits. ElevenLabs has different per-request caps (~5,000 chars for v3); chunking strategy may need provider-specific values.
7. **No Ruby gem dependency required.** ElevenLabs API is small enough that raw `Net::HTTP` or `Faraday` is cleaner than adding the `elevenlabs` gem.

## Next steps (if proceeding)

1. **Generate cost samples.** Pick 3–5 representative articles. Run them through ElevenLabs Flash, Multilingual v2, and v3. Record: actual cost, perceived quality vs Chirp3-HD, any issues with chunking or pronunciation. (Requires an ElevenLabs account — do this on Jesse's personal key first.)
2. **Decide on the demand question.** Ask current Premium users via in-app banner or email: "Would you pay $X more per month for higher-quality voices?" Even a tiny response sample beats guessing.
3. **If signal is positive:** ship Option 1 (BYOK). Measure for a month. Then decide Option 2 vs 3 based on uptake.
4. **If signal is negative or absent:** don't build. Revisit in 6 months.

## References

- `app/models/voice.rb` — current voice catalog
- `app/models/app_config.rb` — tier definitions and pricing constants
- `app/services/tts/api_client.rb` — Google TTS adapter (the natural place to split)
- `app/services/tts/chunked_synthesizer.rb` — chunking logic that will need provider-specific tuning
- `docs/tts-model-analysis.md` — prior analysis comparing Google models, includes ElevenLabs ELO benchmark
- ElevenLabs API docs: https://elevenlabs.io/docs/api-reference
- ElevenLabs pricing: https://elevenlabs.io/pricing
