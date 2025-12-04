# Voice Options Design

**Date:** 2025-12-04
**Status:** Approved

## Overview

Users can choose a voice for their TTS podcasts from a curated set. All tiers get 4 Standard voices; unlimited tier gets 4 additional Chirp3-HD voices. Selection is per-user via a settings page.

## Voices

| Name | Accent | Gender | Google Voice |
|------|--------|--------|--------------|
| **Wren** | British | Female | en-GB-Standard-C |
| **Felix** | British | Male | en-GB-Standard-D |
| **Sloane** | American | Female | en-US-Standard-C |
| **Archer** | American | Male | en-US-Standard-J |
| **Elara** | British | Female | en-GB-Chirp3-HD-Gacrux |
| **Callum** | British | Male | en-GB-Chirp3-HD-Enceladus |
| **Lark** | American | Female | en-US-Chirp3-HD-Callirrhoe |
| **Nash** | American | Male | en-US-Chirp3-HD-Charon |

**Tier access:**
- Free/Premium: Wren, Felix, Sloane, Archer
- Unlimited: All 8

## Data Model

### Migration

```ruby
add_column :users, :voice_preference, :string, null: true
```

### Voice Registry (Static Constant)

```ruby
# app/models/voice.rb
class Voice
  STANDARD = %w[wren felix sloane archer].freeze
  CHIRP = %w[elara callum lark nash].freeze
  ALL = (STANDARD + CHIRP).freeze

  BUCKET = ENV.fetch("GOOGLE_CLOUD_BUCKET")

  CATALOG = {
    "wren"    => { name: "Wren",    accent: "British",  gender: "Female", google_voice: "en-GB-Standard-C" },
    "felix"   => { name: "Felix",   accent: "British",  gender: "Male",   google_voice: "en-GB-Standard-D" },
    "sloane"  => { name: "Sloane",  accent: "American", gender: "Female", google_voice: "en-US-Standard-C" },
    "archer"  => { name: "Archer",  accent: "American", gender: "Male",   google_voice: "en-US-Standard-J" },
    "elara"   => { name: "Elara",   accent: "British",  gender: "Female", google_voice: "en-GB-Chirp3-HD-Gacrux" },
    "callum"  => { name: "Callum",  accent: "British",  gender: "Male",   google_voice: "en-GB-Chirp3-HD-Enceladus" },
    "lark"    => { name: "Lark",    accent: "American", gender: "Female", google_voice: "en-US-Chirp3-HD-Callirrhoe" },
    "nash"    => { name: "Nash",    accent: "American", gender: "Male",   google_voice: "en-US-Chirp3-HD-Charon" },
  }.freeze

  def self.for_tier(tier)
    tier == "unlimited" ? ALL : STANDARD
  end

  def self.sample_url(key)
    "https://storage.googleapis.com/#{BUCKET}/voices/#{key}.mp3"
  end

  def self.find(key)
    CATALOG[key]
  end
end
```

### User Model

```ruby
validates :voice_preference, inclusion: { in: Voice::ALL }, allow_nil: true

def voice
  return Voice.find(voice_preference)[:google_voice] if voice_preference.present?

  unlimited? ? "en-GB-Chirp3-HD-Enceladus" : "en-GB-Standard-D"
end

def available_voices
  Voice.for_tier(tier)
end
```

### Episode Model

```ruby
delegate :voice, to: :user
```

## Settings Page

### Routes

```ruby
resource :settings, only: [:show, :update]
```

### Controller

```ruby
class SettingsController < ApplicationController
  def show
    @voices = current_user.available_voices.map do |key|
      Voice.find(key).merge(key: key, sample_url: Voice.sample_url(key))
    end
    @selected_voice = current_user.voice_preference
  end

  def update
    if current_user.update(voice_preference: params[:voice])
      redirect_to settings_path, notice: "Settings saved."
    else
      redirect_to settings_path, alert: "Invalid voice selection."
    end
  end
end
```

### UI Layout (Radio Cards)

