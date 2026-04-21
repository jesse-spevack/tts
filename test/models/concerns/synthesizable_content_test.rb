# frozen_string_literal: true

require "test_helper"

# Shared contract test for SynthesizableContent (agent-team-bzo6, epic
# agent-team-sird). The concern defines the minimal 9-method interface
# shared by Episode and Narration; this test pins each method against
# BOTH real consumers so the interface can't drift between them.
#
# Pattern: a module with Minitest test methods, included into two
# TestCase subclasses. Each subclass supplies a #build_content helper
# and (optionally) overrides which fixtures it uses. This keeps every
# assertion run twice — once for Episode, once for Narration — while
# letting each subclass handle its own setup quirks (Episode needs a
# user + podcast; Narration needs an mpp_payment).
#
# All tests MUST fail until the concern is created and both models
# include it. Acceptable failure modes:
#   - NameError: uninitialized constant SynthesizableContent
#   - NoMethodError on #source_text / #voice / #provider / #succeed! /
#     #fail! / #cost / #tts_usage / #mpp_payment
#   - Type mismatch (e.g. #voice returning a raw string instead of a
#     Voice::Entry, once the concern starts normalizing that)
module SynthesizableContentContract
  # ---------------------------------------------------------------------------
  # Interface: each method exists and the concern is included
  # ---------------------------------------------------------------------------

  def test_content_class_includes_synthesizable_content_concern
    assert_includes content_class.included_modules, SynthesizableContent,
      "#{content_class} must include SynthesizableContent"
  end

  def test_source_text_returns_a_string
    # 120 chars — safely above the 100-char MIN_LENGTH validator on Episode.
    text = "H" * 120
    content = build_content(source_text: text)
    assert_kind_of String, content.source_text
    assert_equal text, content.source_text
  end

  def test_voice_returns_a_non_blank_identifier
    content = build_content
    voice = content.voice
    # Voice may be a Voice::Entry, a google_voice string, or a catalog key —
    # the contract pins only that it's present. Implementer picks the shape.
    assert voice.present?, "#{content_class}#voice must return a non-blank value"
  end

  def test_provider_returns_a_symbol_or_string
    content = build_content
    provider = content.provider
    assert provider.is_a?(Symbol) || provider.is_a?(String),
      "#{content_class}#provider must return a Symbol or String, got #{provider.class}"
    assert provider.to_s.present?, "#{content_class}#provider must not be blank"
  end

  def test_status_returns_a_string_matching_the_models_enum
    content = build_content
    assert_kind_of String, content.status
    assert_includes %w[pending preparing processing complete failed], content.status
  end

  def test_tts_usage_returns_nil_when_no_usage_recorded
    content = build_content
    assert_nil content.tts_usage,
      "fresh #{content_class} should have no tts_usage until RecordsTtsUsage runs"
  end

  def test_tts_usage_returns_the_polymorphic_record_when_present
    content = build_content
    usage = TtsUsage.create!(
      usable: content,
      provider: "google",
      voice_id: "en-GB-Standard-D",
      voice_tier: "standard",
      character_count: 100,
      cost_cents: 1,
      source: "actual"
    )
    assert_equal usage, content.reload.tts_usage
  end

  def test_mpp_payment_is_optional_and_returns_nil_when_absent
    content = build_content_without_mpp_payment
    return skip("#{content_class} requires mpp_payment") if content.nil?

    assert_nil content.mpp_payment,
      "content without MPP payment should have #mpp_payment == nil"
  end

  def test_mpp_payment_returns_the_payment_when_present
    content = build_content_with_mpp_payment
    assert_not_nil content.mpp_payment
    assert_kind_of MppPayment, content.mpp_payment
  end

  # ---------------------------------------------------------------------------
  # Lifecycle: succeed!(audio_blob:, duration:) / fail!(reason:)
  # ---------------------------------------------------------------------------

  def test_succeed_bang_transitions_status_to_terminal_success_state
    content = build_content
    content.succeed!(audio_blob: "\x00\x01\x02fake mp3 bytes", duration: 42)
    content.reload
    # Existing enum uses "complete" for the terminal success state. If the
    # concern renames to "succeeded", update both models + this assertion
    # together (migration required).
    assert_equal "complete", content.status,
      "#succeed! must transition status to the terminal success state"
  end

  def test_succeed_bang_records_duration
    content = build_content
    content.succeed!(audio_blob: "\x00\x01\x02fake mp3 bytes", duration: 123)
    content.reload
    assert_equal 123, content.duration_seconds,
      "#succeed! must persist the supplied duration"
  end

  def test_succeed_bang_records_audio_size_from_blob
    blob = "\x00\x01\x02\x03fake mp3 bytes for size tracking"
    content = build_content
    content.succeed!(audio_blob: blob, duration: 10)
    content.reload
    assert_equal blob.bytesize, content.audio_size_bytes,
      "#succeed! must record audio_size_bytes from the blob"
  end

  def test_fail_bang_transitions_status_to_failed
    content = build_content
    content.fail!(reason: "synthesis exploded")
    content.reload
    assert_equal "failed", content.status
  end

  def test_fail_bang_stores_reason_in_error_message
    content = build_content
    content.fail!(reason: "tts provider 500")
    content.reload
    assert_equal "tts provider 500", content.error_message,
      "#fail! must persist the reason on the content row"
  end

  # ---------------------------------------------------------------------------
  # #cost — value object, not persisted (brick 3 makes it persisted)
  # ---------------------------------------------------------------------------

  def test_cost_returns_a_value_object_with_a_numeric_amount
    content = build_content
    cost = content.cost
    # Intentionally loose: implementer can return a Money, a Struct, a plain
    # Integer cents, or a dedicated EpisodeCost value object. The pin is
    # "non-nil, responds to some amount method, does NOT touch a persisted
    # cost column". Brick 3 (agent-team-7i24) makes it persisted.
    assert_not_nil cost, "#cost must not be nil"

    has_amount = cost.respond_to?(:cents) ||
                 cost.respond_to?(:amount) ||
                 cost.respond_to?(:to_i) ||
                 cost.is_a?(Numeric)
    assert has_amount,
      "#cost should expose a numeric amount (via #cents, #amount, #to_i, or be Numeric); got #{cost.class}"
  end

  def test_cost_is_not_persisted_in_brick_2b
    # Brick 3 adds a cost_cents column. Until then, calling #cost must not
    # trigger a write.
    content = build_content
    assert_no_difference -> { content.class.where(id: content.id).pick(:updated_at) } do
      content.cost
    end
  end
