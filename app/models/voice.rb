# frozen_string_literal: true

class Voice
  Entry = Struct.new(:key, :name, :accent, :gender, :google_voice, :sample_url, keyword_init: true) do
    # :premium or :standard — drives MPP pricing and user-facing tier badges.
    # Premium maps to Chirp3-HD synthesis; Standard maps to Google Standard voices.
    def tier
      AppConfig::Tiers::CHIRPHD_VOICES.include?(key) ? :premium : :standard
    end

    def premium?
      tier == :premium
    end

    def standard?
      tier == :standard
    end

    # Backwards-compat alias. Prefer #premium?.
    alias_method :chirphd?, :premium?

    # MPP price for one narration with this voice, in cents.
    def price_cents
      case tier
      when :premium then AppConfig::Mpp::PRICE_PREMIUM_CENTS
      when :standard then AppConfig::Mpp::PRICE_STANDARD_CENTS
      end
    end
  end

  CATALOG = {
    "wren"    => { name: "Wren",    accent: "British",  gender: "Female", google_voice: "en-GB-Standard-C" },
    "felix"   => { name: "Felix",   accent: "British",  gender: "Male",   google_voice: "en-GB-Standard-D" },
    "sloane"  => { name: "Sloane",  accent: "American", gender: "Female", google_voice: "en-US-Standard-C" },
    "archer"  => { name: "Archer",  accent: "American", gender: "Male",   google_voice: "en-US-Standard-J" },
    "gemma"   => { name: "Gemma",   accent: "British",  gender: "Female", google_voice: "en-GB-Standard-A" },
    "hugo"    => { name: "Hugo",    accent: "British",  gender: "Male",   google_voice: "en-GB-Standard-B" },
    "quinn"   => { name: "Quinn",   accent: "American", gender: "Female", google_voice: "en-US-Standard-E" },
    "theo"    => { name: "Theo",    accent: "American", gender: "Male",   google_voice: "en-US-Standard-D" },
    "elara"   => { name: "Elara",   accent: "British",  gender: "Female", google_voice: "en-GB-Chirp3-HD-Gacrux" },
    "callum"  => { name: "Callum",  accent: "British",  gender: "Male",   google_voice: "en-GB-Chirp3-HD-Enceladus" },
    "lark"    => { name: "Lark",    accent: "American", gender: "Female", google_voice: "en-US-Chirp3-HD-Callirrhoe" },
    "nash"    => { name: "Nash",    accent: "American", gender: "Male",   google_voice: "en-US-Chirp3-HD-Charon" }
  }.freeze

  ALL = CATALOG.keys.freeze

  # Catalog default used by ResolvesVoice when no voice is requested AND
  # no user preference applies. Flipped from 'callum' (Premium) to 'felix'
  # (Standard) per agent-team-0g5 research — casual callers who omit
  # voice should land on the cheaper tier by default.
  DEFAULT_KEY = "felix"

  DEFAULT_STANDARD = "en-GB-Standard-D"
  DEFAULT_CHIRP = "en-GB-Chirp3-HD-Enceladus"

  def self.find(key)
    data = CATALOG[key]
    return nil unless data

    Entry.new(key: key, sample_url: sample_url(key), **data)
  end

  # Reverse lookup: resolve tier (:premium / :standard) from a google voice
  # string (e.g. "en-GB-Chirp3-HD-Enceladus"). Returns nil if the string is
  # not in the catalog. Used by Episode-level tier display where we stamp
  # the google voice on the episode at synth time.
  #
  # Emits a structured warning when a non-blank google_voice misses the
  # catalog — that's a drift/rename signal worth surfacing, since the
  # caller's `||= :standard` fallback would otherwise silently mislabel
  # a premium voice as Standard. Blank input is the normal "not stamped
  # yet" path and stays silent.
  def self.tier_for(google_voice)
    return nil if google_voice.blank?

    tier = tier_by_google_voice[google_voice]
    unless tier
      Rails.logger.warn "event=voice_tier_lookup_missed google_voice=#{google_voice}"
      return nil
    end

    tier
  end

  # Memoized reverse index: google_voice string → tier symbol. Built once
  # from CATALOG and frozen. In dev mode Rails reloads the Voice constant
  # so the memo resets with the catalog.
  def self.tier_by_google_voice
    @tier_by_google_voice ||= CATALOG.each_with_object({}) do |(key, _data), h|
      entry = find(key)
      h[entry.google_voice] = entry.tier if entry
    end.freeze
  end

  def self.sample_url(key)
    AppConfig::Storage.voice_sample_url(key)
  end

  def self.google_voice_for(preference, is_premium:)
    if preference.present?
      voice = find(preference)
      return voice.google_voice if voice
    end
    is_premium ? DEFAULT_CHIRP : DEFAULT_STANDARD
  end
end
