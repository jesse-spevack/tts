# frozen_string_literal: true

class ExtractsEmailContent
  include StructuredLogging

  def self.call(mail:)
    new(mail: mail).call
  end

  def initialize(mail:)
    @mail = mail
  end

  def call
    content = extract_content
    log_info "email_content_extracted", length: content.length, source: content_source
    content
  end

  private

  attr_reader :mail

  def extract_content
    if mail.text_part.present?
      @content_source = "text_part"
      mail.text_part.decoded
    elsif mail.html_part.present?
      @content_source = "html_part"
      strip_html(mail.html_part.decoded)
    elsif mail.body.present?
      body = mail.body.decoded
      if html_content?(body)
        @content_source = "body_html"
        strip_html(body)
      else
        @content_source = "body_text"
        body
      end
    else
      @content_source = "empty"
      ""
    end
  end

  def content_source
    @content_source || "unknown"
  end

  def strip_html(html)
    ActionController::Base.helpers.strip_tags(html).gsub(/\s+/, " ").strip
  end

  def html_content?(text)
    text.include?("<html") || text.include?("<body") || text.include?("<div") || text.include?("<p>")
  end
end
