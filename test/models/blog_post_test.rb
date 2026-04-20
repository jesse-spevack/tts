# frozen_string_literal: true

require "test_helper"

class BlogPostTest < ActiveSupport::TestCase
  test ".all returns non-empty collection" do
    assert_not_empty BlogPost.all
  end

  test ".all entries have required fields populated" do
    BlogPost.all.each do |post|
      assert post.title.present?, "missing title"
      assert post.url.present?, "missing url"
      assert_kind_of Date, post.published_on
      assert post.cover_image_url.present?, "missing cover_image_url"
    end
  end

  test ".all sorts newest first" do
    dates = BlogPost.all.map(&:published_on)
    assert_equal dates.sort.reverse, dates
  end

  test ".build returns entry when required fields present" do
    post = BlogPost.build(
      "title" => "Test",
      "url" => "https://example.com",
      "published_on" => Date.new(2026, 1, 1),
      "cover_image_url" => "https://example.com/img.png"
    )
    assert_equal "Test", post.title
  end

  test ".build raises when a required field is missing" do
    assert_raises(ArgumentError) do
      BlogPost.build("title" => "x", "url" => "https://example.com")
    end
  end

  test ".build raises when a required field is blank" do
    assert_raises(ArgumentError) do
      BlogPost.build(
        "title" => "",
        "url" => "https://example.com",
        "published_on" => Date.new(2026, 1, 1),
        "cover_image_url" => "https://example.com/img.png"
      )
    end
  end
end
