# frozen_string_literal: true

require "test_helper"

class HelpClaudeTest < ActionDispatch::IntegrationTest
  test "help/claude page is accessible without authentication" do
    get "/help/claude"
    assert_response :success
  end

  test "help/claude page shows setup instructions" do
    get "/help/claude"
    assert_response :success
    assert_match "Connect PodRead to Claude", response.body
    assert_match "/mcp", response.body
    assert_match "Allow", response.body
  end

  test "help/claude page shows available tools" do
    get "/help/claude"
    assert_match "create_episode_from_url", response.body
    assert_match "create_episode_from_text", response.body
    assert_match "list_episodes", response.body
    assert_match "get_episode", response.body
    assert_match "delete_episode", response.body
    assert_match "get_feed_url", response.body
    assert_match "list_voices", response.body
  end

  test "help/claude page shows example prompts" do
    get "/help/claude"
    assert_match "Turn this article into a podcast episode", response.body
  end

  test "help/claude page shows troubleshooting" do
    get "/help/claude"
    assert_match "Troubleshooting", response.body
  end

  test "help nav includes Claude link" do
    get "/help/claude"
    assert_match "Claude", response.body
  end
end
