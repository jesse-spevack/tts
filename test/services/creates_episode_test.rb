# frozen_string_literal: true

require "test_helper"

# Facade over the per-source Creates{Url,Paste,File,Extension}Episode services.
# The facade is responsible for:
#   1. Dispatching to the right per-source creator based on a normalized
#      source_type ("url", "text", "file", "extension").
#   2. Running post-create side effects (RecordsEpisodeUsage +
#      DebitsEpisodeCredit) exactly once, only on success, in that order.
#   3. Returning the per-source creator's Result unchanged on success, and
#      returning a failure Result on unknown source_type.
#
# Callers (HTML and API controllers) handle HTTP-shaped params and normalize
# them into the facade's source_type + params hash before calling in.
class CreatesEpisodeTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @podcast = podcasts(:one)
    @episode = episodes(:one)

    Mocktail.replace(CreatesUrlEpisode)
    Mocktail.replace(CreatesPasteEpisode)
    Mocktail.replace(CreatesFileEpisode)
    Mocktail.replace(CreatesExtensionEpisode)
    Mocktail.replace(RecordsEpisodeUsage)
    Mocktail.replace(DebitsEpisodeCredit)
  end

  # --- Dispatch ------------------------------------------------------------

  test "dispatches 'url' source_type to CreatesUrlEpisode and returns its Result" do
    success = Result.success(@episode)
    stubs { |_m| CreatesUrlEpisode.call(podcast: @podcast, user: @user, url: "https://example.com/a") }.with { success }

    result = CreatesEpisode.call(
      user: @user,
      podcast: @podcast,
      source_type: "url",
      params: { url: "https://example.com/a" },
      cost_in_credits: 1
    )

    assert_same success, result
    verify { |_m| CreatesUrlEpisode.call(podcast: @podcast, user: @user, url: "https://example.com/a") }
  end

  test "dispatches 'text' source_type to CreatesPasteEpisode with all paste args" do
    success = Result.success(@episode)
    stubs do |_m|
      CreatesPasteEpisode.call(
        podcast: @podcast,
        user: @user,
        text: "long text body",
        title: "My Title",
        author: "Jane",
        source_url: "https://example.com/src"
      )
    end.with { success }

    result = CreatesEpisode.call(
      user: @user,
      podcast: @podcast,
      source_type: "text",
      params: {
        text: "long text body",
        title: "My Title",
        author: "Jane",
        source_url: "https://example.com/src"
      },
      cost_in_credits: 1
    )

    assert_same success, result
  end

  test "dispatches 'text' without source_url when not provided" do
    success = Result.success(@episode)
    stubs do |_m|
      CreatesPasteEpisode.call(
        podcast: @podcast,
        user: @user,
        text: "long text body",
        title: nil,
        author: nil,
        source_url: nil
      )
    end.with { success }

    result = CreatesEpisode.call(
      user: @user,
      podcast: @podcast,
      source_type: "text",
      params: { text: "long text body" },
      cost_in_credits: 1
    )

    assert result.success?
  end

  test "dispatches 'file' source_type to CreatesFileEpisode" do
    success = Result.success(@episode)
    stubs do |_m|
      CreatesFileEpisode.call(
        podcast: @podcast,
        user: @user,
        title: "Title",
        author: "Author",
        description: "Desc",
        content: "file body"
      )
    end.with { success }

    result = CreatesEpisode.call(
      user: @user,
      podcast: @podcast,
      source_type: "file",
      params: { title: "Title", author: "Author", description: "Desc", content: "file body" },
      cost_in_credits: 1
    )

    assert result.success?
    verify do |_m|
      CreatesFileEpisode.call(
        podcast: @podcast,
        user: @user,
        title: "Title",
        author: "Author",
        description: "Desc",
        content: "file body"
      )
    end
  end

  test "dispatches 'extension' source_type to CreatesExtensionEpisode" do
    success = Result.success(@episode)
    stubs do |_m|
      CreatesExtensionEpisode.call(
        podcast: @podcast,
        user: @user,
        title: "Extension Title",
        content: "extension body",
        url: "https://example.com/ext",
        author: "Author",
        description: "Desc"
      )
    end.with { success }

    result = CreatesEpisode.call(
      user: @user,
      podcast: @podcast,
      source_type: "extension",
      params: {
        title: "Extension Title",
        content: "extension body",
        url: "https://example.com/ext",
        author: "Author",
        description: "Desc"
      },
      cost_in_credits: 1
    )

    assert result.success?
  end

  test "returns failure Result for unknown source_type" do
    result = CreatesEpisode.call(
      user: @user,
      podcast: @podcast,
      source_type: "bogus",
      params: {},
      cost_in_credits: 1
    )

    assert result.failure?
    assert_match(/source_type/i, result.error)
  end

  test "returns failure Result for nil source_type" do
    result = CreatesEpisode.call(
      user: @user,
      podcast: @podcast,
      source_type: nil,
      params: {},
      cost_in_credits: 1
    )

    assert result.failure?
  end

  # --- Side effects on success --------------------------------------------

  test "on success, calls RecordsEpisodeUsage once" do
    stubs { |_m| CreatesUrlEpisode.call(podcast: @podcast, user: @user, url: "https://example.com/a") }
      .with { Result.success(@episode) }

    CreatesEpisode.call(
      user: @user,
      podcast: @podcast,
      source_type: "url",
      params: { url: "https://example.com/a" },
      cost_in_credits: 1
    )

    assert_nil verify(times: 1) { RecordsEpisodeUsage.call(user: @user) }
  end

  test "on success, calls DebitsEpisodeCredit once with returned episode and cost_in_credits" do
    stubs { |_m| CreatesUrlEpisode.call(podcast: @podcast, user: @user, url: "https://example.com/a") }
      .with { Result.success(@episode) }

    CreatesEpisode.call(
      user: @user,
      podcast: @podcast,
      source_type: "url",
      params: { url: "https://example.com/a" },
      cost_in_credits: 3
    )

    assert_nil verify(times: 1) { DebitsEpisodeCredit.call(user: @user, episode: @episode, cost_in_credits: 3) }
  end

  test "records usage BEFORE debiting credit" do
    stubs { |_m| CreatesUrlEpisode.call(podcast: @podcast, user: @user, url: "https://example.com/a") }
      .with { Result.success(@episode) }

    call_order = []
    stubs { |_m| RecordsEpisodeUsage.call(user: @user) }.with { call_order << :usage }
    stubs { |_m| DebitsEpisodeCredit.call(user: @user, episode: @episode, cost_in_credits: 1) }.with { call_order << :debit }

    CreatesEpisode.call(
      user: @user,
      podcast: @podcast,
      source_type: "url",
      params: { url: "https://example.com/a" },
      cost_in_credits: 1
    )

    assert_equal [ :usage, :debit ], call_order
  end

  # --- Side effects NOT run on failure ------------------------------------

  test "on per-source creator failure, does NOT call RecordsEpisodeUsage or DebitsEpisodeCredit" do
    failure = Result.failure("Content cannot be empty")
    stubs { |_m| CreatesPasteEpisode.call(podcast: @podcast, user: @user, text: "", title: nil, author: nil, source_url: nil) }
      .with { failure }

    result = CreatesEpisode.call(
      user: @user,
      podcast: @podcast,
      source_type: "text",
      params: { text: "" },
      cost_in_credits: 1
    )

    assert_same failure, result
    verify(times: 0) { |m| RecordsEpisodeUsage.call(user: m.any) }
    verify(times: 0) { |m| DebitsEpisodeCredit.call(user: m.any, episode: m.any, cost_in_credits: m.numeric) }
  end

  test "on unknown source_type, does NOT call side effects" do
    result = CreatesEpisode.call(
      user: @user,
      podcast: @podcast,
      source_type: "bogus",
      params: {},
      cost_in_credits: 1
    )

    assert result.failure?
    assert_nil verify(times: 0) { |m| RecordsEpisodeUsage.call(user: m.any) }
    assert_nil verify(times: 0) { |m| DebitsEpisodeCredit.call(user: m.any, episode: m.any, cost_in_credits: m.numeric) }
  end
end
