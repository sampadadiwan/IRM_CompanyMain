Feature: Clock synchronisation and cross-region alerting are provisioned
  Clock drift between the regions is the one cause of a failed region switch that leaves no
  trace at all: the hand-off credential carries an absolute expiry stamped by the issuing
  region and checked against the verifying region's clock, and nothing in the deploy or the
  dashboards used to assert that a time daemon was even running.

  This is a configuration guard, in the style of the notification attachment-size guard - it
  asserts the rules and the deploy check exist, not that live infrastructure is healthy.

  @clock-sync-monitoring
  Scenario: X17 Clock drift is alerted on well below the credential's lifetime
    When I read the provisioned Grafana alert rules
    Then there should be an alert rule titled "Server Clock Drift (>30s)"
    And that rule should watch "node_timex_offset_seconds"
    And that rule's threshold should be below the hand-off credential lifetime

  @clock-sync-monitoring
  Scenario: X17 A stopped time daemon is alerted on before any offset accumulates
    When I read the provisioned Grafana alert rules
    Then there should be an alert rule titled "Server Clock Unsynchronised"
    And that rule should watch "node_timex_sync_status"

  @clock-sync-monitoring
  Scenario: A divergence between the regions' shared secrets is alerted on
    When I read the provisioned Grafana alert rules
    Then there should be an alert rule titled "Cross-Region Trust Broken"
    And that rule should watch "caphive_cross_region_trust"

  @clock-sync-monitoring
  Scenario: A rise in rejected hand-offs is alerted on
    When I read the provisioned Grafana alert rules
    Then there should be an alert rule titled "Cross-Region Hand-off Rejections"
    And that rule should watch "caphive_cross_region_handoff_total"

  @clock-sync-monitoring
  Scenario: Every provisioned rule uses a comparator the provisioner can build
    When I read the provisioned Grafana alert rules
    Then every rule should use only the "threshold_gt" comparator

  @clock-sync-monitoring
  Scenario: X16 The deploy asserts clock synchronisation on every app server
    When I read the deploy configuration
    Then it should define a "check_clock_sync" task
    And that task should run on the app role
    And that task should check both NTP synchronisation and the time daemon
