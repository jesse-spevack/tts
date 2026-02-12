module EpisodesHelper
  def status_badge(status)
    case status
    when "pending"
      content_tag :span, class: "inline-flex items-center gap-1 text-sm" do
        content_tag(:span, "●", class: "text-yellow-500 dark:text-yellow-300") +
        content_tag(:span, "Pending")
      end
    when "processing"
      content_tag :span, class: "inline-flex items-center gap-1 text-sm" do
        content_tag(:span, "●", class: "text-yellow-500 dark:text-yellow-300 animate-pulse") +
        content_tag(:span, "Processing")
      end
    when "complete"
      content_tag :span, class: "inline-flex items-center gap-1 text-sm" do
        content_tag(:span, "✓", class: "text-green-600 dark:text-green-400") +
        content_tag(:span, "Completed")
      end
    when "failed"
      content_tag :span, class: "inline-flex items-center gap-1 text-sm" do
        content_tag(:span, "✗", class: "text-red-600 dark:text-red-400") +
        content_tag(:span, "Failed")
      end
    else
      content_tag :span, status, class: "text-sm text-mist-500 dark:text-mist-400"
    end
  end

  def status_dot(status)
    content_tag :span, "", class: status_dot_class(status)
  end

  def status_dot_class(status)
    base = "flex size-2 rounded-full flex-shrink-0"
    color = case status
    when "pending"    then "bg-mist-400"
    when "processing" then "bg-yellow-500 animate-ping"
    when "complete"   then "bg-green-500"
    when "failed"     then "bg-rose-500"
    else "bg-mist-400"
    end
    "#{base} #{color}"
  end

  def format_duration(duration_seconds)
    FormatsDuration.call(duration_seconds)
  end

  def deletable?(episode)
    episode.user_id == Current.user&.id
  end
end
