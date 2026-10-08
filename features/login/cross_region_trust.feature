Feature: Inter-region trust verification
  The two regions' CROSS_INSTANCE_SECRET lives in separate encrypted credentials files with
  separate keys, so they can silently diverge - and when they do, every region switch fails.
  Each region publishes a non-reversible fingerprint so the divergence can be seen, and the
  hourly check turns it into an alert instead of a wall of identical failures.

  @cross-region-trust
  Scenario: H4 Two regions configured with the same secret produce the same fingerprint
    Given region "IN" is configured with inter-region secret "shared-secret-value"
    And I capture the trust fingerprint as "in"
    Given region "US" is configured with inter-region secret "shared-secret-value"
    And I capture the trust fingerprint as "us"
    Then the captured fingerprints "in" and "us" should match

  @cross-region-trust
  Scenario: Two regions configured with different secrets produce different fingerprints
    Given region "IN" is configured with inter-region secret "india-secret"
    And I capture the trust fingerprint as "in"
    Given region "US" is configured with inter-region secret "us-secret-diverged"
    And I capture the trust fingerprint as "us"
    Then the captured fingerprints "in" and "us" should not match

  @cross-region-trust
  Scenario: E10 The trust endpoint discloses a fingerprint and nothing else
    Given region "IN" is configured with inter-region secret "a-very-distinctive-secret"
    When I request the cross-site trust endpoint
    Then the trust response should report the region as "IN"
    And the trust response should report the secret as configured
    And the trust response fingerprint should be 64 hex characters
    And the trust response should not contain "a-very-distinctive-secret"

  @cross-region-trust
  Scenario: E9 A region with no shared secret reports it rather than returning a fingerprint
    Given region "IN" is configured with no inter-region secret
    When I request the cross-site trust endpoint
    Then the trust response should report the secret as not configured
    And the trust response fingerprint should be empty

  @cross-region-trust @sync-http @cross-region-cache
  Scenario: The hourly check flags a divergent peer and leaves an alertable gauge
    Given region "IN" is configured with inter-region secret "india-secret"
    And peer region "US" reports fingerprint for secret "us-secret-diverged"
    When the cross-site trust check runs
    Then a peer secret mismatch should be recorded

  @cross-region-trust @sync-http @cross-region-cache
  Scenario: The hourly check clears the flag when the peer agrees
    Given region "IN" is configured with inter-region secret "shared-secret-value"
    And peer region "US" reports fingerprint for secret "shared-secret-value"
    When the cross-site trust check runs
    Then no peer secret mismatch should be recorded

  @cross-region-trust @sync-http @cross-region-cache
  Scenario: A peer that reports no secret at all counts as a divergence
    Given region "IN" is configured with inter-region secret "india-secret"
    And peer region "US" reports that it has no secret configured
    When the cross-site trust check runs
    Then a peer secret mismatch should be recorded

  @cross-region-trust @sync-http @cross-region-cache
  Scenario: An unreachable peer is not treated as a divergence
    Given region "IN" is configured with inter-region secret "india-secret"
    And a peer secret mismatch has previously been recorded as "false"
    And peer region "US" is unreachable
    When the cross-site trust check runs
    Then no peer secret mismatch should be recorded
