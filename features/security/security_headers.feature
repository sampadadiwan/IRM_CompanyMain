Feature: Security L5 - security headers and host checking
  Every response now enforces object-src 'none', base-uri 'self' and frame-ancestors 'self', sends
  the full Content-Security-Policy as report-only (nonce scripts, CDN allowlist, reports to
  /csp_reports) and a Permissions-Policy. Host authorization (BASE_DOMAIN and its subdomains,
  tenant custom domains, health checks excluded) is built but off unless
  ENFORCE_HOST_AUTHORIZATION=1; the session cookie keeps domain: :all.
  Design: docs/security/security_review_2026_10.md, "Authentication and session — Medium / Low", L5

  # L5-H — Happy path: a page carries the enforced CSP, the report-only CSP and the Permissions-Policy
  @security @rack_test
  Scenario: L5-H A page carries the security headers
    When I am at the login page
    Then the enforced CSP is "object-src 'none'; base-uri 'self'; frame-ancestors 'self'"
    And the report-only CSP includes "script-src 'self'"
    And the report-only CSP includes "'nonce-"
    And the report-only CSP includes "report-uri /csp_reports"
    And the Permissions-Policy includes "microphone=(self)"
    And the Permissions-Policy includes "geolocation=()"

  # L5-1 — Edge case: a browser's violation report is accepted and logged without the page's query string
  @security
  Scenario: L5-1 A CSP violation report is logged without query strings
    When a browser reports a "script-src-elem" violation on "https://app.caphive.test/funds/1?token=secret123"
    Then the CSP report is answered with 204
    And the CSP log names "script-src-elem" and "https://app.caphive.test/funds/1"
    And the CSP log does not contain "secret123"

  # L5-2 — Error case: with host checking on, unknown hosts get 403 while our domains, custom domains and health checks pass
  @security
  Scenario: L5-2 Host checking allows only this deployment's hosts
    Given host checking is on for the base domain "caphive.test"
    And a tenant has the custom domain "acmecapital.example"
    Then requests answer as follows:
      | host                         | path                    | status |
      | app.caphive.test             | /                       | 200    |
      | acme.caphive.test:443        | /                       | 200    |
      | caphive.test                 | /                       | 200    |
      | invest.acmecapital.example   | /                       | 200    |
      | evil.example                 | /                       | 403    |
      | caphive.test.evil.example    | /                       | 403    |
      | 10.0.3.5                     | /                       | 403    |
      | 10.0.3.5                     | /health_check/db_check  | 200    |

  # L5-3 — Edge case: the Outlook task pane keeps its own frame-ancestors allowlist, with object-src and base-uri added
  @security @rack_test
  Scenario: L5-3 The Outlook task pane keeps its framing allowlist
    When I open the Outlook task pane
    Then the enforced CSP includes "frame-ancestors 'self' https://outlook.office.com"
    And the enforced CSP includes "object-src 'none'"
    And the enforced CSP includes "base-uri 'self'"
