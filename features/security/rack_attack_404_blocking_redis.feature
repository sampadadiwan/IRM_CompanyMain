# The same defenses as rack_attack_404_blocking.feature, but with
# Rack::Attack.cache.store pointed at a REAL Redis-backed RedisCacheStore —
# the store production/staging use (config/initializers/rack_attack.rb).
#
# Why a second feature instead of more scenarios in the first one: the sibling
# feature runs on an in-memory store, and rack-attack treats the two very
# differently. A RedisCacheStore gets wrapped in RedisCacheStoreProxy, which
# forces `raw: true` on read AND write (so the `true` block flag is stored and
# compared as the string "true", and the 404 counter becomes a Redis INCRBY
# with a TTL set on first write), and the store applies a :namespace to every
# key. A MemoryStore is not proxied and does none of that, so a break in any
# of it would only ever surface in production. See features/support/rack_attack.rb.
#
# Needs a Redis on REDIS_URL (default redis://localhost:6379); the hook fails
# with an explicit message rather than passing vacuously if there isn't one.
#
# @allow-rescue: as in the sibling feature, missing routes must produce real
# 404 RESPONSES rather than re-raised exceptions, so Log404s can count them.
@rack_attack_redis @allow-rescue
Feature: 404-scanner blocking works against the real Redis store

  Background:
    Given there is a user "email=valid.user@caphive.test" for an entity "name=SecurityTestCo"

  # Exercises the whole Redis round trip: Log404s' INCRBY creates the counter
  # with a TTL, the blocklist reads it back raw, writes the `true` flag through
  # the proxy (which stores "true"), then reads that flag back and blocks.
  Scenario: An anonymous scanner is blocked after repeated 404s
    Given a visitor "scanner" browsing from IP "203.0.113.90"
    When "scanner" requests 12 different missing pages
    Then "scanner" is blocked with "403" when visiting "/entities/dashboard"

  # Rack::Attack's OWN throttle bookkeeping (Cache#count -> store.increment,
  # not this app's manual keys) against Redis, including the expires_in it
  # derives per epoch window.
  Scenario: An anonymous scanner is rate-limited with 429 before the hard block
    Given the clock is frozen for predictable rate-limit windows
    And a visitor "scanner" browsing from IP "203.0.113.91"
    When "scanner" requests 7 different missing pages
    Then "scanner" receives "429" within 6 visits to "/entities/dashboard"

  # The block flag has to persist in Redis while the auth-path exemption still
  # lets the same IP reach sign-in — the lockout case that matters most.
  Scenario: A valid user can always sign in even while a scanner has their shared IP blocked
    Given a visitor "scanner" browsing from IP "198.51.100.90"
    When "scanner" requests 12 different missing pages
    Then "scanner" is blocked with "403" when visiting "/entities/dashboard"
    Given a visitor "admin" browsing from IP "198.51.100.90"
    Then "admin" can load the sign-in page
    And "admin" signs in with valid credentials
    And "admin" can still browse the app normally

  # Also pins the "no 404 strikes" assertion to Rack::Attack.cache.store: here
  # Rails.cache is a separate, always-empty MemoryStore, so an assertion that
  # read Rails.cache would pass no matter what the middleware wrote.
  Scenario: A signed-in user is never throttled or blocked, however many 404s they hit
    Given a visitor "admin" browsing from IP "203.0.113.92"
    And "admin" signs in with valid credentials
    When "admin" requests 25 different missing pages and each returns a plain 404
    Then "admin" can still browse the app normally
    And no 404 strikes are recorded against IP "203.0.113.92"
