class SessionsMailer < ApplicationMailer
  def magic_link(user:, token:, plan: nil)
    @user = user
    @magic_link_url = auth_url(token: token, plan: plan.presence)

    mail(
      to: @user.email_address,
      subject: "🎙️ Your TTS Login Link"
    )
  end
end
