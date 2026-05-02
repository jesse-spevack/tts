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
    EPISODE_CHARACTER_LIMIT = 50_000
    FREE_MONTHLY_EPISODES = 2

    FREE_VOICES = %w[wren felix sloane archer gemma hugo quinn theo].freeze
    # ChirpHD voices — higher cost per character than Standard
    CHIRPHD_VOICES = %w[elara callum lark nash].freeze
    PREMIUM_VOICES = (FREE_VOICES + CHIRPHD_VOICES).freeze

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
    BUCKET = ENV.fetch("GOOGLE_CLOUD_BUCKET", "podread")
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
    WEBHOOK_SECRET = ENV.fetch("STRIPE_WEBHOOK_SECRET", "test_webhook_secret")
  end

  module Credits
    # PACKS is the authoritative source for pack sizes, prices, and Stripe
    # price IDs. Callers resolve a pack by size (checkout) or price_id
    # (webhook) rather than hard-coding any single pack.
    #
    # Stripe price IDs must be set via environment. In non-test environments
    # ENV.fetch raises on boot when a value is missing so a misconfigured
    # deploy fails loudly instead of silently sending garbage price IDs to
    # Stripe at checkout time. test_helper.rb sets these before Rails boots.
    PACKS = [
      {
        size: 5,
        price_cents: 999,
        stripe_price_id: ENV.fetch("STRIPE_PRICE_ID_CREDIT_PACK_5"),
        label: "Starter"
      }.freeze,
      {
        size: 10,
        price_cents: 1799,
        stripe_price_id: ENV.fetch("STRIPE_PRICE_ID_CREDIT_PACK_10"),
        label: "Standard"
      }.freeze,
      {
        size: 20,
        price_cents: 3299,
        stripe_price_id: ENV.fetch("STRIPE_PRICE_ID_CREDIT_PACK_20"),
        label: "Bulk"
      }.freeze
    ].freeze

    def self.find_pack_by_price_id(price_id)
      return nil if price_id.nil?
      PACKS.find { |pack| pack[:stripe_price_id] == price_id }
    end

    def self.find_pack_by_size(size)
      PACKS.find { |pack| pack[:size] == size }
    end
  end

  module Extension
    CHROME_WEB_STORE_URL = "https://chromewebstore.google.com/detail/podread-extension/icgbgfaelfomnobbkecaegeecjpdcdhd"
  end

  module Tts
    # Google Cloud TTS COGS per million input characters, in whole cents.
    # Standard: $4/M → 400¢. Chirp3-HD premium: $30/M → 3000¢.
    COST_CENTS_PER_MILLION = {
      "standard" => 400,
      "premium" => 3_000
    }.freeze
  end

  module Mpp
    SECRET_KEY = ENV.fetch("MPP_SECRET_KEY") { SecureRandom.hex(32) }
    # Tiered per-narration pricing, split by payment scheme. Tempo is on-chain
    # with near-zero per-tx cost; SPT (Stripe) bills 2.9% + $0.30 per redemption,
    # so SPT prices are bumped to absorb that fee. Standard vs Premium tiering
    # remains driven by Chirp3-HD COGS (~7.5× input cost vs Google Standard).
    PRICE_STANDARD_CENTS     = ENV.fetch("MPP_PRICE_STANDARD_CENTS", 75).to_i
    PRICE_PREMIUM_CENTS      = ENV.fetch("MPP_PRICE_PREMIUM_CENTS", 200).to_i
    SPT_PRICE_STANDARD_CENTS = ENV.fetch("MPP_SPT_PRICE_STANDARD_CENTS", 150).to_i
    SPT_PRICE_PREMIUM_CENTS  = ENV.fetch("MPP_SPT_PRICE_PREMIUM_CENTS", 250).to_i
    CURRENCY = ENV.fetch("MPP_CURRENCY", "usd")
    CHARACTER_LIMIT = 20_000
    CHALLENGE_TTL_SECONDS = ENV.fetch("MPP_CHALLENGE_TTL_SECONDS", 300).to_i
    # Tempo JSON-RPC endpoint. Mainnet (chain 4217) for production, Moderato
    # testnet (chain 42431) for every other Rails env. The RPC URL and the
    # TEMPO_CURRENCY_TOKEN contract MUST refer to the same chain — a testnet
    # RPC paired with a mainnet contract silently strands user payments
    # (agent-team-tv6e). Mpp::VerifiesChainId (wired in via the initializer
    # config/initializers/mpp_chain_id_guard.rb) fails boot on mismatch.
    # Explicit TEMPO_RPC_URL env var wins when set.
    TEMPO_RPC_URL = ENV.fetch("TEMPO_RPC_URL") do
      Rails.env.production? ? "https://rpc.tempo.xyz" : "https://rpc.moderato.tempo.xyz"
    end
    # pathUSD (0x20c0...0000) is Tempo's predeployed stablecoin used on the
    # Moderato testnet (the testnet faucet only dispenses pathUSD). USDC.e
    # (0x20c0...0000b9537d11c60e8b50) is USDC bridged via Stargate and is
    # Stripe's prod guidance for mainnet MPP traffic. The TEMPO_CURRENCY_TOKEN
    # env var determines which one is active — default stays pathUSD for
    # testnet safety; prod sets the USDC.e address in its deploy config.
    TEMPO_CURRENCY_TOKEN = ENV.fetch("TEMPO_CURRENCY_TOKEN", "0x20c0000000000000000000000000000000000000")
    # Decimals for the Tempo stablecoin. Both pathUSD and USDC.e use 6
    # decimals, confirmed by pympp (mpp/methods/tempo/intents.py) and
    # Stripe's machine-payments sample. On-chain Transfer event `data` is
    # in these base units, so we convert cents -> base units before comparing.
    TEMPO_TOKEN_DECIMALS = ENV.fetch("TEMPO_TOKEN_DECIMALS", 6).to_i
    # Timeouts for the Tempo JSON-RPC call. A slow or hung RPC must not
    # block a Rails thread indefinitely.
    TEMPO_RPC_OPEN_TIMEOUT_SECONDS = ENV.fetch("TEMPO_RPC_OPEN_TIMEOUT_SECONDS", 5).to_i
    TEMPO_RPC_READ_TIMEOUT_SECONDS = ENV.fetch("TEMPO_RPC_READ_TIMEOUT_SECONDS", 10).to_i
    # Pinned to the preview track while shared_payment_granted_token
    # is private-preview only.
    STRIPE_API_VERSION = ENV.fetch("STRIPE_API_VERSION", "2026-03-04.preview")
    # Merchant's Stripe Profile ID, advertised as networkId in
    # stripe-method 402 challenges. The placeholder default is safe for
    # issuance — mppx only validates presence/string-shape, and the SPT
    # carries merchant binding so we don't validate it server-side.
    STRIPE_NETWORK_ID = ENV.fetch("STRIPE_NETWORK_ID", "stripe_network_placeholder")
  end
end
