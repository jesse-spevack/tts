class SessionsMailer < ApplicationMailer
  def magic_link(user:, token:, plan: nil, pack_size: nil)
    @user = user
    @magic_link_url = auth_url(token: token, plan: plan.presence, pack_size: pack_size.presence)

    mail(
      to: @user.email_address,
      subject: "🎙️ Your PodRead Login Link"
    )
  end
end
