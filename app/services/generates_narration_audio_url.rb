# frozen_string_literal: true

require "google/cloud/storage"
require "google/apis/iamcredentials_v1"
require "googleauth"

# Generates signed download URLs for narration MP3 files stored in GCS.
#
# Mirrors GeneratesEpisodeDownloadUrl: the GCS bucket is private, so anonymous
# GET on a raw https://storage.googleapis.com/<bucket>/... URL returns
# AccessDenied. Narration audio is uploaded by ProcessesNarration to
# gs://<BUCKET>/narrations/<gcs_episode_id>.mp3 and needs an IAM-signed URL
# to be reachable by an MPP buyer holding the returned audio_url.
#
# Uses IAM signBlob API because GCE metadata server credentials can't sign
# URLs directly (no private key). The VM's service account must have
# roles/iam.serviceAccountTokenCreator on SERVICE_ACCOUNT_EMAIL to sign.
#
class GeneratesNarrationAudioUrl
  def self.call(narration)
    new(narration).call
  end

  def initialize(narration)
    @narration = narration
  end

  def call
    return nil unless narration.complete? && narration.gcs_episode_id.present?

    file.signed_url(
      method: "GET",
      expires: AppConfig::Storage::SIGNED_URL_EXPIRY_SECONDS,
      query: {
        "response-content-disposition" => "attachment; filename=\"#{filename}\""
      },
      issuer: service_account_email,
      signer: iam_signer
    )
  end

  private

  attr_reader :narration

  def service_account_email
    ENV.fetch("SERVICE_ACCOUNT_EMAIL")
  end

  def iam_signer
    lambda do |string_to_sign|
      iam = Google::Apis::IamcredentialsV1::IAMCredentialsService.new
      iam.authorization = Google::Auth.get_application_default(
        [ "https://www.googleapis.com/auth/iam" ]
      )

      request = Google::Apis::IamcredentialsV1::SignBlobRequest.new(
        payload: string_to_sign
      )
      response = iam.sign_service_account_blob(
        "projects/-/serviceAccounts/#{service_account_email}",
        request
      )
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
    "narrations/#{narration.gcs_episode_id}.mp3"
  end

  def filename
    base = narration.title.presence || narration.gcs_episode_id
    "#{base.parameterize}.mp3"
  end
end
