# Simple Analytics Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Track page views and referrers to understand landing page traffic.

**Architecture:** Add PageView model to store visits, Trackable concern to capture them on public pages, admin dashboard to view stats. Admin access via boolean on User model.

**Tech Stack:** Rails 8.1, SQLite, Minitest

---

### Task 1: Add admin column to users

**Files:**
- Create: `hub/db/migrate/YYYYMMDDHHMMSS_add_admin_to_users.rb`
- Modify: `hub/test/fixtures/users.yml`

**Step 1: Generate migration**

Run:
```bash
cd hub && bin/rails generate migration AddAdminToUsers admin:boolean
```

**Step 2: Update migration with default value**

Edit the generated migration to set `default: false, null: false`:

```ruby
class AddAdminToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :admin, :boolean, default: false, null: false
  end
end
```

**Step 3: Run migration**

Run:
```bash
cd hub && bin/rails db:migrate
```
Expected: Migration runs successfully, schema.rb updated

**Step 4: Add admin fixture**

Add to `hub/test/fixtures/users.yml`:

```yaml
admin_user:
  email_address: admin@example.com
  admin: true
```

**Step 5: Commit**

```bash
git add hub/db/migrate hub/db/schema.rb hub/test/fixtures/users.yml
git commit -m "feat: add admin boolean to users table"
```

---

### Task 2: Create PageView model

**Files:**
- Create: `hub/app/models/page_view.rb`
- Create: `hub/db/migrate/YYYYMMDDHHMMSS_create_page_views.rb`
- Create: `hub/test/models/page_view_test.rb`

**Step 1: Write the failing test**

Create `hub/test/models/page_view_test.rb`:

```ruby
require "test_helper"

class PageViewTest < ActiveSupport::TestCase
  test "creates page view with required attributes" do
    page_view = PageView.create!(
      path: "/",
      visitor_hash: "abc123",
      user_agent: "Mozilla/5.0"
    )

    assert page_view.persisted?
    assert_equal "/", page_view.path
  end

  test "allows nil referrer" do
    page_view = PageView.new(
      path: "/",
      visitor_hash: "abc123",
      user_agent: "Mozilla/5.0",
      referrer: nil
    )

    assert page_view.valid?
  end

  test "extracts referrer_host from referrer" do
    page_view = PageView.new(
      path: "/",
      visitor_hash: "abc123",
      user_agent: "Mozilla/5.0",
      referrer: "https://www.google.com/search?q=tts"
    )

    assert_equal "www.google.com", page_view.referrer_host
  end

  test "handles nil referrer when extracting host" do
    page_view = PageView.new(
      path: "/",
      visitor_hash: "abc123",
      user_agent: "Mozilla/5.0",
      referrer: nil
    )

    assert_nil page_view.referrer_host
  end

  test "handles malformed referrer gracefully" do
    page_view = PageView.new(
      path: "/",
      visitor_hash: "abc123",
      user_agent: "Mozilla/5.0",
      referrer: "not a valid url"
    )

    assert_nil page_view.referrer_host
  end

  # Query method tests
  test ".stats returns total_views and unique_visitors since date" do
    PageView.create!(path: "/", visitor_hash: "abc", user_agent: "test", created_at: 2.days.ago)
    PageView.create!(path: "/", visitor_hash: "abc", user_agent: "test", created_at: 1.day.ago)
    PageView.create!(path: "/", visitor_hash: "def", user_agent: "test", created_at: 1.day.ago)
    PageView.create!(path: "/old", visitor_hash: "xyz", user_agent: "test", created_at: 10.days.ago)

    stats = PageView.stats(since: 7.days.ago)

    assert_equal 3, stats[:total_views]
    assert_equal 2, stats[:unique_visitors]
  end

  test ".stats returns views_by_page ordered by count" do
    PageView.create!(path: "/", visitor_hash: "a", user_agent: "test")
    PageView.create!(path: "/", visitor_hash: "b", user_agent: "test")
    PageView.create!(path: "/how-it-sounds", visitor_hash: "c", user_agent: "test")

    stats = PageView.stats(since: 7.days.ago)

    assert_equal({ "/" => 2, "/how-it-sounds" => 1 }, stats[:views_by_page])
  end

  test ".top_referrers returns referrer hosts ordered by count" do
    PageView.create!(path: "/", visitor_hash: "a", user_agent: "test", referrer: "https://google.com/search")
    PageView.create!(path: "/", visitor_hash: "b", user_agent: "test", referrer: "https://google.com/search")
    PageView.create!(path: "/", visitor_hash: "c", user_agent: "test", referrer: "https://twitter.com/post")
    PageView.create!(path: "/", visitor_hash: "d", user_agent: "test", referrer: nil)

    referrers = PageView.top_referrers(since: 7.days.ago, limit: 10)

    assert_equal({ "google.com" => 2, "twitter.com" => 1, nil => 1 }, referrers)
  end

  test ".daily_views returns views grouped by date" do
    PageView.create!(path: "/", visitor_hash: "a", user_agent: "test", created_at: Date.current)
    PageView.create!(path: "/", visitor_hash: "b", user_agent: "test", created_at: Date.current)
    PageView.create!(path: "/", visitor_hash: "c", user_agent: "test", created_at: 1.day.ago)

    daily = PageView.daily_views(since: 7.days.ago)

    assert_equal 2, daily[Date.current.to_s]
    assert_equal 1, daily[1.day.ago.to_date.to_s]
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
cd hub && bin/rails test test/models/page_view_test.rb
```
Expected: FAIL - uninitialized constant PageView

