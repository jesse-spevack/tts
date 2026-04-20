# frozen_string_literal: true

class RoutesResendInboundEmail
  include StructuredLogging

  def self.call(email_data:)
    new(email_data: email_data).call
  end

  def initialize(email_data:)
    @email_data = email_data
  end

  def call
    mail = build_mail
    inbound_email = ActionMailbox::InboundEmail.create_and_extract_message_id!(mail.to_s)

    log_info "resend_inbound_email_created",
      inbound_email_id: inbound_email.id,
      to: email_data["to"]&.first

    inbound_email.route

    Result.success(inbound_email)
  end

  private

  attr_reader :email_data

  def build_mail
    data = email_data
    Mail.new do
      from    data["from"]
      to      data["to"]
      subject data["subject"]

      if data["html"].present?
        html_part do
          content_type "text/html; charset=UTF-8"
          body data["html"]
        end
      end

      if data["text"].present?
        text_part do
          body data["text"]
        end
      end

      message_id data["message_id"] if data["message_id"].present?
    end
  end
end
