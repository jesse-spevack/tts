# frozen_string_literal: true

require "test_helper"

class BlogPageTest < ActionDispatch::IntegrationTest
  test "GET /blog is accessible without authentication" do
    get "/blog"
    assert_response :success
  end

  test "blog_path routes to pages#blog" do
    assert_routing "/blog", controller: "pages", action: "blog"
  end

  test "page renders every curated post title" do
    get "/blog"
    BlogPost.all.each do |post|
      assert_includes response.body, post.title
    end
  end

  test "page renders headline and meta description for SEO" do
    get "/blog"
    assert_select "title", /Writing — PodRead/
    assert_select "meta[name=description][content*=?]", "PodRead"
    assert_select "h1", /Writing from PodRead/
  end

  test "every post card links externally with noopener noreferrer" do
    get "/blog"
    posts = BlogPost.all
    assert_select "a[target=_blank][rel='noopener noreferrer']", count: posts.size
    posts.each do |post|
      assert_select "a[href=?][target=_blank][rel='noopener noreferrer']", post.url
    end
  end

  test "hero CTA button opens the signup modal" do
    get "/blog"
    assert_select "button[data-action*=signup-modal]", text: "Create your first episode"
  end

  test "page renders a post that has no excerpt" do
    post = BlogPost::Entry.new(
      title: "No Excerpt Post",
      url: "https://example.com",
      published_on: Date.new(2026, 1, 1),
      excerpt: nil,
      cover_image_url: "https://example.com/img.png"
    )
    original_all = BlogPost.method(:all)
    BlogPost.define_singleton_method(:all) { [ post ] }
    begin
      get "/blog"
      assert_response :success
      assert_includes response.body, "No Excerpt Post"
    ensure
      BlogPost.define_singleton_method(:all, original_all)
    end
  end

  test "nav includes Blog link" do
    get "/blog"
    assert_select "nav a[href=?]", blog_path, text: "Blog"
  end

  test "nav on home page includes Blog link" do
    get "/"
    assert_select "nav a[href=?]", blog_path, text: "Blog"
  end

  test "nav on about page includes Blog link" do
    get "/about"
    assert_select "nav a[href=?]", blog_path, text: "Blog"
  end

  test "nav on privacy page includes Blog link" do
    get "/privacy"
    assert_select "nav a[href=?]", blog_path, text: "Blog"
  end

  test "nav on terms page includes Blog link" do
    get "/terms"
    assert_select "nav a[href=?]", blog_path, text: "Blog"
  end
end
