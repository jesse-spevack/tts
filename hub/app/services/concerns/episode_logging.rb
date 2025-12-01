# frozen_string_literal: true

module EpisodeLogging
  private

  # Including class must define this method
  def episode
    raise NotImplementedError, "#{self.class} must define #episode to use EpisodeLogging"
  end

  def log_info(event, **attrs)
    Rails.logger.info build_log_message(event, attrs)
  end

  def log_warn(event, **attrs)
    Rails.logger.warn build_log_message(event, attrs)
  end

  def log_error(event, **attrs)
    Rails.logger.error build_log_message(event, attrs)
  end

  def build_log_message(event, attrs)
    parts = [ "event=#{event}", "episode_id=#{episode.id}" ]
    attrs.each { |k, v| parts << "#{k}=#{v}" }
    parts.join(" ")
  end
end