**Step 3: Generate model and migration**

Run:
```bash
cd hub && bin/rails generate model PageView path:string referrer:string referrer_host:string visitor_hash:string user_agent:string
```

**Step 4: Add indexes to migration**

Edit the generated migration:

```ruby
class CreatePageViews < ActiveRecord::Migration[8.1]
  def change
    create_table :page_views do |t|
      t.string :path, null: false
      t.string :referrer
      t.string :referrer_host
      t.string :visitor_hash, null: false
      t.string :user_agent

      t.timestamps
    end

    add_index :page_views, :created_at
    add_index :page_views, :path
    add_index :page_views, :referrer_host
  end
end
```

**Step 5: Run migration**

Run:
```bash
cd hub && bin/rails db:migrate
```

**Step 6: Implement PageView model**

Replace `hub/app/models/page_view.rb`:

```ruby
class PageView < ApplicationRecord
  before_validation :extract_referrer_host

  validates :path, presence: true
  validates :visitor_hash, presence: true

  class << self
    def stats(since:)
      views = where("created_at >= ?", since)
      {
        total_views: views.count,
        unique_visitors: views.distinct.count(:visitor_hash),
        views_by_page: views.group(:path).order("count_all DESC").count
      }
    end

    def top_referrers(since:, limit: 10)
      where("created_at >= ?", since)
        .group(:referrer_host)
        .order("count_all DESC")
        .limit(limit)
        .count
    end

    def daily_views(since:)
      where("created_at >= ?", since)
        .group("date(created_at)")
        .order("date(created_at) DESC")
        .count
    end
  end

  private

  def extract_referrer_host
    return if referrer.blank?

    uri = URI.parse(referrer)
    self.referrer_host = uri.host
  rescue URI::InvalidURIError
    self.referrer_host = nil
  end
end
```

**Step 7: Run tests to verify they pass**

Run:
```bash
cd hub && bin/rails test test/models/page_view_test.rb
```
Expected: 9 tests, 0 failures

**Step 8: Commit**

```bash
git add hub/app/models/page_view.rb hub/db/migrate hub/db/schema.rb hub/test/models/page_view_test.rb
git commit -m "feat: add PageView model for analytics tracking"
```

---

### Task 3: Create Trackable concern

**Files:**
- Create: `hub/app/controllers/concerns/trackable.rb`
- Create: `hub/test/controllers/concerns/trackable_test.rb`

**Step 1: Write the failing test**

Create directory and test file:

```bash
mkdir -p hub/test/controllers/concerns
```

Create `hub/test/controllers/concerns/trackable_test.rb`:

