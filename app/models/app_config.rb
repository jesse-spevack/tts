# frozen_string_literal: true

class AppConfig
  module Domain
    HOST = ENV.fetch("APP_HOST", "localhost:3000")
    BASE_URL = "https://#{HOST}".freeze
    # Strip port for email domain — email addresses never include ports
    # Note: config/application.rb has a parallel definition for email_ingest_domain
    # that also strips ports, since it loads before autoloading makes this available
    MAIL_FROM = ENV.fetch("MAILER_FROM_ADDRESS", "noreply@#{HOST.sub(/:\d+\z/, "")}")
  end

  module Tiers
    FREE_CHARACTER_LIMIT = 15_000
    PREMIUM_CHARACTER_LIMIT = 50_000
    FREE_MONTHLY_EPISODES = 2

    FREE_VOICES = %w[wren felix sloane archer gemma hugo quinn theo].freeze
    # ChirpHD voices — higher cost per character than Standard
    CHIRPHD_VOICES = %w[elara callum lark nash].freeze
    PREMIUM_VOICES = (FREE_VOICES + CHIRPHD_VOICES).freeze

    def self.character_limit_for(tier)
      case tier.to_s
      when "free" then FREE_CHARACTER_LIMIT
      when "premium" then PREMIUM_CHARACTER_LIMIT
      when "unlimited" then nil
      end
    end

    def self.voices_for(tier)
      case tier.to_s
      when "free" then FREE_VOICES
      when "premium", "unlimited" then PREMIUM_VOICES
      end
    end
  end

  module Api
    DEFAULT_PER_PAGE = 20
    MAX_PER_PAGE = 100
  end

  module Content
    MIN_LENGTH = 100
    MAX_FETCH_BYTES = 10 * 1024 * 1024  # 10MB
    LOW_QUALITY_EXTRACTION_CHARS = 500
    LOW_QUALITY_HTML_MIN_BYTES = 10_000
    JINA_READER_BASE_URL = "https://r.jina.ai"

    KNOWN_AUTHORS = {
      "seangoedecke.com" => "Sean Goedecke"
    }.freeze
  end

  module Llm
    MAX_TITLE_LENGTH = 255
    MAX_AUTHOR_LENGTH = 255
    MAX_DESCRIPTION_LENGTH = 1000
  end

  module Network
    TIMEOUT_SECONDS = 10
    DNS_TIMEOUT_SECONDS = 5
  end

  module Storage
    BUCKET = ENV.fetch("GOOGLE_CLOUD_BUCKET", "verynormal-tts-podcast")
    BASE_URL = "https://storage.googleapis.com/#{BUCKET}".freeze
    SIGNED_URL_EXPIRY_SECONDS = 300  # 5 minutes

    def self.bucket
      BUCKET
    end

    def self.episode_audio_url(podcast_id, gcs_episode_id)
      "#{BASE_URL}/podcasts/#{podcast_id}/episodes/#{gcs_episode_id}.mp3"
    end

    def self.feed_url(podcast_id)
      "#{BASE_URL}/podcasts/#{podcast_id}/feed.xml"
    end

    def self.public_feed_url(podcast_id)
      "#{AppConfig::Domain::BASE_URL}/feeds/#{podcast_id}.xml"
    end

    def self.voice_sample_url(voice_key)
      "#{BASE_URL}/voices/#{voice_key}.mp3"
    end
  end

  module Stripe
    PRICE_ID_MONTHLY = ENV.fetch("STRIPE_PRICE_ID_MONTHLY", "test_price_monthly")
    PRICE_ID_ANNUAL = ENV.fetch("STRIPE_PRICE_ID_ANNUAL", "test_price_annual")
    PRICE_ID_CREDIT_PACK = ENV.fetch("STRIPE_PRICE_ID_CREDIT_PACK", "test_price_credit_pack")
    WEBHOOK_SECRET = ENV.fetch("STRIPE_WEBHOOK_SECRET", "test_webhook_secret")

    PLAN_INFO = {
      PRICE_ID_MONTHLY => { name: "Premium Monthly", amount_cents: 900, display: "$9/mo" },
      PRICE_ID_ANNUAL => { name: "Premium Annual", amount_cents: 8900, display: "$89/yr" }
    }.freeze
  end

  module Credits
    PACK_SIZE = 5
    PACK_PRICE_DISPLAY = "$4.99"
    PER_EPISODE_DISPLAY = "$1.00"
  end

  module Extension
    CHROME_WEB_STORE_URL = "https://chromewebstore.google.com/detail/podread-extension/icgbgfaelfomnobbkecaegeecjpdcdhd"
  end

  module Mpp
    SECRET_KEY = ENV.fetch("MPP_SECRET_KEY") { SecureRandom.hex(32) }
    # Tiered per-narration pricing. Standard voices use Google TTS Standard
    # ($4/M chars COGS); Premium voices use Chirp3-HD ($30/M chars COGS) —
    # 7.5× delta on the biggest input cost line justifies a split.
    # See agent-team-0g5 for the full cost model.
    PRICE_STANDARD_CENTS = ENV.fetch("MPP_PRICE_STANDARD_CENTS", 75).to_i
    PRICE_PREMIUM_CENTS = ENV.fetch("MPP_PRICE_PREMIUM_CENTS", 100).to_i
    # Legacy flat price — retained for any call site not yet migrated to
    # per-tier pricing. Removed once agent-team-nkz.4 (tier-aware challenge
    # generation) lands and all call sites use Voice#price_cents instead.
    PRICE_CENTS = ENV.fetch("MPP_PRICE_CENTS", 100).to_i
    CURRENCY = ENV.fetch("MPP_CURRENCY", "usd")
    CHARACTER_LIMIT = 20_000
    CHALLENGE_TTL_SECONDS = ENV.fetch("MPP_CHALLENGE_TTL_SECONDS", 300).to_i
    TEMPO_RPC_URL = ENV.fetch("TEMPO_RPC_URL", "https://rpc.testnet.tempo.xyz")
    TEMPO_CURRENCY_TOKEN = ENV.fetch("TEMPO_CURRENCY_TOKEN", "0x20c0000000000000000000000000000000000000")
    # Decimals for the Tempo stablecoin (pathUSD / USDC). Confirmed by pympp
    # (mpp/methods/tempo/intents.py) and Stripe's machine-payments sample,
    # both of which hardcode 6. On-chain Transfer event `data` is in these
    # base units, so we convert cents -> base units before comparing.
    TEMPO_TOKEN_DECIMALS = ENV.fetch("TEMPO_TOKEN_DECIMALS", 6).to_i
    # Timeouts for the Tempo JSON-RPC call. A slow or hung RPC must not
    # block a Rails thread indefinitely.
    TEMPO_RPC_OPEN_TIMEOUT_SECONDS = ENV.fetch("TEMPO_RPC_OPEN_TIMEOUT_SECONDS", 5).to_i
    TEMPO_RPC_READ_TIMEOUT_SECONDS = ENV.fetch("TEMPO_RPC_READ_TIMEOUT_SECONDS", 10).to_i
    # Stripe API version for crypto PaymentIntent endpoints. Must stay
    # on the preview track while Machine Payments Protocol support is
    # gated there.
    STRIPE_API_VERSION = ENV.fetch("MPP_STRIPE_API_VERSION", "2026-03-04.preview")
  end
end
