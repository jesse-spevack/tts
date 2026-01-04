require "test_helper"

class SessionsMailerTest < ActionMailer::TestCase
  test "magic_link" do
    user = users(:one)
    token = GeneratesAuthToken.call(user: user)

    mail = SessionsMailer.magic_link(user: user, token: token)
    assert_equal "🎙️ Your Very Normal TTS Login Link", mail.subject
    assert_equal [ user.email_address ], mail.to
    assert_match token, mail.body.encoded
  end

  test "magic_link uses root url not session/new" do
    user = users(:one)
    token = GeneratesAuthToken.call(user: user)

    mail = SessionsMailer.magic_link(user: user, token: token)

    # The URL should use root path (/?token=) not /session/new which redirects and loses the token
    assert_no_match %r{/session/new}, mail.body.encoded
    assert_match %r{\?token=#{token}}, mail.body.encoded
  end
end
