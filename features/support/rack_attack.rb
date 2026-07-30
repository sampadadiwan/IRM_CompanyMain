# Support for @rack_attack scenarios, which exercise the 404-scanner defenses
# (Log404s middleware + Rack::Attack rules) through the full middleware stack.
#
# The test environment normally neuters both halves of that system:
#   * config.cache_store is :null_store, so 404 counters and block flags
#     would silently never persist — this hook swaps in a real store;
#   * cucumber-rails re-raises exceptions into scenarios instead of rendering
#     the 404 RESPONSES the middleware counts — the feature carries the
#     built-in @allow-rescue tag to restore production-style rendering.
# Everything is restored afterwards, so no other feature is affected.

# travel/travel_to power the "minutes pass" steps that prove counters and
# block flags expire on their own.
World(ActiveSupport::Testing::TimeHelpers)

Around('@rack_attack') do |_scenario, block|
  original_cache = Rails.cache
  original_attack_store = Rack::Attack.cache.store

  # A fresh in-memory store per scenario: counters/flags work like production
  # (including expiry) and cannot leak between scenarios.
  Rails.cache = ActiveSupport::Cache::MemoryStore.new
  # Rack::Attack captured the boot-time null store; point its internal
  # throttle bookkeeping at the same live store as the custom rules.
  Rack::Attack.cache.store = Rails.cache

  block.call
ensure
  Rack::Attack.cache.store = original_attack_store
  Rails.cache = original_cache
  # Undo any travel/travel_to a step performed.
  travel_back
end
