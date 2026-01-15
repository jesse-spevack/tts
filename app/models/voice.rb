# frozen_string_literal: true

class Voice
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

  DEFAULT_STANDARD = "en-GB-Standard-D"
  DEFAULT_CHIRP = "en-GB-Chirp3-HD-Enceladus"

  def self.sample_url(key)
    AppConfig::Storage.voice_sample_url(key)
  end

  def self.find(key)
    CATALOG[key]
  end

  def self.google_voice_for(preference, is_unlimited:)
    if preference.present?
      voice_data = find(preference)
      return voice_data[:google_voice] if voice_data
    end
    is_unlimited ? DEFAULT_CHIRP : DEFAULT_STANDARD
  end
end
