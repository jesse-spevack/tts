# frozen_string_literal: true

require "test_helper"

# Tests for the anonymous home page pricing section + FAQ copy after iny7.
#
# iny7 removes all user-facing subscription surfaces: the Monthly/Yearly
# pricing toggle goes away, the two Premium tiers ($9/mo, $89/yr) are
# replaced by three credit-pack tiers (Starter/Standard/Bulk), and the
# FAQ is rewritten to stop pitching a subscription.
class PagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Anonymous; PagesController#home redirects authenticated users.
    get root_path
    assert_response :success
    @body = response.body
  end

  # --- Pricing section: no subscription surfaces ---

  test "home page does not render subscription prices" do
    refute_match "$9/month", @body
    refute_match "$89/year", @body
    refute_match "Premium Monthly", @body
    refute_match "Premium Annual", @body
  end

  test "home page does not render premium plan signup CTAs" do
    assert_select %([data-plan="premium_monthly"]), false,
      "Expected no data-plan=premium_monthly buttons on home page"
    assert_select %([data-plan="premium_annual"]), false,
      "Expected no data-plan=premium_annual buttons on home page"
  end

  test "home page does not render the monthly/annual pricing toggle" do
    assert_select %(input[name="frequency"]), false,
      "Expected no Monthly/Yearly frequency toggle on home page"
    # The pricing_toggle Stimulus controller wraps the toggle. If it's still
    # wired in, the subscription UX hasn't been removed.
    assert_select %([data-controller~="pricing-toggle"]), false,
      "Expected no pricing-toggle stimulus controller on home page"
    # The shared/marketing/pricing_hero_multi partial renders an <el-tab-group>
    # with Monthly/Yearly tab buttons. After iny7 there's one panel of tiers,
    # so the pricing-section tab-group must be absent.
    assert_select %(el-tab-group), false,
      "Expected no el-tab-group (Monthly/Yearly toggle) on home page"
  end

  test "home page forbids 'Get Premium' and 'Subscribe to' copy" do
    refute_includes @body, "Get Premium"
    refute_includes @body, "Subscribe to"
  end

  # --- Pricing section: three credit packs + Free ---

  test "home page renders Starter / Standard / Bulk pack labels" do
    assert_match "Starter", @body
    assert_match "Standard", @body
    assert_match "Bulk", @body
  end

  test "home page renders the three credit pack prices" do
    assert_match "$9.99", @body
    assert_match "$17.99", @body
    assert_match "$32.99", @body
  end

  test "home page renders three credit_pack CTAs with pack_size 5/10/20" do
    assert_select %([data-plan="credit_pack"][data-pack-size="5"]), 1,
      "Expected one credit_pack CTA for 5-pack (Starter)"
    assert_select %([data-plan="credit_pack"][data-pack-size="10"]), 1,
      "Expected one credit_pack CTA for 10-pack (Standard)"
    assert_select %([data-plan="credit_pack"][data-pack-size="20"]), 1,
      "Expected one credit_pack CTA for 20-pack (Bulk)"
  end

  test "home page marks the 20-pack Bulk card as Best value" do
    # Implementer may choose the exact element, but the 'Best value' badge
    # copy must appear somewhere in the pricing section adjacent to the
    # Bulk / $32.99 tier.
    assert_match "Best value", @body
  end

  test "home page still renders the Free tier with $0 / 2 episodes per month" do
    assert_match "$0", @body
    assert_match "2 episodes", @body
  end

  # --- FAQ: no subscription language ---

  test "home page FAQ does not pitch a $9/month subscription" do
    refute_match "$9/month", @body
    refute_match "subscription", @body
    refute_match "unlimited episodes", @body
  end

  test "home page FAQ mentions credit pack pricing" do
    assert_match "credit pack", @body
    # The Starter-pack entry-point price from the rewritten FAQ.
    assert_match "$9.99 for 5 episodes", @body
  end

  # --- Splitting Long Articles help page (agent-team-qc8o) -------------------
  #
  # Reached from the inline tip rendered on a failed-with-char-limit episode
  # card. The page walks users through the paste-and-split workaround.

  test "splitting articles help page renders successfully" do
    get help_splitting_articles_path
    assert_response :success
  end

  test "splitting articles help page mounts the scroll-spy controller" do
    get help_splitting_articles_path
    assert_select %([data-controller~="scroll-spy"])
    assert_select %([data-scroll-spy-target="step"]), 4,
      "Expected 4 step articles for the scroll-spy to observe"
    assert_select %([data-scroll-spy-target="link"]), 4,
      "Expected 4 nav links matching the 4 steps"
  end

  test "splitting articles help page links to the paste form deep-link" do
    get help_splitting_articles_path
    assert_select %(a[href="#{new_episode_path(source: "paste")}"])
  end

  # Right-rail "On this page" ToC (agent-team-q8nk). Pattern matches
  # docs/{authentication,episodes,mpp}.html.erb so help and API docs share one
  # visual language. Hidden below xl via Tailwind classes; we assert it's in
  # the rendered HTML and that all 4 step targets are linked.
  test "splitting articles help page renders the right-rail ToC" do
    get help_splitting_articles_path
    assert_select %(nav[aria-label="On this page"]) do
      assert_select %(a[href="#step-1"])
      assert_select %(a[href="#step-2"])
      assert_select %(a[href="#step-3"])
      assert_select %(a[href="#step-4"])
    end
  end

  test "splitting articles is reachable from the help nav" do
    get help_add_rss_feed_path
    assert_select %(a[href="#{help_splitting_articles_path}"])
  end

  # --- Convert-a-URL help page (agent-team-wo80) ---------------------------
  #
  # Walks a user through the URL-source episode-creation flow. Mirrors the
  # splitting-articles page structure (4 steps, scroll-spy nav, demo frames).

  test "url_help page renders successfully" do
    get help_url_path
    assert_response :success
  end

  test "url_help page mounts the scroll-spy controller" do
    get help_url_path
    assert_select %([data-controller~="scroll-spy"])
    assert_select %([data-scroll-spy-target="step"]), 4,
      "Expected 4 step articles for the scroll-spy to observe"
    assert_select %([data-scroll-spy-target="link"]), 4,
      "Expected 4 nav links matching the 4 steps"
  end

  test "url_help page links to the new-episode form" do
    get help_url_path
    assert_select %(a[href="#{new_episode_path}"])
  end

  test "url_help is reachable from the help nav" do
    get help_add_rss_feed_path
    assert_select %(a[href="#{help_url_path}"])
  end

  # Right-rail "On this page" ToC (agent-team-1yb3). Mirrors the
  # splitting-articles ToC test — same shared partial, same markup, same
  # 4-step shape. Hidden below xl via Tailwind classes; we assert it's in
  # the rendered HTML and that all 4 step targets are linked.
  test "url_help page renders the right-rail ToC" do
    get help_url_path
    assert_select %(nav[aria-label="On this page"]) do
      assert_select %(a[href="#step-1"])
      assert_select %(a[href="#step-2"])
      assert_select %(a[href="#step-3"])
      assert_select %(a[href="#step-4"])
    end
  end

  # --- Upload-a-file help page (agent-team-90no / epic agent-team-dewz) ----

  test "file help page renders successfully" do
    get help_file_path
    assert_response :success
  end

  test "file help page mounts the scroll-spy controller" do
    get help_file_path
    assert_select %([data-controller~="scroll-spy"])
    assert_select %([data-scroll-spy-target="step"]), 4,
      "Expected 4 step articles for the scroll-spy to observe"
    assert_select %([data-scroll-spy-target="link"]), 4,
      "Expected 4 nav links matching the 4 steps"
  end

  test "file help page links to the upload form deep-link" do
    get help_file_path
    assert_select %(a[href="#{new_episode_path(source: "file")}"])
  end

  # Right-rail "On this page" ToC (agent-team-ozxg). Pattern matches
  # /help/splitting-articles (PR #357) and docs/{authentication,episodes,mpp}.
  # Hidden below xl via Tailwind classes; we assert it's in the rendered HTML
  # and that all 4 step targets are linked.
  test "file help page renders the right-rail ToC" do
    get help_file_path
    assert_select %(nav[aria-label="On this page"]) do
      assert_select %(a[href="#step-1"])
      assert_select %(a[href="#step-2"])
      assert_select %(a[href="#step-3"])
      assert_select %(a[href="#step-4"])
    end
  end

  test "file help is reachable from the help nav" do
    get help_add_rss_feed_path
    assert_select %(a[href="#{help_file_path}"])
  end

  # --- Email-articles help page (agent-team-e1sh / epic agent-team-dewz) ----

  test "email help page renders successfully" do
    get help_email_path
    assert_response :success
  end

  test "email help page mounts the scroll-spy controller" do
    get help_email_path
    assert_select %([data-controller~="scroll-spy"])
    assert_select %([data-scroll-spy-target="step"]), 4
    assert_select %([data-scroll-spy-target="link"]), 4
  end

  test "email help page links to settings (where the user enables email episodes)" do
    get help_email_path
    assert_select %(a[href="#{settings_path}"])
  end

  test "email help is reachable from the help nav" do
    get help_add_rss_feed_path
    assert_select %(a[href="#{help_email_path}"])
  end

  # Right-rail "On this page" ToC (agent-team-kz29). Pattern matches
  # docs/{authentication,episodes,mpp}.html.erb so help and API docs share one
  # visual language. Hidden below xl via Tailwind classes; we assert it's in
  # the rendered HTML and that all 4 step targets are linked.
  test "email help page renders the right-rail ToC" do
    get help_email_path
    assert_select %(nav[aria-label="On this page"]) do
      assert_select %(a[href="#step-1"])
      assert_select %(a[href="#step-2"])
      assert_select %(a[href="#step-3"])
      assert_select %(a[href="#step-4"])
    end
  end

  # --- Browser extension help page (agent-team-3njp / epic agent-team-dewz) -

  test "extension help page renders successfully" do
    get help_extension_path
    assert_response :success
  end

  test "extension help page mounts the scroll-spy controller" do
    get help_extension_path
    assert_select %([data-controller~="scroll-spy"])
    assert_select %([data-scroll-spy-target="step"]), 4,
      "Expected 4 step articles for the scroll-spy to observe"
    assert_select %([data-scroll-spy-target="link"]), 4,
      "Expected 4 nav links matching the 4 steps"
  end

  test "extension help page links to the Chrome Web Store" do
    get help_extension_path
    assert_select %(a[href="#{AppConfig::Extension::CHROME_WEB_STORE_URL}"])
  end

  # Right-rail "On this page" ToC (agent-team-td0g, sweep of agent-team-s4zp).
  # Same pattern as splitting_articles — see PR #357 / agent-team-q8nk.
  test "extension help page renders the right-rail ToC" do
    get help_extension_path
    assert_select %(nav[aria-label="On this page"]) do
      assert_select %(a[href="#step-1"])
      assert_select %(a[href="#step-2"])
      assert_select %(a[href="#step-3"])
      assert_select %(a[href="#step-4"])
    end
  end

  # --- Paste text help page (agent-team-k8ph / epic agent-team-dewz) -------

  test "paste help page renders successfully" do
    get help_paste_path
    assert_response :success
  end

  test "paste help page mounts the scroll-spy controller" do
    get help_paste_path
    assert_select %([data-controller~="scroll-spy"])
    assert_select %([data-scroll-spy-target="step"]), 4,
      "Expected 4 step articles for the scroll-spy to observe"
    assert_select %([data-scroll-spy-target="link"]), 4,
      "Expected 4 nav links matching the 4 steps"
  end

  test "paste help page links to the paste form deep-link" do
    get help_paste_path
    assert_select %(a[href="#{new_episode_path(source: "paste")}"])
  end

  # Right-rail "On this page" ToC (agent-team-377f, sweep agent-team-s4zp).
  # Mirrors the splitting-articles assertion from PR #357 — same partial,
  # same scroll-spy targets, same 4-step shape.
  test "paste help page renders the right-rail ToC" do
    get help_paste_path
    assert_select %(nav[aria-label="On this page"]) do
      assert_select %(a[href="#step-1"])
      assert_select %(a[href="#step-2"])
      assert_select %(a[href="#step-3"])
      assert_select %(a[href="#step-4"])
    end
  end

  test "paste help is reachable from the help nav" do
    get help_add_rss_feed_path
    assert_select %(a[href="#{help_paste_path}"])
  end

  # --- Add RSS feed help page (agent-team-e399 / epic agent-team-fvh1) ------
  #
  # Reference doc, not a 4-step walkthrough. Sections are arbitrary
  # (Apple Podcasts / Overcast / Pocket Casts / Other apps), so the
  # right-rail ToC uses the unnumbered shape — `_help_right_toc.html.erb`
  # accepts `{ id:, label: }` items and matches the API-docs ToC pattern.
  # Same shared partial as the walkthrough pages, same scroll-spy controller;
  # only the data-step keys differ (id strings instead of step numbers).

  test "add rss feed help page renders successfully" do
    get help_add_rss_feed_path
    assert_response :success
  end

  test "add rss feed help page mounts the scroll-spy controller" do
    get help_add_rss_feed_path
    assert_select %([data-controller~="scroll-spy"])
    assert_select %([data-scroll-spy-target="step"]), 4,
      "Expected 4 section headings (Apple Podcasts / Overcast / Pocket Casts / Other apps)"
    assert_select %([data-scroll-spy-target="link"]), 4,
      "Expected 4 nav links matching the 4 sections"
  end

  test "add rss feed help page renders the right-rail ToC with section anchors" do
    get help_add_rss_feed_path
    assert_select %(nav[aria-label="On this page"]) do
      assert_select %(a[href="#apple-podcasts"])
      assert_select %(a[href="#overcast"])
      assert_select %(a[href="#pocket-casts"])
      assert_select %(a[href="#other-apps"])
    end
  end

  # --- CLI help page (agent-team-gbhp / sweep agent-team-ypqj) -------------
  #
  # Reference doc, not a 4-step walkthrough. Sections are arbitrary
  # (Install / Log in / Create an episode / Choose a voice / Manage episodes
  # / Get your feed / More info), so the right-rail ToC uses the unnumbered
  # shape — `_help_right_toc.html.erb` accepts `{ id:, label: }` items and
  # matches the API-docs ToC pattern. Same shared partial as the walkthrough
  # pages, same scroll-spy controller; only the data-step keys differ (id
  # strings instead of step numbers).

  test "cli help page renders successfully" do
    get help_cli_path
    assert_response :success
  end

  test "cli help page mounts the scroll-spy controller" do
    get help_cli_path
    assert_select %([data-controller~="scroll-spy"])
    assert_select %([data-scroll-spy-target="step"]), 7,
      "Expected 7 section headings (Install / Log in / Create an episode / Choose a voice / Manage episodes / Get your feed / More info)"
    assert_select %([data-scroll-spy-target="link"]), 7,
      "Expected 7 nav links matching the 7 sections"
  end

  test "cli help page renders the right-rail ToC with section anchors" do
    get help_cli_path
    assert_select %(nav[aria-label="On this page"]) do
      assert_select %(a[href="#install"])
      assert_select %(a[href="#log-in"])
      assert_select %(a[href="#create-an-episode"])
      assert_select %(a[href="#choose-a-voice"])
      assert_select %(a[href="#manage-episodes"])
      assert_select %(a[href="#get-your-feed"])
      assert_select %(a[href="#more-info"])
    end
  end

  # --- Claude Code help page (agent-team-bxw3 / sweep agent-team-ypqj) ------
  #
  # Reference doc, not a 4-step walkthrough. Sections are arbitrary
  # (What is it? / Prerequisites / Install / Usage / Troubleshooting), so the
  # right-rail ToC uses the unnumbered shape — `_help_right_toc.html.erb`
  # accepts `{ id:, label: }` items and matches the API-docs ToC pattern.
  # Same shared partial as the walkthrough pages, same scroll-spy controller;
  # only the data-step keys differ (id strings instead of step numbers).

  test "claude code help page renders successfully" do
    get help_claude_code_path
    assert_response :success
  end

  test "claude code help page mounts the scroll-spy controller" do
    get help_claude_code_path
    assert_select %([data-controller~="scroll-spy"])
    assert_select %([data-scroll-spy-target="step"]), 5,
      "Expected 5 section headings (What is it? / Prerequisites / Install / Usage / Troubleshooting)"
    assert_select %([data-scroll-spy-target="link"]), 5,
      "Expected 5 nav links matching the 5 sections"
  end

  test "claude code help page renders the right-rail ToC with section anchors" do
    get help_claude_code_path
    assert_select %(nav[aria-label="On this page"]) do
      assert_select %(a[href="#what-is-it"])
      assert_select %(a[href="#prerequisites"])
      assert_select %(a[href="#install"])
      assert_select %(a[href="#usage"])
      assert_select %(a[href="#troubleshooting"])
    end
  end

  # --- How It Sounds page (agent-team-t58q / epic agent-team-fvh1) ---------
  #
  # Reference doc, not a 4-step walkthrough. Two arbitrary sections (the
  # audio sample and the how-it-works overview), so the right-rail ToC uses
  # the unnumbered { id:, label: } shape — same pattern as add_rss_feed.

  test "how it sounds page renders successfully" do
    get how_it_sounds_path
    assert_response :success
  end

  test "how it sounds page mounts the scroll-spy controller" do
    get how_it_sounds_path
    assert_select %([data-controller~="scroll-spy"])
    assert_select %([data-scroll-spy-target="step"]), 2,
      "Expected 2 section headings (Sample audio / How it works)"
    assert_select %([data-scroll-spy-target="link"]), 2,
      "Expected 2 nav links matching the 2 sections"
  end

  test "how it sounds page renders the right-rail ToC with section anchors" do
    get how_it_sounds_path
    assert_select %(nav[aria-label="On this page"]) do
      assert_select %(a[href="#sample-audio"])
      assert_select %(a[href="#how-it-works"])
    end
  end

  # --- ChatGPT help page (agent-team-ovaf / sweep agent-team-ypqj) ---------
  #
  # Reference doc, not a 4-step walkthrough. Sections are arbitrary
  # (Getting started / Example prompts / What you can do / Troubleshooting),
  # so the right-rail ToC uses the unnumbered { id:, label: } shape — same
  # shared partial, same scroll-spy controller, just id-string data-step
  # keys instead of step numbers. Mirrors add_rss_feed (PR #365).

  test "chatgpt help page renders successfully" do
    get help_chatgpt_path
    assert_response :success
  end

  test "chatgpt help page mounts the scroll-spy controller" do
    get help_chatgpt_path
    assert_select %([data-controller~="scroll-spy"])
    assert_select %([data-scroll-spy-target="step"]), 4,
      "Expected 4 section headings (Getting started / Example prompts / What you can do / Troubleshooting)"
    assert_select %([data-scroll-spy-target="link"]), 4,
      "Expected 4 nav links matching the 4 sections"
  end

  test "chatgpt help page renders the right-rail ToC with section anchors" do
    get help_chatgpt_path
    assert_select %(nav[aria-label="On this page"]) do
      assert_select %(a[href="#getting-started"])
      assert_select %(a[href="#example-prompts"])
      assert_select %(a[href="#what-you-can-do"])
      assert_select %(a[href="#troubleshooting"])
    end
  end
end
