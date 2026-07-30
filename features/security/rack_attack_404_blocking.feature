# @allow-rescue: cucumber-rails re-raises exceptions into scenarios by
# default, but these scenarios need missing routes to produce real 404
# RESPONSES (as production does) so the Log404s middleware can count them.
@rack_attack @allow-rescue
Feature: 404-scanner blocking never locks out valid users

  Path scanners probe the app with bursts of URLs that 404, so IPs producing
  repeated 404s are throttled (429) and then blocked (403) by Rack::Attack,
  fed by the Log404s middleware's per-IP counter.

  These scenarios prove BOTH sides of the contract:
    * scanners are still caught — even when they fake a session cookie;
    * valid users are never caught: signed-in users are exempt however many
      404s they hit, their 404s never poison a shared office/VPN IP, the
      sign-in endpoints are never gated (so a blocked IP can always
      re-authenticate), 404 strikes expire instead of accumulating forever,
      blocks lift on their own, and localhost health checks are untouchable.

  Background:
    Given there is a user "email=valid.user@caphive.test" for an entity "name=SecurityTestCo"

  # ──────────────────────────────────────────────────────────────────────────
  # The protection itself still works
  # ──────────────────────────────────────────────────────────────────────────

  Scenario: An anonymous scanner is blocked after repeated 404s
    Given a visitor "scanner" browsing from IP "203.0.113.66"
    When "scanner" requests 12 different missing pages
    Then "scanner" is blocked with "403" when visiting "/entities/dashboard"

  Scenario: A scanner faking a session cookie is still blocked
    Given a visitor "scanner" browsing from IP "203.0.113.67"
    And "scanner" carries a spoofed session cookie
    When "scanner" requests 12 different missing pages
    Then "scanner" is blocked with "403" when visiting "/entities/dashboard"

  Scenario: An anonymous scanner is rate-limited with 429 before the hard block
    Given the clock is frozen for predictable rate-limit windows
    And a visitor "scanner" browsing from IP "203.0.113.70"
    When "scanner" requests 7 different missing pages
    Then "scanner" receives "429" within 6 visits to "/entities/dashboard"

  # ──────────────────────────────────────────────────────────────────────────
  # Valid users are never caught
  # ──────────────────────────────────────────────────────────────────────────

  Scenario: A signed-in user is never throttled or blocked, however many 404s they hit
    Given a visitor "admin" browsing from IP "203.0.113.68"
    And "admin" signs in with valid credentials
    When "admin" requests 25 different missing pages and each returns a plain 404
    Then "admin" can still browse the app normally
    And no 404 strikes are recorded against IP "203.0.113.68"

  Scenario: A signed-in user's 404s never poison their shared office IP for colleagues
    Given a visitor "admin" browsing from IP "198.51.100.10"
    And "admin" signs in with valid credentials
    When "admin" requests 15 different missing pages and each returns a plain 404
    And a visitor "colleague" browsing from IP "198.51.100.10"
    Then "colleague" is not blocked when visiting "/users/sign_in"
    And "colleague" is not blocked when visiting "/entities/dashboard"
    And no 404 strikes are recorded against IP "198.51.100.10"

  Scenario: A valid user can always sign in even while a scanner has their shared IP blocked
    Given a visitor "scanner" browsing from IP "198.51.100.20"
    When "scanner" requests 12 different missing pages
    Then "scanner" is blocked with "403" when visiting "/entities/dashboard"
    Given a visitor "admin" browsing from IP "198.51.100.20"
    Then "admin" can load the sign-in page
    And "admin" signs in with valid credentials
    And "admin" can still browse the app normally

  Scenario: 404 strikes expire after a quiet minute and never accumulate into a block
    Given a visitor "shopper" browsing from IP "203.0.113.71"
    When "shopper" requests 4 different missing pages
    And 2 minutes pass
    And "shopper" requests 4 different missing pages
    And 2 minutes pass
    And "shopper" requests 4 different missing pages
    Then "shopper" is not blocked when visiting "/users/sign_in"
    And "shopper" is not blocked when visiting "/entities/dashboard"

  Scenario: A block automatically expires once the scanner goes quiet
    Given a visitor "scanner" browsing from IP "203.0.113.72"
    When "scanner" requests 12 different missing pages
    Then "scanner" is blocked with "403" when visiting "/entities/dashboard"
    When 7 minutes pass
    Then "scanner" is not blocked when visiting "/entities/dashboard"

  Scenario: Blocking one IP never affects visitors on other IPs
    Given a visitor "scanner" browsing from IP "203.0.113.73"
    When "scanner" requests 12 different missing pages
    Then "scanner" is blocked with "403" when visiting "/entities/dashboard"
    Given a visitor "bystander" browsing from IP "203.0.113.74"
    Then "bystander" is not blocked when visiting "/users/sign_in"
    And "bystander" is not blocked when visiting "/entities/dashboard"

  Scenario: Localhost health checks are never blocked no matter how many 404s they hit
    Given a visitor "monitor" with no forwarded IP
    When "monitor" requests 20 different missing pages and each returns a plain 404
    Then "monitor" is not blocked when visiting "/entities/dashboard"
