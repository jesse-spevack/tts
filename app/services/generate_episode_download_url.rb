# frozen_string_literal: true

require "google/cloud/storage"
require "google/apis/iamcredentials_v1"
require "googleauth"

class GenerateEpisodeDownloadUrl
  def self.call(episode)
    new(episode).call
  end

  def initialize(episode)
    @episode = episode
  end

  def call
    return nil unless @episode.complete? && @episode.gcs_episode_id.present?

    file.signed_url(
      method: "GET",
      expires: 300,
      query: {
        "response-content-disposition" => "attachment; filename=\"#{filename}\""
      },
      **signing_options
    )
  end

  private

  def signing_options
    return {} if has_service_account_credentials?

    { issuer: service_account_email, signer: iam_signer }
  end

  def has_service_account_credentials?
    # Check if we have a JSON keyfile with signing capability
    ENV["GOOGLE_APPLICATION_CREDENTIALS"].present? &&
      File.exist?(ENV["GOOGLE_APPLICATION_CREDENTIALS"])
  end

  def service_account_email
    ENV.fetch("SERVICE_ACCOUNT_EMAIL")
  end

  def iam_signer
    lambda do |string_to_sign|
      iam_client = Google::Apis::IamcredentialsV1::IAMCredentialsService.new
      iam_client.authorization = Google::Auth.get_application_default(
        [ "https://www.googleapis.com/auth/iam" ]
      )

      request = Google::Apis::IamcredentialsV1::SignBlobRequest.new(
        payload: string_to_sign
      )
      resource = "projects/-/serviceAccounts/#{service_account_email}"
      response = iam_client.sign_service_account_blob(resource, request)
      response.signed_blob
    end
  end

  def file
    bucket.file(file_path)
  end

  def bucket
    storage.bucket(bucket_name)
  end

  def storage
    Google::Cloud::Storage.new(project_id: ENV["GOOGLE_CLOUD_PROJECT"])
  end

  def bucket_name
    AppConfig::Storage::BUCKET
  end

  def file_path
    "podcasts/#{@episode.podcast.podcast_id}/episodes/#{@episode.gcs_episode_id}.mp3"
  end

  def filename
    "#{@episode.title.parameterize}.mp3"
  end
end
