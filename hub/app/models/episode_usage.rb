class EpisodeUsage < ApplicationRecord
  belongs_to :user

  validates :period_start, presence: true
  validates :episode_count, numericality: { greater_than_or_equal_to: 0 }

  def self.current_for(user)
    find_or_initialize_by(
      user: user,
      period_start: Time.current.beginning_of_month.to_date
    )
  end

  def increment!
    with_lock do
      self.episode_count += 1
      save!
    end
  end

  def decrement!
    with_lock do
      self.episode_count = [ episode_count - 1, 0 ].max
      save!
    end
  end
end
