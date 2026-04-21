# frozen_string_literal: true

module Webhooks
  class ResendController < ApplicationController
    include StructuredLogging

    skip_before_action :verify_authenticity_token
    allow_unauthenticated_access

    def inbound
      raw_payload = request.body.read

      verification = VerifiesResendSignature.call(
        headers: request.headers,
        raw_payload: raw_payload,
        secret: ENV["RESEND_WEBHOOK_SECRET"]
      )
      unless verification.success?
        log_warn "resend_webhook_invalid_signature"
        return head :unauthorized
      end

      svix_id = request.headers["svix-id"]
      if svix_id.blank?
        log_warn "resend_webhook_missing_svix_id"
        return head :bad_request
      end

      event = JSON.parse(raw_payload)

      begin
        WebhookEvent.create!(
          provider: "resend",
          event_id: svix_id,
          event_type: event["type"],
          received_at: Time.current
        )
      rescue ActiveRecord::RecordNotUnique
        log_info "resend_webhook_duplicate_ignored", svix_id: svix_id, event_type: event["type"]
        return head :ok
      rescue ActiveRecord::RecordInvalid => e
        if e.record&.errors&.of_kind?(:event_id, :taken)
          log_info "resend_webhook_duplicate_ignored", svix_id: svix_id, event_type: event["type"]
          return head :ok
        end
        raise
      end

      unless event["type"] == "email.received"
        log_info "resend_webhook_ignored", event_type: event["type"]
        return head :ok
      end

      email_id = event.dig("data", "email_id")
      unless email_id
        log_warn "resend_webhook_missing_email_id"
        return head :bad_request
      end

      fetched = FetchesResendEmail.call(email_id: email_id)
      unless fetched.success?
        log_error "resend_webhook_fetch_failed", email_id: email_id
        return head :unprocessable_entity
      end

      RoutesResendInboundEmail.call(email_data: fetched.data)

      head :ok
    rescue JSON::ParserError => e
      log_error "resend_webhook_invalid_json", error: e.message, exception: e
      head :bad_request
    rescue StandardError => e
      log_error "resend_webhook_error", error_class: e.class.name, error: e.message, exception: e
      head :internal_server_error
    end
  end
end
