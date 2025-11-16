require "minitest/autorun"
require "webmock/minitest"
require_relative "../lib/hub_callback_client"

class TestHubCallbackClient < Minitest::Test
  def setup
    @hub_url = "https://hub.example.com"
    @secret = "test-secret-token"
    @client = HubCallbackClient.new(hub_url: @hub_url, callback_secret: @secret)
  end

  def test_notify_complete_sends_correct_request
    episode_id = 123
    episode_data = {
      "id" => "episode_abc123",
      "file_size_bytes" => 5242880
    }

    stub_request(:post, "#{@hub_url}/api/internal/episodes/#{episode_id}/complete")
      .with(
        headers: {
          "Content-Type" => "application/json",
          "X-Generator-Secret" => @secret
        },
        body: {
          gcs_episode_id: "episode_abc123",
          audio_size_bytes: 5242880
        }.to_json
      )
      .to_return(status: 200, body: '{"status":"success"}')

    response = @client.notify_complete(episode_id: episode_id, episode_data: episode_data)

    assert_equal "200", response.code
  end

  def test_notify_complete_uses_https
    stub_request(:post, "#{@hub_url}/api/internal/episodes/1/complete")
      .to_return(status: 200)

    @client.notify_complete(episode_id: 1, episode_data: { "id" => "x", "file_size_bytes" => 1 })

    assert_requested(:post, "https://hub.example.com/api/internal/episodes/1/complete")
  end
end
