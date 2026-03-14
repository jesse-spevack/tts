require "test_helper"

class ComplimentaryMailerTest < ActionMailer::TestCase
  test "welcome sends to user email" do
    user = users(:complimentary_user)
    token = GeneratesAuthToken.call(user: user)

    mail = ComplimentaryMailer.welcome(user, token: token)

    assert_equal [ user.email_address ], mail.to
  end

  test "welcome has correct subject" do
    user = users(:complimentary_user)
    token = GeneratesAuthToken.call(user: user)

    mail = ComplimentaryMailer.welcome(user, token: token)

    assert_equal "A little gift for you — PodRead is yours", mail.subject
  end

  test "welcome includes magic link with token" do
    user = users(:complimentary_user)
    token = GeneratesAuthToken.call(user: user)

    mail = ComplimentaryMailer.welcome(user, token: token)

    assert_match token, mail.body.encoded
    assert_match "auth", mail.body.encoded
  end

  test "welcome describes complimentary benefits" do
    user = users(:complimentary_user)
    token = GeneratesAuthToken.call(user: user)

    mail = ComplimentaryMailer.welcome(user, token: token)
    body = mail.body.encoded

    assert_match "Unlimited episodes", body
    assert_match "50,000 characters", body
    assert_match "12 voices", body
    assert_match "highest quality", body
  end

  test "welcome includes login button" do
    user = users(:complimentary_user)
    token = GeneratesAuthToken.call(user: user)

    mail = ComplimentaryMailer.welcome(user, token: token)

    assert_match "Log in and get started", mail.body.encoded
  end
end