end

# ---------------------------------------------------------------------------
# Episode runner
# ---------------------------------------------------------------------------

class Episode::SynthesizableContentTest < ActiveSupport::TestCase
  include SynthesizableContentContract

  def content_class
    Episode
  end

  def build_content(source_text: "A" * 120 + " — default episode text for contract test.")
    Episode.create!(
      podcast: podcasts(:one),
      user: users(:one),
      title: "Contract Test Episode",
      author: "Contract Author",
      description: "An episode created inside the SynthesizableContent shared contract test.",
      source_type: :paste,
      source_text: source_text,
      status: :processing
    )
  end

  def build_content_without_mpp_payment
    # Episodes typically have no MPP payment (credit / free tier).
    build_content
  end

  def build_content_with_mpp_payment
    episode = build_content
    episode.update!(mpp_payment: mpp_payments(:completed))
    episode
  end
end

# ---------------------------------------------------------------------------
# Narration runner
# ---------------------------------------------------------------------------

class Narration::SynthesizableContentTest < ActiveSupport::TestCase
  include SynthesizableContentContract

  def content_class
    Narration
  end

  def build_content(source_text: "Default narration text for contract test, padded to meet length.")
    # Fresh MppPayment per call — `narrations.mpp_payment_id` is UNIQUE, so
    # reusing a fixture would collide with other narration fixtures that
    # already claim `completed_for_narration` et al.
    payment = MppPayment.create!(
      amount_cents: 150,
      currency: "usd",
      status: "completed",
      stripe_payment_intent_id: "pi_test_narration_contract_#{SecureRandom.hex(4)}",
      tx_hash: "0x#{SecureRandom.hex(16)}",
      user: users(:one)
    )
    Narration.create!(
      title: "Contract Test Narration",
      author: "Contract Author",
      description: "A narration created inside the SynthesizableContent shared contract test.",
      source_type: :text,
      source_text: source_text,
      status: :processing,
      voice: "en-GB-Standard-D",
      expires_at: 24.hours.from_now,
      mpp_payment: payment
    )
  end

  def build_content_without_mpp_payment
    # Narration requires mpp_payment (belongs_to, non-optional). Skip that
    # assertion on the Narration runner — it's Episode-only semantics.
    nil
  end

  def build_content_with_mpp_payment
    build_content
  end
end
