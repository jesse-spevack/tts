require "google/cloud/tasks/v2"

class CloudTasksEnqueuer
  def initialize
    @client = Google::Cloud::Tasks::V2::CloudTasks::Client.new
  end

  # Enqueue episode processing task
  # @param task_payload [Hash] Task data including podcast_id, title, author, description, staging_path
  # @return [String] Task name
  def enqueue_episode_processing(task_payload)
    task = build_task(task_payload)
    response = @client.create_task(parent: queue_path, task: task)
    response.name
  end

  private

  def queue_path
    @client.queue_path(
      project: ENV.fetch("GOOGLE_CLOUD_PROJECT"),
      location: ENV.fetch("CLOUD_TASKS_LOCATION", "us-central1"),
      queue: ENV.fetch("CLOUD_TASKS_QUEUE", "episode-processing")
    )
  end

  def build_task(task_payload)
    {
      http_request: {
        http_method: "POST",
        url: "#{service_url}/process",
        headers: { "Content-Type" => "application/json" },
        body: task_payload.to_json,
        oidc_token: {
          service_account_email: ENV.fetch("SERVICE_ACCOUNT_EMAIL")
        }
      }
    }
  end

  def service_url
    ENV.fetch("SERVICE_URL", "http://localhost:8080")
  end
end
