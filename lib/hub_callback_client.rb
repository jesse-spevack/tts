require "net/http"
require "uri"
require "json"

class HubCallbackClient
  def initialize(hub_url:, callback_secret:)
    @hub_url = hub_url
    @callback_secret = callback_secret
  end

  def notify_complete(episode_id:, episode_data:)
    patch_episode(episode_id, {
      status: "complete",
      gcs_episode_id: episode_data["id"],
      audio_size_bytes: episode_data["file_size_bytes"],
      duration_seconds: episode_data["duration_seconds"]
    })
  end

  def notify_failed(episode_id:, error_message:)
    patch_episode(episode_id, {
      status: "failed",
      error_message: error_message
    })
  end

  private

  def patch_episode(episode_id, body)
    path = "/api/internal/episodes/#{episode_id}"
    patch_to_hub(path: path, body: body)
  end

  def patch_to_hub(path:, body:)
    uri = URI.parse("#{@hub_url}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = 10

    request = Net::HTTP::Patch.new(uri.path)
    request["Content-Type"] = "application/json"
    request["X-Generator-Secret"] = @callback_secret
    request.body = body.to_json

    http.request(request)
  end
end
