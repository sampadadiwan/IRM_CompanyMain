Feature: Cross-region hand-off, end to end
  A user signed in on one region follows the hand-off through the destination region's two hops
  and ends up signed in there - or, when something is wrong, lands on that region's own sign-in
  screen with a banner saying which of the six things went wrong and, where retrying can help,
  a link back to where they came from.

  Before this, every one of those six produced the same bare "Invalid or expired link" page,
  with no log line and nothing to click.

  Background:
    Given the regions are "IN,US"
    And a user "neha@siliconroad.com" whose stored regions are "IN,US"

  @cross-region-login @cross-region-cache @rack_test
  Scenario: H2 A hand-off signs the user in on the destination region's company site
    Given the user's company site in the destination region is "acme"
    And the current region is "IN"
    When that user starts a switch to "US"
    Then the browser should be sent to the "US" region to resolve the subdomain
    When the destination region is "US" and the browser follows that redirect
    Then the browser should be sent to host "acme.caphive.us.test" to sign in
    When the browser follows that redirect
    Then the user should be signed in on the destination region
    And the hand-off success should be logged with both regions

  @cross-region-login @cross-region-cache @rack_test
  Scenario: E5 A company with no site in the destination region falls back to the default
    Given the user's company has no site in the destination region
    And the current region is "IN"
    When that user starts a switch to "US"
    Then the browser should be sent to the "US" region to resolve the subdomain
    When the destination region is "US" and the browser follows that redirect
    Then the browser should be sent to host "app.caphive.us.test" to sign in
    When the browser follows that redirect
    Then the user should be signed in on the destination region

  @cross-region-login @cross-region-cache @rack_test
  Scenario: H3 The subdomain hop reads the credential without consuming it
    Given the user's company site in the destination region is "acme"
    And the current region is "IN"
    When that user starts a switch to "US"
    When the destination region is "US" and the browser follows that redirect
    Then the credential should still be unclaimed
    When the browser follows that redirect
    Then the user should be signed in on the destination region

  @cross-region-login @cross-region-cache @rack_test
  Scenario: X1 An expired credential explains itself and offers a way back
    Given the current region is "IN"
    And a hand-off credential that expired 6 minutes ago
    When the destination region is "US" and that credential is presented for sign-in
    Then the user should not be signed in
    And the sign-in screen should show the "expired" cross-region banner
    And the banner should offer a way back to "IN"
    And the rejection logged should be "expired"

  @cross-region-login @cross-region-cache @rack_test
  Scenario: X2 A credential already used is refused, with a way back
    Given the user's company site in the destination region is "acme"
    And the current region is "IN"
    When that user starts a switch to "US"
    When the destination region is "US" and the browser follows that redirect
    And the browser follows that redirect
    Then the user should be signed in on the destination region
    When that same credential is presented for sign-in again from a different browser
    Then the sign-in screen should show the "already_used" cross-region banner
    And the banner should offer a way back to "IN"
    And the rejection logged should be "already_used"

  @cross-region-login @cross-region-cache @rack_test
  Scenario: X3 A hand-off with no credential at all dead-ends into the sign-in form
    Given the current region is "US"
    When the sign-in hop is requested with no credential
    Then the user should not be signed in
    And the sign-in screen should show the "missing" cross-region banner
    And the banner should offer no way back
    And the rejection logged should be "missing"

  @cross-region-login @cross-region-cache @rack_test
  Scenario: X4 A tampered credential is reported as invalid, not as expired
    Given the current region is "IN"
    When a hand-off credential is minted for that user targeting "US"
    And the credential is tampered with
    And the destination region is "US" and that credential is presented for sign-in
    Then the user should not be signed in
    And the sign-in screen should show the "invalid" cross-region banner
    And the banner should offer no way back
    And the rejection logged should be "invalid"

  @cross-region-login @cross-region-cache @rack_test
  Scenario: X5 A credential meant for another region is refused
    Given the current region is "US"
    When a hand-off credential is minted for that user targeting "IN"
    And the destination region is "US" and that credential is presented for sign-in
    Then the user should not be signed in
    And the sign-in screen should show the "wrong_region" cross-region banner
    And the rejection logged should be "wrong_region"

  @cross-region-login @cross-region-cache @rack_test
  Scenario: X6 A credential minted for another purpose is refused
    Given the current region is "IN"
    And a hand-off credential minted with purpose "password_reset" targeting "US"
    When the destination region is "US" and that credential is presented for sign-in
    Then the user should not be signed in
    And the sign-in screen should show the "invalid" cross-region banner
    And the rejection logged should be "invalid"

  @cross-region-login @cross-region-cache @rack_test
  Scenario: X7 Divergent region secrets are reported as a configuration problem, with no retry
    Given the current region is "IN"
    When a hand-off credential is minted for that user targeting "US"
    And the credential is tampered with
    And the hourly trust check has found the regions' secrets differ
    And the destination region is "US" and that credential is presented for sign-in
    Then the sign-in screen should show the "secret_mismatch" cross-region banner
    And the banner should offer no way back
    And the rejection logged should be "secret_mismatch"

  @cross-region-login @cross-region-cache @rack_test
  Scenario: X8 A user with no account in the destination region is told so
    Given the current region is "IN"
    And a hand-off credential for "nobody@siliconroad.com" targeting "US"
    When the destination region is "US" and that credential is presented for sign-in
    Then the user should not be signed in
    And the sign-in screen should show the "no_account" cross-region banner
    And the rejection logged should be "no_account"

  @cross-region-login @cross-region-cache @rack_test
  Scenario: E6 Clock drift smaller than the credential's lifetime is tolerated
    Given the current region is "IN"
    And the destination region's clock is 3 minutes ahead
    When a hand-off credential is minted for that user targeting "US"
    And the destination region is "US" and that credential is presented for sign-in
    Then the user should be signed in on the destination region

  @cross-region-login @cross-region-cache @rack_test
  Scenario: E6 Clock drift larger than the credential's lifetime is not
    Given the current region is "IN"
    And the destination region's clock is 7 minutes ahead
    When a hand-off credential is minted for that user targeting "US"
    And the destination region is "US" and that credential is presented for sign-in
    Then the sign-in screen should show the "expired" cross-region banner

  @cross-region-login @cross-region-cache @rack_test
  Scenario: E7 Two simultaneous presentations produce exactly one session
    Given the current region is "IN"
    When a hand-off credential is minted for that user targeting "US"
    And the credential is claimed by 8 threads at once
    Then exactly one claim should have won

  @cross-region-login @cross-region-cache @rack_test
  Scenario: E8 A credential consumed on one app server is consumed on the other
    Given the current region is "IN"
    When a hand-off credential is minted for that user targeting "US"
    And the credential is claimed once
    Then a claim from another app server should be refused

  @cross-region-login @cross-region-cache
  Scenario: X14 No rejection page exposes the credential or anything technical
    Given the current region is "IN"
    When a hand-off credential is minted for that user targeting "US"
    And the credential is tampered with
    And the destination region is "US" and that credential is presented for sign-in
    Then the page should not contain the credential
    And the page should not contain a server hostname
    And the page should not name an internal error class

  @cross-region-login @cross-region-cache @rack_test
  Scenario: X15 The credential never reaches a log line
    Given the current region is "IN"
    And a hand-off credential that expired 6 minutes ago
    When the destination region is "US" and that credential is presented for sign-in
    Then the captured log should not contain the credential
    And the captured log should name the reason and the user

  @cross-region-login @cross-region-cache @rack_test
  Scenario: An unconfigured shared secret is a configuration problem, not a 500
    Given the current region is "US"
    And this region has no inter-region secret configured
    When the sign-in hop is requested with no credential
    Then the user should not be signed in
    And the sign-in screen should show the "secret_mismatch" cross-region banner
    And the banner should offer no way back
