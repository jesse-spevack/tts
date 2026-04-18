# frozen_string_literal: true

require "test_helper"

class Mpp::CreatesNarrationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @mpp_payment = mpp_payments(:one)
  end

  test "creates a url narration and enqueues processing job" do
    params = { source_type: "url", url: "https://example.com/article", title: "Headline" }

    assert_enqueued_with(job: ProcessesNarrationJob) do
      result = Mpp::CreatesNarration.call(mpp_payment: @mpp_payment, params: params)

      assert result.success?
      narration = result.data
      assert narration.persisted?
      assert narration.url?
      assert_equal "https://example.com/article", narration.source_url
      assert_equal "Headline", narration.title
      assert_equal @mpp_payment, narration.mpp_payment
    end
  end

  test "creates a text narration from text param" do
    params = { source_type: "text", text: "Article body content", title: "Piece" }

    result = Mpp::CreatesNarration.call(mpp_payment: @mpp_payment, params: params)

    assert result.success?
    assert result.data.text?
    assert_equal "Article body content", result.data.source_text
  end

  test "creates a text narration from content param (extension source_type)" do
    params = { source_type: "extension", content: "Extracted page content", title: "Page" }

    result = Mpp::CreatesNarration.call(mpp_payment: @mpp_payment, params: params)

    assert result.success?
    assert result.data.text?
    assert_equal "Extracted page content", result.data.source_text
  end

  test "defaults title to Untitled when missing" do
    params = { source_type: "text", text: "body" }

    result = Mpp::CreatesNarration.call(mpp_payment: @mpp_payment, params: params)

    assert_equal "Untitled", result.data.title
  end

  test "sets expires_at approximately 24 hours from now" do
    params = { source_type: "text", text: "body" }

    freeze_time do
      result = Mpp::CreatesNarration.call(mpp_payment: @mpp_payment, params: params)
      assert_in_delta 24.hours.from_now, result.data.expires_at, 1.second
    end
  end
end
