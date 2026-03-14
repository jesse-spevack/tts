class ComplimentaryMailer < ApplicationMailer
  def welcome(user, token:)
    @user = user
    @magic_link_url = auth_url(token: token)
    @new_episode_url = new_episode_url

    mail(
      to: user.email_address,
      subject: "A little gift for you — PodRead is yours"
    )
  end
end
