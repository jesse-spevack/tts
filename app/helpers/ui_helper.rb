module UiHelper
  def button_classes(type: :primary, full_width: false)
    width_class = full_width ? "w-full " : ""

    case type
    when :primary
      "#{width_class}bg-mist-950 dark:bg-white text-white dark:text-mist-950 font-medium py-2 px-4 rounded-lg hover:bg-mist-800 dark:hover:bg-mist-200 cursor-pointer"
    when :secondary
      "#{width_class}border border-mist-200 dark:border-mist-700 text-mist-950 dark:text-white font-medium py-2 px-4 rounded-lg hover:border-mist-950 dark:hover:border-white cursor-pointer"
    when :text
      "text-mist-500 dark:text-mist-400 hover:text-mist-950 dark:hover:text-white"
    when :link
      "text-sm text-mist-950 dark:text-white hover:text-mist-800 dark:hover:text-mist-200 cursor-pointer"
    when :danger
      "#{width_class}border border-red-600/50 dark:border-red-400/50 text-red-600 dark:text-red-400 font-medium py-2 px-4 rounded-lg hover:bg-red-600/10 dark:hover:bg-red-400/10 cursor-pointer"
    else
      ""
    end.strip
  end

  def input_classes
    "block w-full rounded-md bg-white px-3 py-2 text-mist-950 outline-1 -outline-offset-1 outline-mist-300 placeholder:text-mist-400 focus:outline-2 focus:-outline-offset-2 focus:outline-mist-950 dark:bg-mist-800 dark:text-white dark:outline-mist-700 dark:focus:outline-white sm:text-sm/6"
  end

  def label_classes
    "block text-sm/6 font-medium text-mist-950 dark:text-white"
  end

  def status_pill_label(subscription)
    return "" if subscription.nil?
    return "Canceling" if subscription.active? && subscription.canceling?
    return "Active" if subscription.active?
    return "Past Due" if subscription.past_due?
    "Canceled"
  end

  def status_pill_classes(subscription)
    case status_pill_label(subscription)
    when "Active"
      "bg-green-50 text-green-700 dark:bg-green-500/10 dark:text-green-400"
    when "Canceling", "Past Due"
      "bg-yellow-50 text-yellow-700 dark:bg-yellow-500/10 dark:text-yellow-400"
    when "Canceled"
      "bg-mist-100 text-mist-600 dark:bg-mist-500/10 dark:text-mist-400"
    else
      ""
    end
  end

  def manage_billing_cta_label(subscription)
    subscription&.canceled? ? "Resubscribe" : "Manage Billing"
  end
end
