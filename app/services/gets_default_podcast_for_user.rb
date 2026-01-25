class GetsDefaultPodcastForUser
  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    @user.podcasts.first || CreatesDefaultPodcast.call(user: @user)
  end
end
