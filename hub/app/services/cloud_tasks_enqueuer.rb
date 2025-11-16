require "google/cloud/tasks"

class CloudTasksEnqueuer
  def enqueue_episode_processing(episode_id:, podcast_id:, staging_path:, metadata:)
    client = Google::Cloud::Tasks.cloud_tasks

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
        }.to_json,
        oidc_token: {
          service_account_email: ENV.fetch("SERVICE_ACCOUNT_EMAIL")
        }
      }
    }

    client.create_task(parent: parent, task: task)
  end
end
