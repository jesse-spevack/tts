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
    assert_select "meta[name=description]"
    assert_select "h1", /Writing from PodRead/
  end

  test "post cards link externally with noopener" do
    get "/blog"
    first_post = BlogPost.all.first
    assert_select "a[href=?][target=_blank][rel=noopener]", first_post.url
  end

  test "hero CTA opens the signup modal" do
    get "/blog"
    assert_select "button[data-action*=signup-modal]"
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
end
