class MarketingPreviewController < ApplicationController
  allow_unauthenticated_access
  layout "marketing"

  # GET /marketing-preview
  def index
    @refinements = load_refinements
    @partials = build_partial_registry
  end

  # POST /marketing-preview/refine
  def refine
    refinements = load_refinements
    partial_name = params[:partial_name]
    refinements[partial_name] = {
      "needs_refinement" => params[:needs_refinement] == "1",
      "notes" => params[:notes].to_s
    }
    save_refinements(refinements)
    redirect_to marketing_preview_path(anchor: partial_name.parameterize), notice: "Saved."
  end

  private

  def yaml_path
    Rails.root.join("tmp", "partial_refinements.yml")
  end

  def load_refinements
    return {} unless File.exist?(yaml_path)
    YAML.safe_load_file(yaml_path) || {}
  rescue StandardError
    {}
  end

  def save_refinements(data)
    FileUtils.mkdir_p(File.dirname(yaml_path))
    File.write(yaml_path, data.to_yaml)
  end

  def build_partial_registry
    {
      "Navbars" => %w[
        navbar_centered_logo
        navbar_centered_links
        navbar_left_links
      ],
      "Footers" => %w[
        footer_newsletter
        footer_categories
        footer_links_social
      ],
      "Heroes" => %w[
        hero_simple_centered
        hero_simple_left
        hero_left_demo
        hero_centered_demo
        hero_centered_photo
        hero_left_photo
        hero_two_col_photo
        hero_demo_bg
      ],
      "Features" => %w[
        features_two_col
        features_three_col_demos
        features_three_col
        features_alternating
        features_large_demo
      ],
      "Pricing" => %w[
        pricing_multi
        pricing_hero_multi
        pricing_single_two_col
        plan_comparison
      ],
      "Testimonials" => %w[
        testimonial_large_quote
        testimonial_two_col_photo
        testimonials_grid
      ],
      "Stats" => %w[
        stats_graph
        stats_four_col
        stats_three_col
      ],
      "Teams" => %w[
        team_four_col
        team_three_col
      ],
      "FAQs" => %w[
        faqs_accordion
        faqs_two_col_accordion
      ],
      "CTAs" => %w[
        cta_simple
        cta_centered
      ],
      "Documents" => %w[
        document_centered
        document_left
      ],
      "Elements" => %w[
        section
        announcement_badge
        email_signup_form
        install_command
        wallpaper
        screenshot
      ],
      "Icons" => %w[icons]
    }
  end
end
