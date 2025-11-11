class CreateDefaultPodcast
  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    podcast = Podcast.create!(
      title: "#{@user.email_address}'s Very Normal Podcast",
      description: "My podcast created with tts.verynormal.dev"
    )
    PodcastMembership.create!(user: @user, podcast: podcast)
    podcast
  end
end
