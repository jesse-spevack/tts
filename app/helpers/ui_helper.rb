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

  def show_billing_section?(user)
    user.premium?
  end

  def credits_card_variant(user)
    return :balance if user.has_credits?
    return nil if user.premium?
    :empty_state
  end

  # Shared Tailwind classes for the marketing primary CTA button/link.
  # Used by home/about/blog/header to keep the pill-shaped dark button
  # style consistent. Pass a sizing fragment (e.g. "px-4 py-1.5" or
  # "px-5 py-2.5") to control button size per context.
  def marketing_primary_button_classes(sizing = "px-4 py-1.5", extra: nil)
    [
      "inline-flex shrink-0 items-center justify-center gap-1 rounded-full",
      "bg-mist-950 text-white hover:bg-mist-800",
      "dark:bg-white dark:text-mist-950 dark:hover:bg-mist-200",
      "text-sm/7 font-medium",
      sizing,
      extra
    ].compact.join(" ")
  end

  # Destination for a marketing CTA when the user is already authenticated.
  # Mirrors SessionsController#post_login_path so signed-in clicks land
  # where a just-authenticated user would via the signup modal. pack_size
  # overrides the default first-pack checkout for tier-specific credit CTAs.
  def marketing_cta_path(plan, pack_size: nil)
    case plan
    when "credit_pack"
      size = pack_size || AppConfig::Credits::PACKS.first[:size]
      checkout_path(pack_size: size)
    else
      new_episode_path
    end
  end

  def oauth_app_badge(app)
    slug = app.name.to_s.parameterize
    svg_path = Rails.root.join("app/assets/images/oauth_apps/#{slug}.svg") if slug.present?

    if svg_path&.exist?
      content_tag :span,
        class: "inline-flex size-9 items-center justify-center rounded-lg text-mist-950 dark:text-white" do
        inline_oauth_app_svg(svg_path).html_safe
      end
    else
      content_tag :span, oauth_app_initials(app.name),
        class: "inline-flex size-9 items-center justify-center rounded-lg bg-mist-100 text-mist-700 dark:bg-mist-700 dark:text-mist-200 text-xs font-semibold"
    end
  end

  private

  def inline_oauth_app_svg(path)
    # Strip <script> and <foreignObject> as a backstop against accidental
    # designer-export leakage. Primary trust boundary is code review; see
    # app/assets/images/oauth_apps/README.md for the contract.
    raw = path.read
      .gsub(%r{<script\b[^>]*>.*?</script>}m, "")
      .gsub(%r{<foreignObject\b[^>]*>.*?</foreignObject>}m, "")

    doc = Nokogiri::HTML::DocumentFragment.parse(raw)
    svg_el = doc.at_css("svg")
    existing = svg_el["class"]
    svg_el["class"] = [ existing, "size-7" ].compact.map(&:strip).reject(&:empty?).join(" ")
    doc.to_html
  end

  def oauth_app_initials(name)
    return "?" if name.blank?
    name.to_s.strip.split(/\s+/).first(2).filter_map { |w| w[0] }.join.upcase
  end
end
