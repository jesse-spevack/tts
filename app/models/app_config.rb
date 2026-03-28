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
      "www.seangoedecke.com" => "Sean Goedecke",
      "seangoedecke.com" => "Sean Goedecke"
    }.freeze

    def self.known_author_for_url(url)
      host = URI.parse(url).host&.downcase
      KNOWN_AUTHORS[host]
    rescue URI::InvalidURIError
      nil
    end
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
  end

  module Credits
    PACK_SIZE = 5
    PACK_PRICE_DISPLAY = "$4.99"
    PER_EPISODE_DISPLAY = "$1.00"
  end

  module Extension
    CHROME_WEB_STORE_URL = "https://chromewebstore.google.com/detail/podread-extension/icgbgfaelfomnobbkecaegeecjpdcdhd"
  end
end
