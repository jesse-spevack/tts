require "test_helper"

class SessionsMailerTest < ActionMailer::TestCase
  test "magic_link" do
    user = users(:one)
    GenerateAuthToken.call(user: user)

    mail = SessionsMailer.magic_link(user)
    assert_equal "🎙️ Your TTS Login Link", mail.subject
    assert_equal [ user.email_address ], mail.to
    assert_match user.auth_token, mail.body.encoded
  end
end
