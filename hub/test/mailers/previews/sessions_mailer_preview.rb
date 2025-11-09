# Preview all emails at http://localhost:3000/rails/mailers/sessions_mailer
class SessionsMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/sessions_mailer/magic_link
  def magic_link
    user = User.new(
      id: 1,
      email_address: "preview@example.com"
    )
    token = "preview_token_abc123xyz"

    SessionsMailer.magic_link(user: user, token: token)
  end
end
