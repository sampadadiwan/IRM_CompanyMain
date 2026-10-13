# Host-gated serving of the static company website (public/website/) on the
# apex domain, via lib/middleware/website.rb. The @website tag makes
# features/support/website.rb set WEBSITE_HOSTS=caphive.test,www.caphive.test
# for that scenario; the untagged control scenario proves the middleware is a
# no-op when the variable is unset (as it is by default in the test env).
# Design: docs/modules/website/website_serving.md
@allow-rescue @rack_test
Feature: Static company website on the apex domain
  Visitors on the bare domain get the static website; www redirects to the
  apex; every tenant subdomain and the app itself stay untouched.

  @website
  Scenario: The apex root serves the website homepage
    # Asserts the canonical link rather than the headline: the headline is
    # marketing copy that gets reworded (it moved from "Supercharge" to
    # "Reimagine" and broke this scenario), while the canonical URL identifies
    # the homepage and is something the app itself would never serve.
    When a visitor requests "/" on host "caphive.test"
    Then the response status is 200
    And the response body contains '<link rel="canonical" href="https://caphive.com/">'

  @website
  Scenario: Inner pages are served directly
    When a visitor requests "/about.html" on host "caphive.test"
    Then the response status is 200
    And the response body contains "About Us — The Infrastructure Behind Private Capital"

  # Regression guard for the nginx /assets/ collision: the website's relative
  # asset links resolve to /assets/... on the apex and must serve the
  # website's own files, not the app's sprockets output.
  @website
  Scenario: Website assets are served with the right content type
    When a visitor requests "/assets/css/caphive.css" on host "caphive.test"
    Then the response status is 200
    And the response content type is "text/css"

  @website
  Scenario: The apex serves the website robots.txt, not the app's
    When a visitor requests "/robots.txt" on host "caphive.test"
    Then the response status is 200
    And the response body contains "Allow: /"
    And the response body contains "Disallow: /thank-you.html"

  @website
  Scenario: The apex serves the website sitemap
    When a visitor requests "/sitemap.xml" on host "caphive.test"
    Then the response status is 200
    And the response body contains "caphive.com"

  @website
  Scenario: Unknown paths get the website's styled 404 with a real 404 status
    When a visitor requests "/definitely-not-a-page" on host "caphive.test"
    Then the response status is 404
    And the response body contains "Page not found — CapHive"

  @website
  Scenario: Path traversal attempts are rejected with the website 404
    When a visitor requests "/../config/database.yml" on host "caphive.test"
    Then the response status is 404
    And the response body does not contain "adapter"

  # Extensionless URLs resolve to their .html file — matching the nginx
  # vhost's `try_files ... $uri.html ...` so dev and production agree.
  @website
  Scenario: Extensionless page URLs are served
    When a visitor requests "/about" on host "caphive.test"
    Then the response status is 200
    And the response body contains "About Us — The Infrastructure Behind Private Capital"

  # The middleware sits above Rack::Head, so it must strip HEAD bodies itself.
  @website
  Scenario: HEAD requests for missing pages return 404 with no body
    When a visitor sends a HEAD request for "/definitely-not-a-page" on host "caphive.test"
    Then the response status is 404
    And the response has an empty body

  # Legacy notification emails link to the bare domain with ?sub_domain=;
  # those visitors must land on their tenant subdomain, not the website 404.
  @website
  Scenario: Legacy sub_domain links are forwarded to the tenant subdomain
    When a visitor requests "/some/path?sub_domain=acme" on host "caphive.test"
    Then the response redirects to "http://acme.caphive.test/some/path?sub_domain=acme"

  # Scheme and any explicit port survive the redirect: in dev (http, :3001,
  # no TLS listener) a hardcoded https target would be unreachable.
  @website
  Scenario: www redirects permanently to the apex, preserving path and query
    When a visitor requests "/pricing.html?x=1" on host "www.caphive.test"
    Then the response redirects to "http://caphive.test/pricing.html?x=1"

  @website
  Scenario: www redirects keep an explicit port
    When a visitor requests "/" on host "www.caphive.test:3001"
    Then the response redirects to "http://caphive.test:3001/"

  @website
  Scenario: www redirects stay on https for TLS-terminated traffic
    When a visitor requests "/pricing.html" on host "www.caphive.test" over HTTPS
    Then the response redirects to "https://caphive.test/pricing.html"

  @website
  Scenario: The website only answers GET and HEAD
    When a visitor POSTs to "/contact.html" on host "caphive.test"
    Then the response status is 405

  @website
  Scenario: The app on other hosts is untouched
    When a visitor requests "/" on host "localhost"
    Then the response redirects to the sign-in page

  @website
  Scenario: App 404s do not get the website 404 body
    When a visitor requests "/definitely-not-a-page" on host "localhost"
    Then the response status is 404
    And the response body does not contain "Page not found — CapHive"

  # Control: no @website tag, so WEBSITE_HOSTS stays unset and even a
  # website-looking host must fall through to the app (sign-in redirect).
  Scenario: With WEBSITE_HOSTS unset the apex host falls through to the app
    When a visitor requests "/" on host "caphive.test"
    Then the response redirects to the sign-in page
