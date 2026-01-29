# frozen_string_literal: true

module Webhooks
  class ResendController < ApplicationController
    include StructuredLogging

    skip_before_action :verify_authenticity_token
    allow_unauthenticated_access

    def inbound
      unless verify_webhook_signature
        log_warn "resend_webhook_invalid_signature"
        return head :unauthorized
      end

      event = JSON.parse(request.body.read)

      unless event["type"] == "email.received"
        log_info "resend_webhook_ignored", event_type: event["type"]
        return head :ok
      end

      email_id = event.dig("data", "email_id")
      unless email_id
        log_warn "resend_webhook_missing_email_id"
        return head :bad_request
      end

      # Fetch full email content from Resend API
      email_data = fetch_email_content(email_id)
      unless email_data
        log_error "resend_webhook_fetch_failed", email_id: email_id
        return head :unprocessable_entity
      end

      # Route to the appropriate mailbox
      process_inbound_email(email_data)

      head :ok
    rescue JSON::ParserError => e
      log_error "resend_webhook_invalid_json", error: e.message
      head :bad_request
    rescue StandardError => e
      log_error "resend_webhook_error", error_class: e.class.name, error: e.message
      head :internal_server_error
    end

    private

    def verify_webhook_signature
      webhook_secret = ENV["RESEND_WEBHOOK_SECRET"]
      return false unless webhook_secret.present?

      payload = request.body.read
      request.body.rewind

      svix_id = request.headers["svix-id"]
      svix_timestamp = request.headers["svix-timestamp"]
      svix_signature = request.headers["svix-signature"]

      return false unless svix_id && svix_timestamp && svix_signature

      # Verify timestamp is within 5 minutes
      timestamp = svix_timestamp.to_i
      return false if (Time.now.to_i - timestamp).abs > 300

      # Compute expected signature
      signed_content = "#{svix_id}.#{svix_timestamp}.#{payload}"

      # svix_signature can contain multiple signatures (v1,signature v1,signature2)
      svix_signature.split(" ").any? do |versioned_sig|
        version, signature = versioned_sig.split(",", 2)
        next false unless version == "v1" && signature

        expected = Base64.strict_encode64(
          OpenSSL::HMAC.digest("SHA256", Base64.decode64(webhook_secret.sub(/^whsec_/, "")), signed_content)
        )
        ActiveSupport::SecurityUtils.secure_compare(expected, signature)
      end
    end

    def fetch_email_content(email_id)
      api_key = ENV["RESEND_API_KEY"]
      return nil unless api_key.present?

      uri = URI("https://api.resend.com/emails/receiving/#{email_id}")
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{api_key}"

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end

      if response.is_a?(Net::HTTPSuccess)
        JSON.parse(response.body)
      else
        log_error "resend_api_error", status: response.code, body: response.body.truncate(200)
        nil
      end
    end

    def process_inbound_email(email_data)
      # Build a Mail object from the Resend data
      mail = build_mail_from_resend(email_data)

      # Create an ActionMailbox InboundEmail and route it
      inbound_email = ActionMailbox::InboundEmail.create_and_extract_message_id!(mail.to_s)

      log_info "resend_inbound_email_created", inbound_email_id: inbound_email.id, to: email_data["to"]&.first

      inbound_email.route
    end

    def build_mail_from_resend(email_data)
      Mail.new do
        from    email_data["from"]
        to      email_data["to"]
        subject email_data["subject"]

        if email_data["html"].present?
          html_part do
            content_type "text/html; charset=UTF-8"
            body email_data["html"]
          end
        end

        if email_data["text"].present?
          text_part do
            body email_data["text"]
          end
        end

        # Set message ID if available
        if email_data["message_id"].present?
          message_id email_data["message_id"]
        end
      end
    end
  end
end
