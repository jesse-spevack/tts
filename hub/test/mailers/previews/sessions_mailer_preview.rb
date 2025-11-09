# Preview all emails at http://localhost:3000/rails/mailers/sessions_mailer
class SessionsMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/sessions_mailer/magic_link
  def magic_link
    SessionsMailer.magic_link
  end
end
