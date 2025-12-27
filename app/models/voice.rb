# frozen_string_literal: true

class Voice
  STANDARD = %w[wren felix sloane archer].freeze
  CHIRP = %w[elara callum lark nash].freeze
  ALL = (STANDARD + CHIRP).freeze

  DEFAULT_STANDARD = "en-GB-Standard-D"
  DEFAULT_CHIRP = "en-GB-Chirp3-HD-Enceladus"

  CATALOG = {
    "wren"    => { name: "Wren",    accent: "British",  gender: "Female", google_voice: "en-GB-Standard-C" },
    "felix"   => { name: "Felix",   accent: "British",  gender: "Male",   google_voice: "en-GB-Standard-D" },
    "sloane"  => { name: "Sloane",  accent: "American", gender: "Female", google_voice: "en-US-Standard-C" },
    "archer"  => { name: "Archer",  accent: "American", gender: "Male",   google_voice: "en-US-Standard-J" },
    "elara"   => { name: "Elara",   accent: "British",  gender: "Female", google_voice: "en-GB-Chirp3-HD-Gacrux" },
    "callum"  => { name: "Callum",  accent: "British",  gender: "Male",   google_voice: "en-GB-Chirp3-HD-Enceladus" },
    "lark"    => { name: "Lark",    accent: "American", gender: "Female", google_voice: "en-US-Chirp3-HD-Callirrhoe" },
    "nash"    => { name: "Nash",    accent: "American", gender: "Male",   google_voice: "en-US-Chirp3-HD-Charon" }
  }.freeze

  def self.for_tier(tier)
    tier.to_s == "unlimited" ? ALL : STANDARD
  end

  def self.sample_url(key)
    bucket = ENV.fetch("GOOGLE_CLOUD_BUCKET", "verynormal-tts-podcast")
    "https://storage.googleapis.com/#{bucket}/voices/#{key}.mp3"
  end

  def self.find(key)
    CATALOG[key]
  end
end
