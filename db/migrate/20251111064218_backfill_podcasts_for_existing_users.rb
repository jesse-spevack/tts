class BackfillPodcastsForExistingUsers < ActiveRecord::Migration[8.1]
  # Anonymous AR classes scoped to just the columns this migration needs.
  # Avoids loading the live models, which evolve over time and may declare
  # enums/validations against columns that don't yet exist at this migration's
  # point in history (e.g. User#account_type is added in a later migration).
  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
    has_many :podcast_memberships, foreign_key: :user_id, class_name: "BackfillPodcastsForExistingUsers::MigrationPodcastMembership"
    has_many :podcasts, through: :podcast_memberships
  end

  class MigrationPodcast < ActiveRecord::Base
    self.table_name = "podcasts"

    before_validation :generate_podcast_id, on: :create

    private

    def generate_podcast_id
      self.podcast_id ||= "podcast_#{SecureRandom.hex(8)}"
    end
  end

  class MigrationPodcastMembership < ActiveRecord::Base
    self.table_name = "podcast_memberships"
    belongs_to :user, class_name: "BackfillPodcastsForExistingUsers::MigrationUser"
    belongs_to :podcast, class_name: "BackfillPodcastsForExistingUsers::MigrationPodcast"
  end

  def up
    # Find all users without podcasts
    MigrationUser.includes(:podcasts).where(podcasts: { id: nil }).find_each do |user|
      # Create default podcast
      podcast = MigrationPodcast.create!(
        title: "#{user.email_address}'s Very Normal Podcast",
        description: "My podcast created with tts.verynormal.dev"
      )
      MigrationPodcastMembership.create!(user: user, podcast: podcast)

      say "Created podcast for user: #{user.email_address}"
    end
  end

  def down
    # This is a data migration, we don't want to remove podcasts on rollback
    # as they may have episodes by then
  end
end
