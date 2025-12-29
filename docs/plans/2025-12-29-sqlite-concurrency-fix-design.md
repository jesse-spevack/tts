# SQLite Concurrency Fix

## Problem

Users creating multiple episodes quickly causes `SQLite3::BusyException` errors. The root cause is multiple `ProcessUrlEpisodeJob` jobs running concurrently, competing for database write locks with incoming web requests.

## Solution

Two changes to improve SQLite concurrency:

### 1. Enable WAL Mode

Add pragma settings to `config/database.yml`:

```yaml
default: &default
  adapter: sqlite3
  max_connections: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  timeout: 5000
  pragmas:
    journal_mode: wal
    synchronous: normal
```

**Why:** WAL (Write-Ahead Logging) allows readers while writes happen. Writers still serialize but hold locks briefly, dramatically reducing contention.

### 2. Per-User Job Concurrency Limit

Add to `app/jobs/process_url_episode_job.rb`:

```ruby
limits_concurrency to: 1, key: ->(episode_id) {
  Episode.find(episode_id).user_id
}
```

**Why:** Prevents one user's jobs from competing with each other. Multiple users can still process in parallel (up to worker thread limit of 3).

## Verification

After deploy:

1. Check WAL mode is active:
   ```ruby
   ActiveRecord::Base.connection.execute("PRAGMA journal_mode").first
   # => {"journal_mode"=>"wal"}
   ```

2. Create 3 episodes quickly as the same user - logs should show sequential processing.

## Future Considerations

If `SQLite3::BusyException` errors persist, add a global concurrency limit (max 2 concurrent processing jobs). Start without it and monitor.
