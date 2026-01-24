# frozen_string_literal: true

class EpisodesMailbox < ApplicationMailbox
  include StructuredLogging

  def process
    log_info "email_received", from: sender_email, subject: mail.subject

    unless user
      log_info "unknown_sender", email: sender_email
      return
    end

    result = CreatesEmailEpisode.call(user: user, email_body: email_content)

    if result.success?
      log_info "email_episode_created", episode_id: result.data.id
      send_success_notification(result.data) if user.email_episode_confirmation?
    else
      log_warn "email_episode_failed", error: result.error
      send_failure_notification(result.error)
    end
  end

  private

  def user
    @user ||= User.find_by(email_address: sender_email)
  end

  def sender_email
    mail.from.first&.downcase
  end

  def email_content
    ExtractsEmailContent.call(mail: mail)
  end

  def send_success_notification(episode)
    EmailEpisodeMailer.episode_created(episode: episode).deliver_later
  end

  def send_failure_notification(error)
    EmailEpisodeMailer.episode_failed(user: user, error: error).deliver_later
  end
end
