class CreatesDefaultPodcast
  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    podcast = Podcast.create!(
      title: "#{@user.email_address}'s PodRead Podcast",
      description: "My podcast created with #{AppConfig::Domain::HOST}"
    )
    PodcastMembership.create!(user: @user, podcast: podcast)
    podcast
  end
end
