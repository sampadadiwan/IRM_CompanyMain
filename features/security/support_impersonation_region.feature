Feature: Security M5 - no region switch while support is impersonating
  The region hand-off credential names only the user's email, so a support user who switched
  region while impersonating was signed in on the other region AS the client, with no record of
  who was acting. The switch is now refused while impersonating, and the region selector is
  hidden in that session; support signs into the other region themselves.
  Design: docs/security/security_review_2026_10.md, "Authentication and session — Medium / Low", M5

  Background:
    Given the regions are "IN,US"
    And the current region is "IN"
    And a user "neha@siliconroad.com" whose stored regions are "IN,US"

  # M5-H — Happy path: the user themselves sees the selector and switches region as before
  @security @cross-region-issuance @rack_test
  Scenario: M5-H A multi-region user switches region
    When that user starts a switch to "US"
    Then the browser should be sent to the "US" region to resolve the subdomain
    And the signed-in pages show the region selector

  # M5-1 — Error case: support impersonating the same user is refused, and sees no selector
  @security @cross-region-issuance @rack_test
  Scenario: M5-1 Support impersonating a user cannot switch region
    When a support user impersonating that user starts a switch to "US"
    Then the switch is refused with "Region switching is not available while you are signed in as another user"
    And the signed-in pages show no region selector
