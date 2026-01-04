module EpisodesHelper
  def status_badge(status)
    case status
    when "pending"
      content_tag :span, class: "inline-flex items-center gap-1 text-sm" do
        content_tag(:span, "●", class: "text-[var(--color-yellow)]") +
        content_tag(:span, "Pending")
      end
    when "processing"
      content_tag :span, class: "inline-flex items-center gap-1 text-sm" do
        content_tag(:span, "●", class: "text-[var(--color-yellow)] animate-pulse") +
        content_tag(:span, "Processing")
      end
    when "complete"
      content_tag :span, class: "inline-flex items-center gap-1 text-sm" do
        content_tag(:span, "✓", class: "text-[var(--color-green)]") +
        content_tag(:span, "Completed")
      end
    when "failed"
      content_tag :span, class: "inline-flex items-center gap-1 text-sm" do
        content_tag(:span, "✗", class: "text-[var(--color-red)]") +
        content_tag(:span, "Failed")
      end
    else
      content_tag :span, status, class: "text-sm text-[var(--color-subtext)]"
    end
  end

  def format_duration(duration_seconds)
    FormatsDuration.call(duration_seconds)
  end

  def deletable?(episode)
    episode.user_id == Current.user&.id
  end
end
