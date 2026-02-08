# frozen_string_literal: true

require "test_helper"

class ExtractsEmailContentTest < ActiveSupport::TestCase
  test "extracts plain text from text_part" do
    mail = create_mail(text: "Hello, this is plain text content.")

    content = ExtractsEmailContent.call(mail: mail)

    assert_equal "Hello, this is plain text content.", content
  end

  test "strips HTML from html_part when no text_part" do
    mail = create_mail(html: "<p>Hello, this is <strong>HTML</strong> content.</p>")

    content = ExtractsEmailContent.call(mail: mail)

    assert_equal "Hello, this is HTML content.", content
  end

  test "prefers text_part over html_part" do
    mail = create_mail(
      text: "Plain text version",
      html: "<p>HTML version</p>"
    )

    content = ExtractsEmailContent.call(mail: mail)

    assert_equal "Plain text version", content
  end

  test "handles plain text body without parts" do
    mail = Mail.new do
      from "sender@example.com"
      to "readtome@example.com"
      subject "Test"
      body "Simple body content"
    end

    content = ExtractsEmailContent.call(mail: mail)

    assert_equal "Simple body content", content
  end

  test "strips HTML from body when body contains HTML" do
    mail = Mail.new do
      from "sender@example.com"
      to "readtome@example.com"
      subject "Test"
      body "<html><body><p>HTML body</p></body></html>"
    end

    content = ExtractsEmailContent.call(mail: mail)

    assert_equal "HTML body", content
  end

  test "returns empty string when no content" do
    mail = Mail.new do
      from "sender@example.com"
      to "readtome@example.com"
      subject "Test"
    end

    content = ExtractsEmailContent.call(mail: mail)

    assert_equal "", content
  end

  test "normalizes whitespace in HTML content" do
    mail = create_mail(html: "<p>Multiple   spaces\n\nand\nnewlines</p>")

    content = ExtractsEmailContent.call(mail: mail)

    assert_equal "Multiple spaces and newlines", content
  end

  private

  def create_mail(text: nil, html: nil)
    Mail.new do
      from "sender@example.com"
      to "readtome@example.com"
      subject "Test Subject"

      if text && html
        text_part { body text }
        html_part { content_type "text/html; charset=UTF-8"; body html }
      elsif text
        text_part { body text }
      elsif html
        html_part { content_type "text/html; charset=UTF-8"; body html }
      end
    end
  end
end
