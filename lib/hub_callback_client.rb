require "net/http"
require "uri"
require "json"

class HubCallbackClient
  def initialize(hub_url:, callback_secret:)
    @hub_url = hub_url
    @callback_secret = callback_secret
  end

  def notify_complete(episode_id:, episode_data:)
    path = "/api/internal/episodes/#{episode_id}/complete"
    body = {
      gcs_episode_id: episode_data["id"],
      audio_size_bytes: episode_data["file_size_bytes"]
    }
    post_to_hub(path: path, body: body)
  end

  private

  def post_to_hub(path:, body:)
    uri = URI.parse("#{@hub_url}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = 10

    request = Net::HTTP::Post.new(uri.path)
    request["Content-Type"] = "application/json"
    request["X-Generator-Secret"] = @callback_secret
    request.body = body.to_json

    http.request(request)
  end
end