```ruby
require "test_helper"

class TrackableTest < ActionDispatch::IntegrationTest
  test "tracks page view for anonymous visitor" do
    assert_difference "PageView.count", 1 do
      get root_url
    end

    page_view = PageView.last
    assert_equal "/", page_view.path
    assert_not_nil page_view.visitor_hash
  end

  test "captures referrer from request header" do
    assert_difference "PageView.count", 1 do
      get root_url, headers: { "HTTP_REFERER" => "https://google.com/search" }
    end

    page_view = PageView.last
    assert_equal "https://google.com/search", page_view.referrer
    assert_equal "google.com", page_view.referrer_host
  end

  test "does not track logged in users" do
    user = users(:one)
    token = GenerateAuthToken.call(user: user)
    get auth_url, params: { token: token }

    assert_no_difference "PageView.count" do
      get root_url
    end
  end

  test "does not track bot requests" do
    assert_no_difference "PageView.count" do
      get root_url, headers: { "HTTP_USER_AGENT" => "Googlebot/2.1" }
    end
  end

  test "generates different visitor hash each day" do
    get root_url
    first_hash = PageView.last.visitor_hash

    travel 1.day do
      get root_url
    end
    second_hash = PageView.last.visitor_hash

    assert_not_equal first_hash, second_hash
  end

  test "generates same visitor hash within same day" do
    get root_url
    first_hash = PageView.last.visitor_hash

    get how_it_sounds_url
    second_hash = PageView.last.visitor_hash

    assert_equal first_hash, second_hash
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
cd hub && bin/rails test test/controllers/concerns/trackable_test.rb
```
Expected: FAIL - no tracking happening yet

**Step 3: Implement Trackable concern**

Create `hub/app/controllers/concerns/trackable.rb`:

```ruby
module Trackable
  extend ActiveSupport::Concern

  BOT_PATTERNS = /bot|crawler|spider|scraper|curl|wget/i

  included do
    before_action :track_page_view
  end

  private

  def track_page_view
    return if authenticated?
    return if bot_request?
    return unless request.get?

    PageView.insert({
      path: request.path,
      referrer: request.referer,
      referrer_host: extract_host(request.referer),
      visitor_hash: generate_visitor_hash,
      user_agent: request.user_agent,
      created_at: Time.current,
      updated_at: Time.current
    })
  end

  def bot_request?
    request.user_agent&.match?(BOT_PATTERNS)
  end

  def generate_visitor_hash
    daily_salt = Date.current.to_s
    data = "#{request.remote_ip}#{request.user_agent}#{daily_salt}"
    Digest::SHA256.hexdigest(data)
  end

  def extract_host(url)
    return nil if url.blank?
    URI.parse(url).host
  rescue URI::InvalidURIError
    nil
  end
end
```

**Step 4: Include Trackable in PagesController**

Modify `hub/app/controllers/pages_controller.rb`:

```ruby
class PagesController < ApplicationController
  include Trackable
  allow_unauthenticated_access

  def home
    redirect_to new_episode_path if authenticated?
  end

  def how_it_sounds
  end

  def terms
  end

  def add_rss_feed
  end
end
```

**Step 5: Run tests to verify they pass**

Run:
```bash
cd hub && bin/rails test test/controllers/concerns/trackable_test.rb
```
Expected: 6 tests, 0 failures

**Step 6: Commit**

```bash
git add hub/app/controllers/concerns/trackable.rb hub/app/controllers/pages_controller.rb hub/test/controllers/concerns/trackable_test.rb
git commit -m "feat: add Trackable concern for page view tracking"
```

---

### Task 4: Create Admin::AnalyticsController

**Files:**
- Create: `hub/app/controllers/admin/analytics_controller.rb`
- Create: `hub/test/controllers/admin/analytics_controller_test.rb`

**Step 1: Write the failing test**

Create directory:
```bash
mkdir -p hub/app/controllers/admin
mkdir -p hub/test/controllers/admin
```

Create `hub/test/controllers/admin/analytics_controller_test.rb`:

```ruby
require "test_helper"

class Admin::AnalyticsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin_user)
    @regular_user = users(:one)
  end

  test "redirects unauthenticated users to root" do
    get admin_analytics_url
    assert_redirected_to root_url
  end

  test "returns forbidden for non-admin users" do
    token = GenerateAuthToken.call(user: @regular_user)
    get auth_url, params: { token: token }

    get admin_analytics_url
    assert_response :forbidden
  end

  test "allows admin users to view analytics" do
    token = GenerateAuthToken.call(user: @admin)
    get auth_url, params: { token: token }

    get admin_analytics_url
    assert_response :success
  end

  test "displays page view counts" do
    PageView.create!(path: "/", visitor_hash: "abc", user_agent: "test")
    PageView.create!(path: "/", visitor_hash: "def", user_agent: "test")
    PageView.create!(path: "/how-it-sounds", visitor_hash: "abc", user_agent: "test")

    token = GenerateAuthToken.call(user: @admin)
    get auth_url, params: { token: token }

    get admin_analytics_url
    assert_response :success
    assert_select "td", text: "3" # total views
  end

  test "displays unique visitor count" do
    PageView.create!(path: "/", visitor_hash: "abc", user_agent: "test")
    PageView.create!(path: "/", visitor_hash: "abc", user_agent: "test")
    PageView.create!(path: "/", visitor_hash: "def", user_agent: "test")

    token = GenerateAuthToken.call(user: @admin)
    get auth_url, params: { token: token }

    get admin_analytics_url
    assert_response :success
    assert_select "td", text: "2" # unique visitors
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
cd hub && bin/rails test test/controllers/admin/analytics_controller_test.rb
```
Expected: FAIL - uninitialized constant Admin::AnalyticsController

**Step 3: Add route**

Modify `hub/config/routes.rb` to add the admin namespace:

```ruby
Rails.application.routes.draw do
  root "pages#home"

  namespace :admin do
    resource :analytics, only: [:show], controller: "analytics"
  end

  resources :episodes, only: [ :index, :new, :create, :show, :destroy ]

  # ... rest of routes unchanged
```

**Step 4: Implement controller**

Create `hub/app/controllers/admin/analytics_controller.rb`:

```ruby
module Admin
  class AnalyticsController < ApplicationController
    before_action :require_admin

    def show
      @stats_7_days = PageView.stats(since: 7.days.ago)
      @stats_30_days = PageView.stats(since: 30.days.ago)
      @top_referrers = PageView.top_referrers(since: 30.days.ago)
      @daily_views = PageView.daily_views(since: 30.days.ago)
    end

    private

    def require_admin
      head :forbidden unless Current.session&.user&.admin?
    end
  end
end
```

**Step 5: Run tests**

Run:
```bash
cd hub && bin/rails test test/controllers/admin/analytics_controller_test.rb
```
Expected: May fail due to missing view - that's OK, proceed to next step

**Step 6: Commit controller and route**

```bash
git add hub/app/controllers/admin/analytics_controller.rb hub/config/routes.rb hub/test/controllers/admin/analytics_controller_test.rb
git commit -m "feat: add Admin::AnalyticsController with access control"
```

---

### Task 5: Create analytics view

**Files:**
- Create: `hub/app/views/admin/analytics/show.html.erb`

**Step 1: Create view directory**

```bash
mkdir -p hub/app/views/admin/analytics
```

**Step 2: Create the view**

Create `hub/app/views/admin/analytics/show.html.erb`:

