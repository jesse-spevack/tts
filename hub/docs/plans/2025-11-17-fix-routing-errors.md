# Fix Routing Errors Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix or suppress minor routing errors (PATCH /episodes and GET /.env bot scans)

**Architecture:** Add missing PATCH route for episodes and configure Rails to ignore common bot scan paths

**Tech Stack:** Ruby on Rails 8 routing

---

## Task 1: Fix PATCH /episodes routing error

**Files:**
- Modify: `config/routes.rb`
- Create: `test/controllers/routing_test.rb`

**Step 1: Investigate the PATCH /episodes request**

Review logs to understand the context:

```bash
kamal app logs --since 24h | grep -A 5 -B 5 "No route matches \[PATCH\] \"/episodes\""
```

Expected: See what client is trying to PATCH and why

**Step 2: Write test for episodes update route**

```ruby
# test/controllers/routing_test.rb
require "test_helper"

class RoutingTest < ActionDispatch::IntegrationTest
  test "episodes update route exists" do
    assert_routing(
      { method: :patch, path: "/episodes/1" },
      { controller: "episodes", action: "update", id: "1" }
    )
  end

  test "episodes resource has standard actions" do
    assert_recognizes(
      { controller: "episodes", action: "index" },
      { method: :get, path: "/episodes" }
    )

    assert_recognizes(
      { controller: "episodes", action: "new" },
      { method: :get, path: "/episodes/new" }
    )

    assert_recognizes(
      { controller: "episodes", action: "create" },
      { method: :post, path: "/episodes" }
    )

    # If update is needed:
    assert_recognizes(
      { controller: "episodes", action: "update", id: "1" },
      { method: :patch, path: "/episodes/1" }
    )
  end
end
```

**Step 3: Run test to verify it fails**

```bash
rails test test/controllers/routing_test.rb
```

Expected: FAIL - route not found

**Step 4: Determine if update action is needed**

Check if there's any legitimate need to PATCH episodes:

- Client-side code making PATCH requests?
- Form submitting to wrong endpoint?
- Old code that needs updating?

If PATCH is not needed, update test to verify it's explicitly excluded.

**Option A: Add update route (if needed)**

```ruby
# config/routes.rb
resources :episodes, only: [ :index, :new, :create, :update ]
```

Add controller action:
```ruby
# app/controllers/episodes_controller.rb
def update
  @episode = Episode.find(params[:id])

  if @episode.update(episode_params)
    redirect_to episodes_path, notice: "Episode updated"
  else
    render :edit, status: :unprocessable_entity
  end
end
```

**Option B: Verify PATCH is not supported (preferred)**

Update test to confirm PATCH is intentionally not supported:

```ruby
# test/controllers/routing_test.rb
test "episodes update is not supported" do
  assert_raises(ActionController::RoutingError) do
    Rails.application.routes.recognize_path("/episodes/1", method: :patch)
  end
end

test "patch to episodes returns 404" do
  episode = episodes(:one)

  patch episode_path(episode), params: { episode: { title: "New Title" } }

  assert_response :not_found
end
```

**Step 5: Run test to verify approach**

```bash
rails test test/controllers/routing_test.rb
```

Expected: PASS with chosen approach

**Step 6: Commit**

If adding update:
```bash
git add config/routes.rb app/controllers/episodes_controller.rb test/controllers/routing_test.rb
git commit -m "feat: add PATCH route for episodes

Supports episode updates via PATCH method"
```

If documenting intentional exclusion:
```bash
git add test/controllers/routing_test.rb
git commit -m "test: document that PATCH /episodes is intentionally not supported

PATCH requests to /episodes are not a supported operation"
```

---

## Task 2: Suppress /.env bot scan errors

**Files:**
- Create: `config/initializers/routing_exceptions.rb`
- Modify: `app/controllers/application_controller.rb`

**Step 1: Configure exception handling for common bot paths**

Create `config/initializers/routing_exceptions.rb`:

```ruby
# Paths that we intentionally don't support
# These are commonly scanned by bots/security scanners
# We'll return 404 without logging routing errors
Rails.application.config.ignored_paths = [
  "/.env",
  "/.git",
  "/wp-admin",
  "/wp-login.php",
  "/.aws/credentials",
  "/config.json",
  "/.well-known/security.txt"
].freeze
```

**Step 2: Add routing error handler**

Modify `app/controllers/application_controller.rb`:

```ruby
class ApplicationController < ActionController::Base
  before_action :require_authentication

  # Rescue from routing errors for known bot paths
  rescue_from ActionController::RoutingError, with: :handle_routing_error

  private

  def handle_routing_error(exception)
    ignored_paths = Rails.application.config.ignored_paths || []

    if ignored_paths.any? { |path| request.path.start_with?(path) }
      # Silently return 404 for bot scan paths
      head :not_found
    else
      # Log and raise for unexpected routing errors
      Rails.logger.error "Routing error: #{exception.message} for #{request.method} #{request.path}"
      raise exception
    end
  end
end
```

**Step 3: Test the handler**

Create `test/controllers/application_controller_test.rb`:

