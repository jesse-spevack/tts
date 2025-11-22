class SessionsMailer < ApplicationMailer
  def magic_link(user:, token:)
    @user = user
    @magic_link_url = root_url(token: token)

    mail(
      to: @user.email_address,
      subject: "🎙️ Your TTS Login Link"
    )
  end
end
