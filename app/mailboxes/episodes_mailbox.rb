# frozen_string_literal: true

class EpisodesMailbox < ApplicationMailbox
  include StructuredLogging

  def process
    log_info "email_received", to: recipient_email, from: sender_email, subject: mail.subject

    unless user
      log_info "invalid_token", token: extract_token_from_recipient
      return
    end

    rate_limit_result = ChecksEpisodeRateLimit.call(user: user)
    unless rate_limit_result.success?
      log_warn "email_episode_rate_limited", user_id: user.id
      send_failure_notification(rate_limit_result.error)
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
    @user ||= find_user_by_token
  end

  def find_user_by_token
    token = extract_token_from_recipient
    return nil unless token

    User.find_by(email_ingest_token: token, email_episodes_enabled: true)
  end

  def extract_token_from_recipient
    return nil unless recipient_email

    match = recipient_email.match(/^readtome\+([^@]+)@/i)
    match&.[](1)
  end

  def recipient_email
    mail.to.first&.downcase
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
