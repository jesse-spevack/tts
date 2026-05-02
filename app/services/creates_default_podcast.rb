class CreatesDefaultPodcast
  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    podcast = Podcast.create!(
      title: "PodRead Podcast: #{@user.email_address}",
      description: "My podcast created with #{AppConfig::Domain::HOST}"
    )
    PodcastMembership.create!(user: @user, podcast: podcast)
    podcast
  end
end
