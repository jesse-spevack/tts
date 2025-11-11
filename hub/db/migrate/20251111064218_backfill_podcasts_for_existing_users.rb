class BackfillPodcastsForExistingUsers < ActiveRecord::Migration[8.1]
  def up
    # Find all users without podcasts
    User.includes(:podcasts).where(podcasts: { id: nil }).find_each do |user|
      # Create default podcast using the service
      podcast = Podcast.create!(
        title: "#{user.email_address}'s Very Normal Podcast",
        description: "My podcast created with tts.verynormal.dev"
      )
      PodcastMembership.create!(user: user, podcast: podcast)

      puts "Created podcast for user: #{user.email_address}"
    end
  end

  def down
    # This is a data migration, we don't want to remove podcasts on rollback
    # as they may have episodes by then
  end
end
