# frozen_string_literal: true

require "test_helper"

class RoutesResendInboundEmailTest < ActiveSupport::TestCase
  # Address matching the ApplicationMailbox route pattern so routing succeeds.
  ROUTABLE_TO = "readtome+test_token_123@example.com"

  setup do
    users(:one).update!(email_episodes_enabled: true, email_ingest_token: "test_token_123")
  end

  test "creates ActionMailbox::InboundEmail and returns success" do
    email_data = {
      "from" => "sender@example.com",
      "to" => [ ROUTABLE_TO ],
      "subject" => "Test Subject",
      "html" => "<p>body</p>",
      "text" => "body",
      "message_id" => "<test123@example.com>"
    }

    assert_difference "ActionMailbox::InboundEmail.count", 1 do
      result = RoutesResendInboundEmail.call(email_data: email_data)
      assert result.success?
    end
  end

  test "builds mail with from, to, and subject from email data" do
    email_data = {
      "from" => "alice@example.com",
      "to" => [ ROUTABLE_TO ],
      "subject" => "Hello",
      "text" => "world"
    }

    RoutesResendInboundEmail.call(email_data: email_data)

    inbound = ActionMailbox::InboundEmail.last
    mail = inbound.mail
    assert_equal "alice@example.com", mail.from.first
    assert_equal ROUTABLE_TO, mail.to.first
    assert_equal "Hello", mail.subject
  end

  test "includes html part when html is present" do
    email_data = {
      "from" => "a@example.com",
      "to" => [ ROUTABLE_TO ],
      "subject" => "Subj",
      "html" => "<p>hello</p>"
    }

    RoutesResendInboundEmail.call(email_data: email_data)

    inbound = ActionMailbox::InboundEmail.last
    html_part = inbound.mail.html_part
    assert_not_nil html_part
    assert_includes html_part.body.to_s, "<p>hello</p>"
  end

  test "includes text part when text is present" do
    email_data = {
      "from" => "a@example.com",
      "to" => [ ROUTABLE_TO ],
      "subject" => "Subj",
      "text" => "plain body"
    }

    RoutesResendInboundEmail.call(email_data: email_data)

    inbound = ActionMailbox::InboundEmail.last
    text_part = inbound.mail.text_part
    assert_not_nil text_part
    assert_includes text_part.body.to_s, "plain body"
  end

  test "sets message_id when provided" do
    email_data = {
      "from" => "a@example.com",
      "to" => [ ROUTABLE_TO ],
      "subject" => "Subj",
      "text" => "hi",
      "message_id" => "<abc123@example.com>"
    }

    RoutesResendInboundEmail.call(email_data: email_data)

    inbound = ActionMailbox::InboundEmail.last
    assert_equal "abc123@example.com", inbound.message_id
  end

  test "returns success with the created InboundEmail as data" do
    email_data = {
      "from" => "a@example.com",
      "to" => [ ROUTABLE_TO ],
      "subject" => "Subj",
      "text" => "hi"
    }

    result = RoutesResendInboundEmail.call(email_data: email_data)

    assert result.success?
    assert_kind_of ActionMailbox::InboundEmail, result.data
  end

  # Belt-and-suspenders (agent-team-qy30): ActionMailbox::InboundEmail
  # .create_and_extract_message_id! rescues ActiveRecord::RecordNotUnique
  # internally and returns nil when the Message-ID is a duplicate. The service
  # currently dereferences .id on that nil → NoMethodError → controller's
  # rescue StandardError → 500 → Svix retry storm. Even with controller-level
  # svix-id dedup, two concurrent deliveries with the same Message-ID could
  # both pass the DB check and race into this path; the service must treat
  # a nil return as "already processed" and return Result.success.
  test "returns success when ActionMailbox reports duplicate Message-ID (agent-team-qy30)" do
    email_data = {
      "from" => "sender@example.com",
      "to" => [ ROUTABLE_TO ],
      "subject" => "Dup",
      "text" => "body",
      "message_id" => "<already-seen@example.com>"
    }

    Mocktail.replace(ActionMailbox::InboundEmail)
    stubs { |m| ActionMailbox::InboundEmail.create_and_extract_message_id!(m.any) }.with { nil }

    result = nil
    assert_nothing_raised do
      result = RoutesResendInboundEmail.call(email_data: email_data)
    end

    assert_not_nil result
    assert result.success?, "expected success Result when Message-ID is a duplicate; got #{result.inspect}"
  end
end
