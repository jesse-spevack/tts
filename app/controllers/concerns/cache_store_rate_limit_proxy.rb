# frozen_string_literal: true

# Thin proxy around Rails.cache so `rate_limit store: ...` is resolved at
# request time. Rails 8's `rate_limit` captures `store:` at class-load via the
# `cache_store` default, and the test env default is :null_store (no-op). The
# proxy lets tests swap Rails.cache for a MemoryStore and exercise the limiter.
class CacheStoreRateLimitProxy
  def increment(*args, **kwargs) = Rails.cache.increment(*args, **kwargs)
end
