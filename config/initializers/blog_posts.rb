# frozen_string_literal: true

# Fail-fast boot check: parse config/blog_posts.yml and validate every entry
# has the required fields. Without this, a malformed edit would 500 /blog on
# every request until someone noticed — we want the deploy to fail instead.
Rails.application.config.after_initialize do
  BlogPost.all
end
