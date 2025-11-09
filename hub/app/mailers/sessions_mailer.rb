class SessionsMailer < ApplicationMailer
  def magic_link(user)
    @user = user
    @magic_link_url = new_session_url(token: @user.auth_token)

    mail(
      to: @user.email_address,
      subject: "Your Magic Login Link"
    )
  end
end
