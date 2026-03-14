class ComplimentaryMailerPreview < ActionMailer::Preview
  def welcome
    user = User.find_by(account_type: :complimentary) || User.first
    token = SecureRandom.urlsafe_base64
    ComplimentaryMailer.welcome(user, token: token)
  end
end