```ruby
require "test_helper"

class ApplicationControllerTest < ActionDispatch::IntegrationTest
  test "returns 404 for .env requests without logging error" do
    get "/.env"

    assert_response :not_found
  end

  test "returns 404 for wp-admin requests" do
    get "/wp-admin"

    assert_response :not_found
  end

  test "still logs routing errors for unexpected paths" do
    # This test is tricky - may need to check logs
    # For now, just verify unknown paths raise errors as expected
    assert_raises(ActionController::RoutingError) do
      get "/totally-unknown-path-12345"
    end
  end
end
```

**Step 4: Run test**

```bash
rails test test/controllers/application_controller_test.rb
```

Expected: Tests pass with 404 responses for bot paths

**Note:** Rails routing errors are raised before controller actions, so rescue_from in ApplicationController won't catch all routing errors. Alternative approach below.

**Alternative: Use middleware**

Create `lib/middleware/bot_path_filter.rb`:

```ruby
# lib/middleware/bot_path_filter.rb
class BotPathFilter
  IGNORED_PATHS = [
    "/.env",
    "/.git",
    "/wp-admin",
    "/wp-login.php",
    "/.aws/credentials",
    "/config.json"
  ].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)

    if IGNORED_PATHS.any? { |path| request.path.start_with?(path) }
      # Return 404 immediately without processing
      return [404, { "Content-Type" => "text/plain" }, ["Not Found"]]
    end

    @app.call(env)
  end
end
```

Add to `config/application.rb`:

```ruby
require_relative "../lib/middleware/bot_path_filter"

module Hub
  class Application < Rails::Application
    # ... existing config ...

    # Filter out bot scan paths before routing
    config.middleware.use BotPathFilter
  end
end
```

**Step 5: Test middleware approach**

```bash
rails test test/controllers/application_controller_test.rb
```

Expected: PASS

**Step 6: Manual verification**

```bash
rails server
curl http://localhost:3000/.env -i
```

Expected: 404 response, no routing error logged

**Step 7: Commit**

```bash
git add lib/middleware/bot_path_filter.rb config/application.rb test/controllers/application_controller_test.rb
git commit -m "feat: filter bot scan paths with middleware

Silently returns 404 for common bot scan paths (.env, wp-admin, etc)
without generating routing errors in logs.

Reduces log noise from security scanners"
```

---

## Task 3: Add logging for unexpected routes

**Files:**
- Create: `config/initializers/routing_logger.rb`

**Step 1: Create routing event logger**

```ruby
# config/initializers/routing_logger.rb

# Log routing errors with structured data for monitoring
ActiveSupport::Notifications.subscribe "routing_error.action_controller" do |name, start, finish, id, payload|
  path = payload[:path]
  method = payload[:method]

  # Skip if it's a known bot path
  ignored_paths = Rails.application.config.ignored_paths || []
  next if ignored_paths.any? { |p| path.start_with?(p) }

  # Log unexpected routing errors
  Rails.logger.warn(
    event: "routing_error",
    method: method,
    path: path,
    duration_ms: ((finish - start) * 1000).round(2)
  )
end
```

**Step 2: Trigger notification in exception handler**

This allows monitoring tools to track routing issues.

**Step 3: Test in development**

Visit an unknown path and check logs for structured event.

**Step 4: Commit**

```bash
git add config/initializers/routing_logger.rb
git commit -m "feat: add structured logging for routing errors

Enables monitoring of unexpected route requests while
filtering known bot scans"
```

---

## Task 4: Document API routes

**Files:**
- Create: `docs/api-routes.md`

**Step 1: Document all routes**

```bash
rails routes > docs/api-routes.md
```

Edit to add descriptions:

```markdown
# Hub API Routes

## Episodes
- `GET /episodes` - List all episodes for current user's podcast
- `GET /episodes/new` - Show new episode form
- `POST /episodes` - Create new episode and enqueue for processing

## Internal API (used by Generator)
- `PATCH /api/internal/episodes/:id` - Update episode status from generator

## Authentication
- `GET /session/new` - Show login form
- `POST /session` - Send magic link email
- `DELETE /session` - Sign out

## Health
- `GET /up` - Health check endpoint for load balancers

## Intentionally Not Supported
- `PATCH /episodes/:id` - User cannot update episodes directly (use internal API)
- `DELETE /episodes/:id` - Episodes cannot be deleted (add this feature if needed)

## Common Bot Scans (Filtered)
The following paths are filtered by middleware and return 404:
- `/.env`
- `/.git`
- `/wp-admin`
- `/wp-login.php`
```

**Step 2: Commit**

```bash
git add docs/api-routes.md
git commit -m "docs: document API routes and unsupported endpoints

Clarifies which routes are intentional and which are filtered"
```

---

## Verification

**Test routes:**
```bash
rails routes
rails test
```

Expected: All tests pass, routes documented

**Check logs for bot scans:**
```bash
# After deployment
kamal app logs --since 1h | grep -i "routing\|404"
```

Expected: Bot scans return 404 without routing errors

**Manual testing:**
```bash
# Test filtered paths
curl http://localhost:3000/.env -i  # Should return 404
curl http://localhost:3000/wp-admin -i  # Should return 404

# Test valid paths
curl http://localhost:3000/episodes -i  # Should redirect to login
```

**Deployment:**
```bash
git push origin main
./bin/deploy
```

**Post-deployment verification:**

Monitor logs for 24 hours:
- No more PATCH /episodes errors (or they're expected)
- No /.env routing errors
- Overall log noise reduced
