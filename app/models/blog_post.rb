# frozen_string_literal: true

class BlogPost
  REQUIRED_FIELDS = %w[title url published_on cover_image_url].freeze

  DATA_PATH = Rails.root.join("config/blog_posts.yml")

  Entry = Struct.new(
    :title,
    :url,
    :published_on,
    :excerpt,
    :cover_image_url,
    keyword_init: true
  )

  def self.all
    raw = YAML.safe_load_file(DATA_PATH, permitted_classes: [ Date ])
    Array(raw).map { |attrs| build(attrs) }.sort_by(&:published_on).reverse
  end

  def self.build(attrs)
    attrs = attrs.transform_keys(&:to_s)
    missing = REQUIRED_FIELDS.reject { |f| attrs[f].present? }
    if missing.any?
      raise ArgumentError, "BlogPost missing required fields: #{missing.join(", ")} in #{attrs.inspect}"
    end

    Entry.new(
      title: attrs["title"],
      url: attrs["url"],
      published_on: attrs["published_on"],
      excerpt: attrs["excerpt"],
      cover_image_url: attrs["cover_image_url"]
    )
  end
end