```
┌─────────────────────────────────────────────────────────────┐
│ Settings                                                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ Voice                                                       │
│ Choose the voice for your podcast episodes.                 │
│                                                             │
│ ┌───────────────────────────┐ ┌───────────────────────────┐ │
│ │ ◉ Wren                    │ │ ○ Felix                   │ │
│ │ British · Female          │ │ British · Male            │ │
│ │ [▶ Preview]               │ │ [▶ Preview]               │ │
│ └───────────────────────────┘ └───────────────────────────┘ │
│                                                             │
│ ┌───────────────────────────┐ ┌───────────────────────────┐ │
│ │ ○ Sloane                  │ │ ○ Archer                  │ │
│ │ American · Female         │ │ American · Male           │ │
│ │ [▶ Preview]               │ │ [▶ Preview]               │ │
│ └───────────────────────────┘ └───────────────────────────┘ │
│                                                             │
│ [Save Changes]                                              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### View

```erb
<%# app/views/settings/show.html.erb %>
<div class="max-w-2xl mx-auto">
  <h1 class="text-2xl font-semibold mb-8">Settings</h1>

  <%= render "shared/card", padding: "p-4 sm:p-8" do %>
    <%= form_with url: settings_path, method: :patch, class: "space-y-6" do %>
      <h2 class="text-lg font-medium">Voice</h2>
      <p class="text-[var(--color-subtext)] text-sm">Choose the voice for your podcast episodes.</p>

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <% @voices.each do |voice| %>
          <%= render "voice_card", voice: voice, selected: @selected_voice == voice[:key] %>
        <% end %>
      </div>

      <%= submit_tag "Save Changes", class: button_classes(type: :primary) %>
    <% end %>
  <% end %>
</div>
```

### Voice Card Partial

```erb
<%# app/views/settings/_voice_card.html.erb %>
<label class="relative block cursor-pointer">
  <input type="radio" name="voice" value="<%= voice[:key] %>"
         <%= "checked" if selected %>
         class="peer sr-only">

  <div class="border-2 rounded-lg p-4 transition-colors
              border-[var(--color-overlay0)] peer-checked:border-[var(--color-primary)]
              peer-checked:bg-[var(--color-primary)]/5">
    <div class="flex items-center justify-between mb-2">
      <span class="font-medium"><%= voice[:name] %></span>
      <div class="w-4 h-4 rounded-full border-2
                  border-[var(--color-overlay0)] peer-checked:border-[var(--color-primary)]
                  peer-checked:bg-[var(--color-primary)]"></div>
    </div>
    <p class="text-sm text-[var(--color-subtext)]">
      <%= voice[:accent] %> · <%= voice[:gender] %>
    </p>
    <button type="button"
            data-controller="audio-preview"
            data-audio-preview-url-value="<%= voice[:sample_url] %>"
            data-action="click->audio-preview#play"
            class="mt-3 text-sm text-[var(--color-primary)] hover:underline">
      ▶ Preview
    </button>
  </div>
</label>
```

## Audio Preview

### Stimulus Controller

```javascript
// app/javascript/controllers/audio_preview_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }

  play(event) {
    event.preventDefault()
    if (this.audio) this.audio.pause()
    this.audio = new Audio(this.urlValue)
    this.audio.play()
  }
}
```

### Sample Audio Files

Location in GCS:

```
gs://{bucket}/voices/
├── wren.mp3
├── felix.mp3
├── sloane.mp3
├── archer.mp3
├── elara.mp3
├── callum.mp3
├── lark.mp3
└── nash.mp3
```

Sample script (all voices read the same):

> "New research suggests that listening to articles can improve comprehension and retention, especially during commutes."

## Existing Code Changes

### UploadAndEnqueueEpisode

```ruby
voice_name: episode.voice
```

### Navigation

Add "Settings" link to header.

## Design Decisions

1. **Per-user setting** (not per-episode) – keeps UI simple while giving users control
2. **Static constant vs database table** – 8 curated voices that rarely change; no need for DB overhead
3. **String column with validation** (not enum) – readable in DB, flexible to add voices
4. **Pre-recorded audio samples** – instant feedback without API costs
5. **Same sample script for all voices** – enables direct comparison between voices
6. **Decoupled Standard/Chirp voices** – future-proofs against tier or availability changes
