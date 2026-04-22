require "test_helper"

class EpisodesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(account_type: :unlimited)
    sign_in_as(@user)
  end

  test "should get index" do
    get episodes_url
    assert_response :success
  end

  test "should get new" do
    get new_episode_url
    assert_response :success
  end

  test "should create episode" do
    long_content = "# Test Content\n\n" + ("This is test markdown content. " * 10)
    file = Rack::Test::UploadedFile.new(
      StringIO.new(long_content),
      "text/markdown",
      original_filename: "test.md"
    )

    assert_enqueued_with(job: ProcessesFileEpisodeJob) do
      post episodes_url, params: {
        episode: {
          title: "Test Episode",
          author: "Test Author",
          description: "Test Description",
          content: file
        }
      }
    end

    assert_redirected_to episodes_path
  end

  test "should render new on validation failure" do
    file = Rack::Test::UploadedFile.new(
      StringIO.new(""),
      "text/markdown",
      original_filename: "test.md"
    )

    post episodes_url, params: {
      episode: {
        title: "Test",
        author: "Author",
        description: "Desc",
        content: file
      }
    }

    assert_response :unprocessable_entity
  end

  test "should show error when no file uploaded" do
    post episodes_url, params: {
      episode: {
        title: "Test Episode",
        author: "Test Author",
        description: "Test Description",
        content: nil
      }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "Content cannot be empty"
  end

  test "unlimited tier users can create episodes" do
    sign_in_as users(:unlimited_user)

    long_content = "# Test Content\n\n" + ("This is test markdown content. " * 10)
    file = Rack::Test::UploadedFile.new(
      StringIO.new(long_content),
      "text/markdown",
      original_filename: "test.md"
    )

    assert_enqueued_with(job: ProcessesFileEpisodeJob) do
      post episodes_url, params: {
        episode: {
          title: "Test Episode",
          author: "Test Author",
          description: "Test Description",
          content: file
        }
      }
    end

    assert_redirected_to episodes_path
  end

  test "allows free tier user to access new when under limit" do
    sign_in_as users(:free_user)

    get new_episode_url

    assert_response :success
  end

  test "redirects free tier user from new when at monthly limit" do
    free_user = users(:free_user)
    sign_in_as free_user

    EpisodeUsage.create!(
      user: free_user,
      period_start: Time.current.beginning_of_month.to_date,
      episode_count: 2
    )

    get new_episode_url

    assert_redirected_to episodes_path
    assert_includes flash[:alert], "You've used your 2 free episodes this month"
  end

  test "allows free tier user to create when under limit" do
    free_user = users(:free_user)
    sign_in_as free_user

    long_content = "# Test Content\n\n" + ("This is test markdown content. " * 10)
    file = Rack::Test::UploadedFile.new(
      StringIO.new(long_content),
      "text/markdown",
      original_filename: "test.md"
    )

    assert_enqueued_with(job: ProcessesFileEpisodeJob) do
      post episodes_url, params: {
        episode: { title: "Test", author: "A", description: "D", content: file }
      }
    end

    assert_redirected_to episodes_path
  end

  test "redirects free tier user from create when at monthly limit" do
    free_user = users(:free_user)
    sign_in_as free_user

    EpisodeUsage.create!(
      user: free_user,
      period_start: Time.current.beginning_of_month.to_date,
      episode_count: 2
    )

    long_content = "# Test Content\n\n" + ("This is test markdown content. " * 10)
    file = Rack::Test::UploadedFile.new(
      StringIO.new(long_content),
      "text/markdown",
      original_filename: "test.md"
    )

    post episodes_url, params: {
      episode: { title: "Test", author: "A", description: "D", content: file }
    }

    assert_redirected_to episodes_path
    assert_includes flash[:alert], "You've used your 2 free episodes this month"
  end

  test "records usage after successful submission for free tier user" do
    free_user = users(:free_user)
    sign_in_as free_user

    long_content = "# Test Content\n\n" + ("This is test markdown content. " * 10)
    file = Rack::Test::UploadedFile.new(
      StringIO.new(long_content),
      "text/markdown",
      original_filename: "test.md"
    )

    assert_difference "EpisodeUsage.count", 1 do
      post episodes_url, params: {
        episode: { title: "Test", author: "A", description: "D", content: file }
      }
    end

    usage = EpisodeUsage.current_for(free_user)
    assert_equal 1, usage.episode_count
  end

  test "does not record usage for non-free tier user" do
    sign_in_as users(:unlimited_user)

    long_content = "# Test Content\n\n" + ("This is test markdown content. " * 10)
    file = Rack::Test::UploadedFile.new(
      StringIO.new(long_content),
      "text/markdown",
      original_filename: "test.md"
    )

    assert_no_difference "EpisodeUsage.count" do
      post episodes_url, params: {
        episode: { title: "Test", author: "A", description: "D", content: file }
      }
    end
  end

  # URL-based episode creation tests

  test "create with url param creates URL episode and redirects" do
    assert_enqueued_with(job: ProcessesUrlEpisodeJob) do
      post episodes_url, params: { url: "https://example.com/article" }
    end

    assert_redirected_to episodes_path
    follow_redirect!
    assert_match(/Processing/, response.body)
  end

  test "create with url param fails with invalid URL" do
    post episodes_url, params: { url: "not-a-url" }

    assert_response :unprocessable_entity
  end

  test "create with url param records episode usage for free tier" do
    free_user = users(:free_user)
    sign_in_as free_user

    assert_difference -> { EpisodeUsage.count }, 1 do
      post episodes_url, params: { url: "https://example.com/article" }
    end
  end

  test "redirects free tier user from URL create when at monthly limit" do
    free_user = users(:free_user)
    sign_in_as free_user

    EpisodeUsage.create!(
      user: free_user,
      period_start: Time.current.beginning_of_month.to_date,
      episode_count: 2
    )

    post episodes_url, params: { url: "https://example.com/article" }

    assert_redirected_to episodes_path
    assert_includes flash[:alert], "You've used your 2 free episodes this month"
  end

  # Paste text episode creation tests

  test "create with text param creates paste episode and redirects" do
    assert_enqueued_with(job: ProcessesPasteEpisodeJob) do
      post episodes_url, params: { text: "A" * 150 }
    end

    assert_redirected_to episodes_path
    follow_redirect!
    assert_match(/Processing/, response.body)
  end

  test "create with text param passes title and author to service" do
    assert_enqueued_with(job: ProcessesPasteEpisodeJob) do
      post episodes_url, params: { text: "A" * 150, title: "My Title", author: "Jane Doe" }
    end

    episode = Episode.last
    assert_equal "My Title", episode.title
    assert_equal "Jane Doe", episode.author
  end

  test "create with text param uses placeholders when title and author blank" do
    assert_enqueued_with(job: ProcessesPasteEpisodeJob) do
      post episodes_url, params: { text: "A" * 150, title: "", author: "" }
    end

    episode = Episode.last
    assert_equal "Processing...", episode.title
    assert_equal "Processing...", episode.author
  end

  test "create with text param fails with empty text" do
    post episodes_url, params: { text: "" }

    assert_response :unprocessable_entity
  end

  test "create with text param fails with text under 100 characters" do
    post episodes_url, params: { text: "A" * 99 }

    assert_response :unprocessable_entity
  end

  test "create with text param records episode usage for free tier" do
    free_user = users(:free_user)
    sign_in_as free_user

    assert_difference -> { EpisodeUsage.count }, 1 do
      post episodes_url, params: { text: "A" * 150 }
    end
  end

  test "redirects free tier user from text create when at monthly limit" do
    free_user = users(:free_user)
    sign_in_as free_user

    EpisodeUsage.create!(
      user: free_user,
      period_start: Time.current.beginning_of_month.to_date,
      episode_count: 2
    )

    post episodes_url, params: { text: "A" * 150 }

    assert_redirected_to episodes_path
    assert_includes flash[:alert], "You've used your 2 free episodes this month"
  end

  # Pagination tests

  test "index paginates episodes to 10 per page" do
    get episodes_url
    assert_response :success

    # Count episode cards rendered - should be 10 on first page
    # We have 14 episodes for podcast :one (one + 12 pagination fixtures + failed_with_error)
    assert_select "[data-testid='episode-card']", count: 10
  end

  test "index shows second page when page param provided" do
    get episodes_url, params: { page: 2 }
    assert_response :success

    # Second page should have remaining 4 episodes
    assert_select "[data-testid='episode-card']", count: 4
  end

  test "index handles page beyond max by redirecting to last page" do
    get episodes_url, params: { page: 999 }
    assert_redirected_to episodes_url(page: 2)
  end

  test "index renders turbo frame for episodes list" do
    get episodes_url
    assert_response :success
    assert_select "turbo-frame#episodes_list"
  end

  test "index does not show pagination when 10 or fewer episodes" do
    # Delete pagination fixtures to have only 1 episode
    Episode.where(podcast: podcasts(:one)).where.not(id: episodes(:one).id).delete_all

    get episodes_url
    assert_response :success

    # Should not render pagination nav
    assert_select "nav.pagination", count: 0
  end

  # Failed episode error message tests

  test "index displays error message for failed episodes" do
    # Use the failed_with_error fixture
    get episodes_url
    assert_response :success
    assert_includes response.body, "This content is too long for your account tier"
  end

  test "index does not display error styling for completed episodes" do
    # Delete the failed episode so we only have completed ones
    Episode.where(status: :failed).delete_all

    get episodes_url
    assert_response :success

    # Should not contain the error message paragraph with red styling
    assert_no_match(/text-\[var\(--color-red\)\].*mt-1/, response.body)
  end

  # Public episode show tests

  test "show renders episode page for complete episode without authentication" do
    sign_out
    episode = episodes(:two) # status: complete
    get episode_url(episode.prefix_id)
    assert_response :success
  end

  test "show returns 404 for non-complete episode" do
    sign_out
    episode = episodes(:one) # status: pending
    get episode_url(episode.prefix_id)
    assert_response :not_found
  end

  test "show returns 404 for non-existent episode" do
    sign_out
    get episode_url("ep_nonexistent")
    assert_response :not_found
  end

  test "show displays episode title" do
    episode = episodes(:two)
    get episode_url(episode.prefix_id)
    assert_select "h1", text: episode.title
  end

  test "show displays audio player for complete episode" do
    episode = episodes(:two)
    get episode_url(episode.prefix_id)
    assert_select "audio[controls]"
  end

  test "show works for authenticated users too" do
    episode = episodes(:two)
    get episode_url(episode.prefix_id)
    assert_response :success
  end

  test "show displays download button" do
    episode = episodes(:two)
    get episode_url(episode.prefix_id)
    assert_select "a[href=?]", episode_path(episode.prefix_id, format: :mp3), text: /Download MP3/
  end

  test "show displays copy link button" do
    episode = episodes(:two)
    get episode_url(episode.prefix_id)
    assert_select "button[data-controller='clipboard']"
  end

  test "show displays view original link for unauthenticated user when source_url present" do
    sign_out
    episode = episodes(:two)
    get episode_url(episode.prefix_id)
    assert_select "a[href=?]", episode.source_url, text: /View Original/
  end

  test "show does not display view original link for unauthenticated user when source_url blank" do
    sign_out
    episode = episodes(:two)
    episode.update_column(:source_url, nil)
    get episode_url(episode.prefix_id)
    assert_select "a", text: /View Original/, count: 0
  end

  test "show with mp3 format redirects to signed GCS URL" do
    episode = episodes(:two)
    signed_url = "https://storage.googleapis.com/test-bucket/test.mp3?signature=abc"

    Mocktail.replace(GeneratesEpisodeDownloadUrl)
    stubs { |m| GeneratesEpisodeDownloadUrl.call(m.any) }.with { signed_url }

    get episode_url(episode.prefix_id, format: :mp3)

    assert_redirected_to signed_url
  end

  test "show with mp3 format returns 404 for incomplete episode" do
    episode = episodes(:one)  # pending episode

    get episode_url(episode.prefix_id, format: :mp3)

    assert_response :not_found
  end

  test "show with mp3 format works without authentication" do
    sign_out
    episode = episodes(:two)
    signed_url = "https://storage.googleapis.com/test-bucket/test.mp3?signature=abc"

    Mocktail.replace(GeneratesEpisodeDownloadUrl)
    stubs { |m| GeneratesEpisodeDownloadUrl.call(m.any) }.with { signed_url }

    get episode_url(episode.prefix_id, format: :mp3)

    assert_redirected_to signed_url
  end

  # Delete episode tests

  test "destroy soft-deletes the episode" do
    Mocktail.replace(CloudStorage)
    Mocktail.replace(GeneratesRssFeed)

    mock_gcs = Mocktail.of(CloudStorage)
    stubs { |m| CloudStorage.new(podcast_id: m.any) }.with { mock_gcs }
    stubs { |m| mock_gcs.delete_file(remote_path: m.any) }.with { true }
    stubs { |m| mock_gcs.upload_content(content: m.any, remote_path: m.any) }.with { nil }
    stubs { |m| GeneratesRssFeed.call(podcast: m.any) }.with { "<rss></rss>" }

    episode = episodes(:one)

    perform_enqueued_jobs do
      delete episode_url(episode)
    end

    assert_not_nil Episode.unscoped.find(episode.id).deleted_at
  end

  test "destroy enqueues DeleteEpisodeJob with episode" do
    episode = episodes(:one)
    episode.update!(gcs_episode_id: "20251222-test")

    assert_enqueued_with(job: DeleteEpisodeJob) do
      delete episode_url(episode)
    end
  end

  test "destroy redirects to episodes index for html requests" do
    episode = episodes(:one)

    delete episode_url(episode)

    assert_redirected_to episodes_path
  end

  test "destroy returns turbo stream that removes episode from DOM" do
    episode = episodes(:one)

    delete episode_url(episode), as: :turbo_stream

    assert_response :success
    assert_includes response.body, %(turbo-stream action="remove" target="episode_#{episode.id}")
    assert_includes response.body, %(turbo-stream action="update" target="flash-messages")
  end

  test "destroy redirects to episodes index when redirect param is present" do
    episode = episodes(:one)

    delete episode_url(episode, redirect: true), as: :turbo_stream

    assert_redirected_to episodes_path
  end

  test "deleted episodes do not appear in index" do
    episode = episodes(:one)
    episode.soft_delete!

    get episodes_url

    assert_response :success
    assert_no_match episode.title, response.body
  end

  # Episode search tests

  test "index with q param filters episodes by search query" do
    @user.podcasts.first.episodes.create!(
      user: @user, title: "Searchable", author: "Unique Author Name",
      description: "Test episode", source_type: :url,
      source_url: "https://example.com/searchable",
      source_text: "searchable content", status: :complete
    )

    get episodes_url, params: { q: "Unique Author" }

    assert_response :success
    assert_includes response.body, "Unique Author Name"
  end

  test "index without q param returns all episodes" do
    get episodes_url

    assert_response :success
    assert_select "[data-testid='episode-card']", count: 10
  end

  test "index with empty q param returns all episodes" do
    get episodes_url, params: { q: "" }

    assert_response :success
    assert_select "[data-testid='episode-card']", count: 10
  end

  test "index search with no results shows no-match message" do
    get episodes_url, params: { q: "zzzznoexist" }

    assert_response :success
    assert_includes response.body, "No episodes match your search"
  end

  test "index renders search input" do
    get episodes_url

    assert_response :success
    assert_select "input[name='q']"
  end

  test "index preserves query value in search input" do
    get episodes_url, params: { q: "test" }

    assert_response :success
    assert_select "input[name='q'][value='test']"
  end

  test "pagination links preserve q param during search" do
    # Create enough searchable episodes to paginate (>10)
    11.times do |i|
      @user.podcasts.first.episodes.create!(
        user: @user, title: "Searchable #{i}", author: "Searchable Author",
        description: "Test episode", source_type: :url,
        source_url: "https://example.com/search-#{i}",
        source_text: "searchable content #{i}", status: :complete
      )
    end

    get episodes_url, params: { q: "Searchable" }

    assert_response :success
    assert_select "a[href*='q=Searchable']"
  end

  test "index handles page beyond max with q param by redirecting to last page with q" do
    get episodes_url, params: { page: 999, q: "test" }
    assert_response :redirect
    assert_includes response.location, "q=test"
  end

  # === Credit-cost-by-usage ===
  #
  # A credit_user submitting a Premium voice + >20k chars triggers a
  # 2-credit charge. The pre-check gate must reject before any Episode or
  # CreditTransaction is written when balance < anticipated_cost.
  # Subscribers with 0 credits are also gated — only complimentary and
  # unlimited account_types bypass credit deduction.

  test "credit user with balance 1 cannot create Premium long-form episode (insufficient credits gated before create)" do
    credit_user = users(:credit_user)
    credit_user.update!(voice_preference: "callum") # Premium voice
    CreditBalance.for(credit_user).update!(balance: 1)
    sign_in_as credit_user

    long_text = "A" * 20_001 # >20k chars + Premium = 2 credits

    assert_no_difference -> { Episode.count } do
      assert_no_difference -> { CreditTransaction.count } do
        post episodes_url, params: { text: long_text }
      end
    end

    assert_response :redirect
    assert_equal 1, credit_user.reload.credits_remaining
  end

  test "credit user with balance 2 creates Premium long-form episode and is debited 2 credits" do
    credit_user = users(:credit_user)
    credit_user.update!(voice_preference: "callum") # Premium voice
    CreditBalance.for(credit_user).update!(balance: 2)
    sign_in_as credit_user

    long_text = "A" * 20_001 # >20k chars + Premium = 2 credits

    assert_difference -> { Episode.count }, 1 do
      assert_difference -> { CreditTransaction.where(user: credit_user, transaction_type: "usage").count }, 1 do
        post episodes_url, params: { text: long_text }
      end
    end

    assert_redirected_to episodes_path

    transaction = CreditTransaction.where(user: credit_user, transaction_type: "usage").order(:created_at).last
    assert_equal(-2, transaction.amount)
    assert_equal 0, credit_user.reload.credits_remaining
  end

  test "complimentary user creates Premium long-form episode with no CreditTransaction written" do
    complimentary_user = users(:complimentary_user)
    complimentary_user.update!(voice_preference: "callum") # Premium voice
    sign_in_as complimentary_user

    long_text = "A" * 20_001

    assert_difference -> { Episode.count }, 1 do
      assert_no_difference -> { CreditTransaction.count } do
        post episodes_url, params: { text: long_text }
      end
    end

    assert_redirected_to episodes_path
  end

  test "unlimited user creates Premium long-form episode with no CreditTransaction written" do
    unlimited_user = users(:unlimited_user)
    unlimited_user.update!(voice_preference: "callum") # Premium voice
    sign_in_as unlimited_user

    long_text = "A" * 20_001

    assert_difference -> { Episode.count }, 1 do
      assert_no_difference -> { CreditTransaction.count } do
        post episodes_url, params: { text: long_text }
      end
    end

    assert_redirected_to episodes_path
  end

  test "URL submission does not write a CreditTransaction at controller time" do
    # URL pricing defers to ProcessesUrlEpisode because the article's
    # real length isn't known until fetch + extract. The controller's
    # only job here is the minimum balance gate.
    credit_user = users(:credit_user)
    CreditBalance.for(credit_user).update!(balance: 3)
    sign_in_as credit_user

    assert_difference -> { Episode.count }, 1 do
      assert_no_difference -> { CreditTransaction.count } do
        post episodes_url, params: { url: "https://example.com/article" }
      end
    end

    assert_redirected_to episodes_path
    assert_equal 3, credit_user.reload.credits_remaining
  end

  test "subscriber with zero credits is gated (premium subscription bypass removed)" do
    # Regression guard: subscribers whose credit_user? returns false (due
    # to premium? short-circuit) must still be gated. Only complimentary
    # and unlimited account_types bypass credit deduction.
    subscriber = users(:subscriber) # has active_subscription fixture
    subscriber.update!(voice_preference: "callum") # Premium voice
    # Ensure zero credit balance (subscribers don't typically have one)
    CreditBalance.for(subscriber).update!(balance: 0)
    sign_in_as subscriber

    long_text = "A" * 20_001

    assert_no_difference -> { Episode.count } do
      assert_no_difference -> { CreditTransaction.count } do
        post episodes_url, params: { text: long_text }
      end
    end

    # Behaviour on the web path is redirect + flash (matches existing
    # permission-gate style). The corresponding API v1 path returns 402.
    assert_response :redirect
  end

  # === New-episode form: credit cost preview UI (agent-team-gq88) ===
  #
  # The hardcoded "This episode will use 1 credit" copy is a lie post-cga5
  # (Premium + >20k = 2 credits). gq88 replaces it with a Stimulus-driven
  # reactive cost preview. Voice selection is read-only on the form —
  # users change voice in /settings (locked design decision).

  test "new form for credit user removes hardcoded 1-credit copy" do
    credit_user = users(:credit_user)
    CreditBalance.for(credit_user).update!(balance: 3)
    credit_user.update!(voice_preference: "callum")
    sign_in_as credit_user

    get new_episode_url

    assert_response :success
    assert_not_includes response.body, "This episode will use 1 credit",
      "Hardcoded 1-credit copy must be removed (incorrect for Premium + >20k)"
  end

  test "new form for credit user attaches cost_preview Stimulus controller" do
    credit_user = users(:credit_user)
    CreditBalance.for(credit_user).update!(balance: 3)
    credit_user.update!(voice_preference: "callum")
    sign_in_as credit_user

    get new_episode_url

    assert_response :success
    assert_select "[data-controller~='cost-preview']", minimum: 1
  end

  test "new form for credit user renders a read-only voice badge" do
    credit_user = users(:credit_user)
    CreditBalance.for(credit_user).update!(balance: 3)
    credit_user.update!(voice_preference: "callum")
    sign_in_as credit_user

    get new_episode_url

    assert_response :success
    # Badge shows the user's effective voice name (Callum in this case).
    assert_match(/Callum/, response.body,
      "Expected the read-only voice badge to display the user's voice name")
  end

  test "new form for credit user links to settings voice section" do
    credit_user = users(:credit_user)
    CreditBalance.for(credit_user).update!(balance: 3)
    credit_user.update!(voice_preference: "felix")
    sign_in_as credit_user

    get new_episode_url

    assert_response :success
    # The settings page anchors its voice section at #voice (see
    # settings/show.html.erb). The "Change in settings" link should
    # point there so the user can swap voice without inline override.
    assert_select "a[href=?]", settings_path(anchor: "voice"),
      text: /Change in settings/i
  end

  test "new form for credit user includes a cost-preview target div" do
    credit_user = users(:credit_user)
    CreditBalance.for(credit_user).update!(balance: 3)
    credit_user.update!(voice_preference: "felix")
    sign_in_as credit_user

    get new_episode_url

    assert_response :success
    assert_select "[data-cost-preview-target='preview']", minimum: 1
  end

  test "new form for free tier user does not render cost preview UI" do
    free = users(:free_user)
    sign_in_as free

    get new_episode_url

    assert_response :success
    assert_select "[data-controller~='cost-preview']", count: 0
    # Existing free-tier quota copy still present (unchanged by gq88).
    # We don't assert the exact message here — episodes_controller#new
    # flashes on redirect when over quota; under quota the view renders
    # without the cost preview block.
  end

  test "new form for complimentary user does not render cost preview UI" do
    complimentary = users(:complimentary_user)
    sign_in_as complimentary

    get new_episode_url

    assert_response :success
    assert_select "[data-controller~='cost-preview']", count: 0
    assert_not_includes response.body, "This episode will use 1 credit"
  end

  test "new form for unlimited user does not render cost preview UI" do
    unlimited = users(:unlimited_user)
    sign_in_as unlimited

    get new_episode_url

    assert_response :success
    assert_select "[data-controller~='cost-preview']", count: 0
    assert_not_includes response.body, "This episode will use 1 credit"
  end

  # === Episode show page: character count + credit cost display (agent-team-xgyd) ===
  #
  # The owner view of the episode show page surfaces a per-episode receipt:
  # character count (Episode#source_text_length), credits consumed (from the
  # usage CreditTransaction), and the voice tier for that episode. This closes
  # the UX gap where URL-submitted episodes debit credits asynchronously post-
  # submit and the user otherwise has no durable record of "what did this
  # episode cost me?".
  #
  # Scope covers four account states:
  #   1. standard credit_user with a usage CreditTransaction (modern pricing)
  #   2. free-tier user, no CreditTransaction ('Free tier episode')
  #   3. complimentary / unlimited, no CreditTransaction ('Included')
  #   4. legacy pre-cga5 usage row (amount=-1 sentinel; display as-is)

  test "show displays formatted character count for credit-debited episode" do
    credit_user = users(:credit_user)
    credit_user.update!(voice_preference: "felix") # Standard voice
    episode = credit_user.primary_podcast.episodes.create!(
      user: credit_user, title: "Cost Receipt", author: "Author",
      description: "desc", source_type: :paste,
      source_text: "A" * 41_204, status: :complete
    )
    episode.update_columns(source_text_length: 41_204)
    CreditTransaction.create!(
      user: credit_user, episode: episode,
      amount: -1, balance_after: 2, transaction_type: "usage"
    )

    sign_in_as credit_user
    get episode_url(episode.prefix_id)

    assert_response :success
    assert_includes response.body, "41,204",
      "Expected character count to render with delimiter (e.g., '41,204')"
  end

  test "show displays credit cost pluralized for 1-credit episode" do
    credit_user = users(:credit_user)
    credit_user.update!(voice_preference: "felix") # Standard voice
    episode = credit_user.primary_podcast.episodes.create!(
      user: credit_user, title: "One Credit", author: "Author",
      description: "desc", source_type: :paste,
      source_text: "A" * 10_000, status: :complete
    )
    episode.update_columns(source_text_length: 10_000, credit_cost: 1)
    CreditTransaction.create!(
      user: credit_user, episode: episode,
      amount: -1, balance_after: 2, transaction_type: "usage"
    )

    sign_in_as credit_user
    get episode_url(episode.prefix_id)

    assert_response :success
    assert_match(/\b1 credit\b/, response.body,
      "Expected '1 credit' (singular) for an episode charged 1 credit")
  end

  test "show displays credit cost pluralized for 2-credit episode" do
    credit_user = users(:credit_user)
    credit_user.update!(voice_preference: "callum") # Premium voice
    episode = credit_user.primary_podcast.episodes.create!(
      user: credit_user, title: "Two Credits", author: "Author",
      description: "desc", source_type: :paste,
      source_text: "A" * 30_000, status: :complete
    )
    episode.update_columns(source_text_length: 30_000, credit_cost: 2)
    CreditTransaction.create!(
      user: credit_user, episode: episode,
      amount: -2, balance_after: 1, transaction_type: "usage"
    )

    sign_in_as credit_user
    get episode_url(episode.prefix_id)

    assert_response :success
    assert_match(/\b2 credits\b/, response.body,
      "Expected '2 credits' (plural) for an episode charged 2 credits")
  end

  test "show displays Standard voice tier label for credit-debited episode with Standard voice" do
    credit_user = users(:credit_user)
    credit_user.update!(voice_preference: "felix") # Standard voice
    episode = credit_user.primary_podcast.episodes.create!(
      user: credit_user, title: "My Article", author: "Author",
      description: "desc", source_type: :paste,
      source_text: "A" * 5_000, status: :complete
    )
    episode.update_columns(source_text_length: 5_000)
    CreditTransaction.create!(
      user: credit_user, episode: episode,
      amount: -1, balance_after: 2, transaction_type: "usage"
    )

    sign_in_as credit_user
    get episode_url(episode.prefix_id)

    assert_response :success
    # Scope the assertion to the owner-view details <dl> so a stray "Standard"
    # in a header/link elsewhere can't accidentally satisfy the test.
    assert_select "dl dd", text: /Standard/i,
      message: "Expected 'Standard' voice tier label inside the Details <dl>"
  end

  test "show displays Premium voice tier label for credit-debited episode with Premium voice" do
    credit_user = users(:credit_user)
    credit_user.update!(voice_preference: "callum") # Premium voice
    episode = credit_user.primary_podcast.episodes.create!(
      user: credit_user, title: "My Article", author: "Author",
      description: "desc", source_type: :paste,
      source_text: "A" * 30_000, status: :complete
    )
    episode.update_columns(source_text_length: 30_000)
    CreditTransaction.create!(
      user: credit_user, episode: episode,
      amount: -2, balance_after: 1, transaction_type: "usage"
    )

    sign_in_as credit_user
    get episode_url(episode.prefix_id)

    assert_response :success
    assert_select "dl dd", text: /Premium/i,
      message: "Expected 'Premium' voice tier label inside the Details <dl>"
  end

  test "show displays character count for free-tier episode" do
    free_user = users(:free_user)
    # free_user has no subscription, no credit_balance → free? == true
    assert free_user.free?, "Expected free_user fixture to be on free tier"
    # Title chosen to not collide with any tier/cost regexes below.
    episode = free_user.primary_podcast.episodes.create!(
      user: free_user, title: "My Article", author: "Author",
      description: "desc", source_type: :paste,
      source_text: "A" * 2_500, status: :complete
    )
    episode.update_columns(source_text_length: 2_500)

    sign_in_as free_user
    get episode_url(episode.prefix_id)

    assert_response :success
    assert_includes response.body, "2,500",
      "Expected character count to render for free-tier episode"
  end

  test "show labels free-tier episode distinctively (no credit cost)" do
    free_user = users(:free_user)
    assert free_user.free?, "Expected free_user fixture to be on free tier"
    episode = free_user.primary_podcast.episodes.create!(
      user: free_user, title: "My Article", author: "Author",
      description: "desc", source_type: :paste,
      source_text: "A" * 2_500, status: :complete
    )
    episode.update_columns(source_text_length: 2_500, credit_cost: 0)
    # Sanity check: no CreditTransaction exists for this episode.
    assert_equal 0, CreditTransaction.where(episode_id: episode.id).count

    sign_in_as free_user
    get episode_url(episode.prefix_id)

    assert_response :success
    # Scope to <dl> so the marketing-layout signup modal copy ("Start listening
    # free") can't accidentally satisfy this assertion.
    assert_select "dl dd", text: /Free tier/i,
      message: "Expected free-tier episode to be labeled 'Free tier' in the Details <dl>"
  end

  test "show labels complimentary-account episode as Included (no credit cost)" do
    complimentary = users(:complimentary_user)
    assert complimentary.complimentary?,
      "Expected complimentary_user fixture to have account_type=complimentary"
    episode = complimentary.primary_podcast.episodes.create!(
      user: complimentary, title: "My Article", author: "Author",
      description: "desc", source_type: :paste,
      source_text: "A" * 7_500, status: :complete
    )
    episode.update_columns(source_text_length: 7_500)

    sign_in_as complimentary
    get episode_url(episode.prefix_id)

    assert_response :success
    assert_includes response.body, "7,500",
      "Expected character count to render for complimentary episode"
    assert_select "dl dd", text: /Included/,
      message: "Expected complimentary episode to be labeled 'Included' in the Details <dl>"
  end

  test "show labels unlimited-account episode as Included (no credit cost)" do
    unlimited = users(:unlimited_user)
    assert unlimited.unlimited?,
      "Expected unlimited_user fixture to have account_type=unlimited"
    episode = unlimited.primary_podcast.episodes.create!(
      user: unlimited, title: "My Article", author: "Author",
      description: "desc", source_type: :paste,
      source_text: "A" * 15_000, status: :complete
    )
    episode.update_columns(source_text_length: 15_000)

    sign_in_as unlimited
    get episode_url(episode.prefix_id)

    assert_response :success
    assert_includes response.body, "15,000",
      "Expected character count to render for unlimited episode"
    assert_select "dl dd", text: /Included/,
      message: "Expected unlimited episode to be labeled 'Included' in the Details <dl>"
  end

  test "show renders legacy pre-cga5 episode (amount=-1) without special-casing" do
    # Pre-cga5 flat-rate-era episodes have CreditTransaction.amount = -1 as a
    # sentinel. The bead directs: display as-is, no special-casing. We assert
    # the page renders char count + a credit-style label, without asserting
    # any "legacy" marker (there isn't one to hardcode against).
    credit_user = users(:credit_user)
    credit_user.update!(voice_preference: "felix")
    episode = credit_user.primary_podcast.episodes.create!(
      user: credit_user, title: "Legacy Episode", author: "Author",
      description: "desc", source_type: :paste,
      source_text: "A" * 8_888, status: :complete
    )
    episode.update_columns(source_text_length: 8_888)
    # amount: -1 represents both "1 credit (modern)" and "pre-cga5 sentinel".
    # We can't distinguish — that's the point; display as-is.
    CreditTransaction.create!(
      user: credit_user, episode: episode,
      amount: -1, balance_after: 2, transaction_type: "usage",
      created_at: 1.year.ago # simulate pre-cga5 era
    )

    sign_in_as credit_user
    get episode_url(episode.prefix_id)

    assert_response :success
    assert_includes response.body, "8,888",
      "Expected character count to render for legacy episode"
    assert_match(/credit/i, response.body,
      "Expected legacy episode to render a credit label (no special-casing)")
  end
end
