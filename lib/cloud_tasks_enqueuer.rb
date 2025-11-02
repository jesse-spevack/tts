require "google/cloud/tasks/v2"

class CloudTasksEnqueuer
  def initialize
    @client = Google::Cloud::Tasks::V2::CloudTasks::Client.new
  end

  def enqueue_episode_processing(title, author, description, staging_path)
    task = build_task(title, author, description, staging_path)
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

  def build_task(title, author, description, staging_path)
    {
      http_request: {
        http_method: "POST",
        url: "#{service_url}/process",
        headers: { "Content-Type" => "application/json" },
        body: build_payload(title, author, description, staging_path).to_json
      }
    }
  end

  def build_payload(title, author, description, staging_path)
    {
      title: title,
      author: author,
      description: description,
      staging_path: staging_path
    }
  end

  def service_url
    ENV.fetch("SERVICE_URL", "http://localhost:8080")
  end
end
