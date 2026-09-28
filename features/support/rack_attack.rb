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

# Support for @rack_attack_redis scenarios.
#
# The hook above runs the rules against a MemoryStore, which proves the RULES
# but says nothing about the store production actually uses. Two things only
# exist on the Redis path:
#
#   * rack-attack wraps an ActiveSupport::Cache::RedisCacheStore in
#     RedisCacheStoreProxy (BaseProxy.lookup matches on the exact class name),
#     and that proxy force-merges `raw: true` into read AND write — so the
#     `true` block/throttle flags round-trip as the STRING "true", and the
#     404 counter is a Redis INCRBY rather than a marshalled entry;
#   * the store carries a :namespace, applied in normalize_key.
#
# A MemoryStore is not proxied at all, so a regression in either would ship
# invisibly. These scenarios re-run the core block/throttle/exemption path
# against a real Redis instead.
#
# Deliberately NOT ported: the travel_to expiry scenarios ("2 minutes pass").
# Redis TTLs are wall-clock, so time travel cannot expire a real key — those
# stay on the MemoryStore feature, where they are a fair test of the TTL
# bookkeeping this app owns.
Around('@rack_attack_redis') do |_scenario, block|
  original_cache = Rails.cache
  original_attack_store = Rack::Attack.cache.store

  # Rails.cache stays in memory — only the ATTACK store goes to Redis, which
  # is also how production is split (Redis vs Solid Cache). That split is the
  # point: any step or rule that reaches for Rails.cache instead of
  # Rack::Attack.cache.store now reads an empty store and fails here.
  Rails.cache = ActiveSupport::Cache::MemoryStore.new

  # A namespace unique per scenario AND per parallel test process, so counters
  # cannot leak between scenarios or between concurrent cucumber runs and no
  # flush of a shared Redis is ever needed — every key written here carries a
  # 1-to-5-minute TTL and expires on its own.
  store = ActiveSupport::Cache::RedisCacheStore.new(
    url: ENV.fetch('REDIS_URL', 'redis://localhost:6379'),
    namespace: "rack_attack_test:#{ENV.fetch('TEST_ENV_NUMBER', '0')}:#{SecureRandom.hex(6)}"
  )

  # Ping OUTSIDE the cache API on purpose: RedisCacheStore#failsafe swallows
  # every Redis::BaseError and returns nil, so without this the scenarios
  # would "pass" against a dead Redis by never throttling anything — the exact
  # fail-open the production config's timeouts are written around. Fail loudly
  # instead of skipping: a security test that quietly opts out is worse than
  # one that is red.
  begin
    store.redis.then { |conn| conn.ping }
  rescue StandardError => e
    raise "@rack_attack_redis needs a Redis at " \
          "#{ENV.fetch('REDIS_URL', 'redis://localhost:6379')} " \
          "(#{e.class}: #{e.message}). Start one, or set REDIS_URL."
  end

  Rack::Attack.cache.store = store

  block.call
ensure
  Rack::Attack.cache.store = original_attack_store
  Rails.cache = original_cache
  travel_back
end
