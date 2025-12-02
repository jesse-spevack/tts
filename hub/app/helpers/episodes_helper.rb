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
    return nil unless duration_seconds

    minutes = duration_seconds / 60
    seconds = duration_seconds % 60
    format("%d:%02d", minutes, seconds)
  end

  # Keep old method for backwards compatibility during migration
  def status_class(status)
    case status
    when "pending"
      "bg-yellow-100 text-yellow-800"
    when "processing"
      "bg-blue-100 text-blue-800"
    when "complete"
      "bg-green-100 text-green-800"
    when "failed"
      "bg-red-100 text-red-800"
    else
      "bg-gray-100 text-gray-800"
    end
  end
end
