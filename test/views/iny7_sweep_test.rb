# frozen_string_literal: true

require "test_helper"

# Filesystem-level sweeps that back up iny7's acceptance criteria. These are
# blunt instruments (grep + file-existence checks), but they catch drift the
# unit tests miss — a stray `upgrade_path` that compiles fine, a leftover
# partial that nobody renders, a JS controller that stopped being referenced.
#
# Separate from the controller/view render tests so we can reason about
# "does this file exist" and "does this substring appear anywhere under
# app/views" independent of any one controller action.
class Iny7SweepTest < ActiveSupport::TestCase
  VIEWS_ROOT = Rails.root.join("app/views")

  # --- _premium_card partial is gone (iny7 decision 5) ---

  test "app/views/shared/_premium_card.html.erb is deleted" do
    path = Rails.root.join("app/views/shared/_premium_card.html.erb")
    refute File.exist?(path),
      "The _premium_card partial must be removed entirely (no callers survive iny7)."
  end

  test "no view renders the shared/premium_card partial" do
    offenders = grep_views(/shared\/premium_card/)
    assert_empty offenders,
      "Views still render shared/premium_card; the partial is deleted — " \
      "update these: #{offenders.join(", ")}"
  end

  # --- pricing_toggle_controller.js is gone (iny7 decision) ---

  test "pricing_toggle_controller.js is deleted" do
    path = Rails.root.join("app/javascript/controllers/pricing_toggle_controller.js")
    refute File.exist?(path),
      "Monthly/annual toggle has no purpose after subscription signup is removed."
  end

  test "no view wires the pricing-toggle stimulus controller" do
    offenders = grep_views(/pricing[-_]toggle/)
    assert_empty offenders,
      "Views still reference pricing-toggle: #{offenders.join(", ")}"
  end

  # --- upgrade_path / upgrade_url route helper call sites are gone from views ---
  # The docs still reference the JSON API response field named `upgrade_url`
  # (documented in the error table for POST /api/v1/episodes). That field is
  # a stable API contract the MPP docs also reference (MPP is SHA-pinned), so
  # the sweep pattern is narrowed to ERB route-helper invocations only.

  test "no view references upgrade_path or upgrade_url" do
    offenders = grep_views(/<%=?\s*(?:link_to\s*\(?\s*["'][^"']*["']\s*,\s*)?upgrade_(path|url)\b|href=['"]<%=\s*upgrade_(path|url)/)
    assert_empty offenders,
      "Views still call upgrade_path/upgrade_url after iny7: #{offenders.join(", ")}"
  end

  # --- Help pages (chatgpt, claude) link to billing, not upgrade ---

  test "chatgpt_help view links to billing_path, not upgrade_path" do
    path = VIEWS_ROOT.join("pages/chatgpt_help.html.erb")
    body = File.read(path)
    refute_match(/\bupgrade_path\b/, body,
      "pages/chatgpt_help.html.erb must not link to upgrade_path")
    assert_match(/\bbilling_path\b/, body,
      "pages/chatgpt_help.html.erb must link to billing_path")
  end

  test "claude_help view links to billing_path, not upgrade_path" do
    path = VIEWS_ROOT.join("pages/claude_help.html.erb")
    body = File.read(path)
    refute_match(/\bupgrade_path\b/, body,
      "pages/claude_help.html.erb must not link to upgrade_path")
    assert_match(/\bbilling_path\b/, body,
      "pages/claude_help.html.erb must link to billing_path")
  end

  test "chatgpt_help no longer promises 'unlimited episodes'" do
    path = VIEWS_ROOT.join("pages/chatgpt_help.html.erb")
    body = File.read(path)
    refute_match(/Upgrade.*unlimited episodes/, body,
      "pages/chatgpt_help.html.erb still pitches unlimited episodes")
  end

  test "claude_help no longer promises 'unlimited episodes'" do
    path = VIEWS_ROOT.join("pages/claude_help.html.erb")
    body = File.read(path)
    refute_match(/Upgrade.*unlimited episodes/, body,
      "pages/claude_help.html.erb still pitches unlimited episodes")
  end

  # --- Header: no unqualified "Upgrade" link ---

  test "shared header does not link to upgrade_path" do
    header = File.read(VIEWS_ROOT.join("shared/_header.html.erb"))
    refute_match(/upgrade_path/, header,
      "Shared header still links to upgrade_path after iny7")
  end

  # --- MCP tool helpers: credit-based error copy ---

  test "McpToolHelpers sends out-of-credits users to /billing, not /upgrade" do
    helpers = File.read(Rails.root.join("app/mcp_tools/mcp_tool_helpers.rb"))
    refute_match(%r{/upgrade"}, helpers,
      "McpToolHelpers error message still points at /upgrade")
    assert_match(%r{/billing}, helpers,
      "McpToolHelpers should direct users to /billing for more credits")
  end

  private

  def grep_views(pattern)
    offenders = []
    Dir.glob(VIEWS_ROOT.join("**/*.erb")).each do |file|
      contents = File.read(file)
      if contents.match?(pattern)
        offenders << file.sub("#{Rails.root}/", "")
      end
    end
    offenders
  end
end
