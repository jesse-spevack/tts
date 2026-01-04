# frozen_string_literal: true

class CreatesUser
  include StructuredLogging

  def self.call(email_address:)
    new(email_address: email_address).call
  end

  def initialize(email_address:)
    @email_address = email_address
  end

  def call
    user = nil
    podcast = nil

    ActiveRecord::Base.transaction do
      user = User.create!(email_address: @email_address)
      podcast = CreatesDefaultPodcast.call(user: user)
    end

    log_info "user_created", user_id: user.id, email: LoggingHelper.mask_email(user.email_address), podcast_id: podcast&.podcast_id

    Result.success(user: user, podcast: podcast)
  rescue ActiveRecord::RecordInvalid
    Result.failure("Could not create user")
  end
end
