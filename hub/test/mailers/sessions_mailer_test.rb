require "test_helper"

class SessionsMailerTest < ActionMailer::TestCase
  test "magic_link" do
    user = users(:one)
    token = GenerateAuthToken.call(user: user)

    mail = SessionsMailer.magic_link(user: user, token: token)
    assert_equal "🎙️ Your TTS Login Link", mail.subject
    assert_equal [ user.email_address ], mail.to
    assert_match token, mail.body.encoded
  end
end
