require "google/cloud/tasks"

class CloudTasksEnqueuer
  def enqueue_episode_processing(episode_id:, podcast_id:, staging_path:, metadata:)
    client = build_client

    parent = client.queue_path(
      project: ENV.fetch("GOOGLE_CLOUD_PROJECT"),
      location: ENV.fetch("CLOUD_TASKS_LOCATION"),
      queue: ENV.fetch("CLOUD_TASKS_QUEUE")
    )

    task = {
      http_request: {
        http_method: "POST",
        url: "#{ENV.fetch('GENERATOR_SERVICE_URL')}/process",
        headers: { "Content-Type" => "application/json" },
        body: {
          episode_id: episode_id,
          podcast_id: podcast_id,
          staging_path: staging_path,
          title: metadata[:title],
          author: metadata[:author],
          description: metadata[:description]
        }.to_json.force_encoding("ASCII-8BIT"),
        oidc_token: {
          service_account_email: ENV.fetch("SERVICE_ACCOUNT_EMAIL")
        }
      }
    }

    response = client.create_task(parent: parent, task: task)
    response.name
  end

  private

  def build_client
    ENV["GOOGLE_CLOUD_CREDENTIALS"] ||= GoogleCredentials.from_env.to_json
    Google::Cloud::Tasks.cloud_tasks
  end
end
