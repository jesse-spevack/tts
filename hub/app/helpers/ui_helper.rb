module UiHelper
  def button_classes(type: :primary, full_width: false)
    width_class = full_width ? "w-full " : ""

    case type
    when :primary
      "#{width_class}bg-[var(--color-primary)] text-[var(--color-primary-text)] font-medium py-2 px-4 rounded-lg hover:bg-[var(--color-primary-hover)] cursor-pointer"
    when :secondary
      "#{width_class}border border-[var(--color-overlay0)] text-[var(--color-text)] font-medium py-2 px-4 rounded-lg hover:border-[var(--color-primary)] cursor-pointer"
    when :text
      "text-[var(--color-subtext)] hover:text-[var(--color-text)]"
    else
      ""
    end.strip
  end

  def input_classes
    "w-full bg-[var(--color-base)] border border-[var(--color-overlay0)] rounded-md px-3 py-2 focus:outline-none focus:border-[var(--color-primary)]"
  end

  def label_classes
    "block text-sm font-medium mb-2"
  end
end
