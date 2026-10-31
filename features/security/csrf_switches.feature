Feature: Security L4 - CSRF cannot be switched off outside development
  VULN_SCAN=true switched CSRF verification off for every controller, and
  SKIP_AUTHENTICITY_TOKEN=true did the same in any environment. The skip is now honoured in
  development only (for local ngrok work), production and staging refuse to boot with it, and
  VULN_SCAN keeps only its exception-mail meaning.
  Design: docs/security/security_review_2026_10.md, "Authentication and session — Medium / Low", L4

  The test environment runs with forgery protection off; @csrf-protection switches it on for the
  scenario and restores it (and the two environment switches) afterwards.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Company"

  # L4-H — Happy path: a form post without the CSRF token is refused
  @security @rack_test @csrf-protection
  Scenario: L4-H A post without the CSRF token is refused
    When I accept the terms without a CSRF token
    Then I should see "Please refresh screen and retry"
    And the user has not accepted the terms

  # L4-1 — Error case: with SKIP_AUTHENTICITY_TOKEN and VULN_SCAN both "true" outside development, CSRF still applies and staging/production would not boot
  @security @rack_test @csrf-protection
  Scenario: L4-1 The CSRF switches are ignored outside development
    Given the environment sets SKIP_AUTHENTICITY_TOKEN and VULN_SCAN to "true"
    When I accept the terms without a CSRF token
    Then I should see "Please refresh screen and retry"
    And the user has not accepted the terms
    And the CSRF boot guard refuses SKIP_AUTHENTICITY_TOKEN in "production" and "staging"
    And the CSRF skip is honoured only in "development"
