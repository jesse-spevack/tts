# frozen_string_literal: true

module EpisodeLogging
  extend ActiveSupport::Concern
  include StructuredLogging

  private

  def default_log_context
    super.merge(episode_id: episode&.id).compact
  end

  def episode
    raise NotImplementedError, "#{self.class} must define #episode to use EpisodeLogging"
  end
end