```erb
<div class="max-w-4xl mx-auto">
  <h1 class="text-3xl font-semibold mb-8">Analytics</h1>

  <!-- Summary Stats -->
  <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-10">
    <!-- 7 Day Stats -->
    <%= render "shared/card", padding: "p-6" do %>
      <h2 class="text-lg font-semibold mb-4">Last 7 Days</h2>
      <table class="w-full text-sm">
        <tr>
          <td class="py-1 text-[var(--color-subtext)]">Page Views</td>
          <td class="py-1 text-right font-medium"><%= @stats_7_days[:total_views] %></td>
        </tr>
        <tr>
          <td class="py-1 text-[var(--color-subtext)]">Unique Visitors</td>
          <td class="py-1 text-right font-medium"><%= @stats_7_days[:unique_visitors] %></td>
        </tr>
      </table>
    <% end %>

    <!-- 30 Day Stats -->
    <%= render "shared/card", padding: "p-6" do %>
      <h2 class="text-lg font-semibold mb-4">Last 30 Days</h2>
      <table class="w-full text-sm">
        <tr>
          <td class="py-1 text-[var(--color-subtext)]">Page Views</td>
          <td class="py-1 text-right font-medium"><%= @stats_30_days[:total_views] %></td>
        </tr>
        <tr>
          <td class="py-1 text-[var(--color-subtext)]">Unique Visitors</td>
          <td class="py-1 text-right font-medium"><%= @stats_30_days[:unique_visitors] %></td>
        </tr>
      </table>
    <% end %>
  </div>

  <!-- Views by Page (30 days) -->
  <%= render "shared/card", padding: "p-6" do %>
    <h2 class="text-lg font-semibold mb-4">Views by Page (30 days)</h2>
    <table class="w-full text-sm">
      <thead>
        <tr class="border-b border-[var(--color-surface1)]">
          <th class="py-2 text-left text-[var(--color-subtext)]">Path</th>
          <th class="py-2 text-right text-[var(--color-subtext)]">Views</th>
        </tr>
      </thead>
      <tbody>
        <% @stats_30_days[:views_by_page].each do |path, count| %>
          <tr class="border-b border-[var(--color-surface0)]">
            <td class="py-2"><%= path %></td>
            <td class="py-2 text-right font-medium"><%= count %></td>
          </tr>
        <% end %>
        <% if @stats_30_days[:views_by_page].empty? %>
          <tr>
            <td colspan="2" class="py-4 text-center text-[var(--color-subtext)]">No data yet</td>
          </tr>
        <% end %>
      </tbody>
    </table>
  <% end %>

  <!-- Top Referrers -->
  <%= render "shared/card", padding: "p-6" do %>
    <h2 class="text-lg font-semibold mb-4">Top Referrers (30 days)</h2>
    <table class="w-full text-sm">
      <thead>
        <tr class="border-b border-[var(--color-surface1)]">
          <th class="py-2 text-left text-[var(--color-subtext)]">Source</th>
          <th class="py-2 text-right text-[var(--color-subtext)]">Views</th>
        </tr>
      </thead>
      <tbody>
        <% @top_referrers.each do |host, count| %>
          <tr class="border-b border-[var(--color-surface0)]">
            <td class="py-2"><%= host || "Direct" %></td>
            <td class="py-2 text-right font-medium"><%= count %></td>
          </tr>
        <% end %>
        <% if @top_referrers.empty? %>
          <tr>
            <td colspan="2" class="py-4 text-center text-[var(--color-subtext)]">No data yet</td>
          </tr>
        <% end %>
      </tbody>
    </table>
  <% end %>

  <!-- Daily Views -->
  <%= render "shared/card", padding: "p-6" do %>
    <h2 class="text-lg font-semibold mb-4">Daily Views (30 days)</h2>
    <table class="w-full text-sm">
      <thead>
        <tr class="border-b border-[var(--color-surface1)]">
          <th class="py-2 text-left text-[var(--color-subtext)]">Date</th>
          <th class="py-2 text-right text-[var(--color-subtext)]">Views</th>
        </tr>
      </thead>
      <tbody>
        <% @daily_views.each do |date, count| %>
          <tr class="border-b border-[var(--color-surface0)]">
            <td class="py-2"><%= date %></td>
            <td class="py-2 text-right font-medium"><%= count %></td>
          </tr>
        <% end %>
        <% if @daily_views.empty? %>
          <tr>
            <td colspan="2" class="py-4 text-center text-[var(--color-subtext)]">No data yet</td>
          </tr>
        <% end %>
      </tbody>
    </table>
  <% end %>
</div>
```

**Step 3: Run all analytics tests**

Run:
```bash
cd hub && bin/rails test test/controllers/admin/analytics_controller_test.rb
```
Expected: 5 tests, 0 failures

**Step 4: Commit**

```bash
git add hub/app/views/admin/analytics/show.html.erb
git commit -m "feat: add analytics dashboard view"
```

---

### Task 6: Run full test suite

**Step 1: Run all tests**

Run:
```bash
cd hub && bin/rails test
```
Expected: All tests pass

**Step 2: Fix any failures**

If tests fail, investigate and fix before proceeding.

**Step 3: Run rubocop**

Run:
```bash
cd hub && bundle exec rubocop
```
Expected: No offenses (or fix any that appear)

---

### Task 7: Final verification

**Step 1: Start the server locally**

Run:
```bash
cd hub && bin/rails server
```

**Step 2: Test tracking**

1. Visit http://localhost:3000/ in incognito
2. Check Rails console: `PageView.count` should be 1
3. Check `PageView.last.path` is "/"

**Step 3: Test admin access**

1. In Rails console: `User.find_by(email: "YOUR_EMAIL").update!(admin: true)`
2. Log in via magic link
3. Visit http://localhost:3000/admin/analytics
4. Verify you see the dashboard with your page view

**Step 4: Commit any final fixes**

If needed, commit any fixes discovered during manual testing.
