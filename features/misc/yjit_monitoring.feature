@rack_test
Feature: YJIT is monitored per process
  YJIT can be asked for (config.yjit) and still not run: a process that starts on a Ruby built
  without YJIT just runs slower, with no error anywhere. On staging, sidekiq once restarted on
  the plain Ruby while puma ran YJIT. Each puma worker and sidekiq therefore reports whether
  YJIT is running, whether it is expected, and what it costs in memory (YjitMetrics in
  config/initializers/prometheus.rb), and Grafana alerts and charts on those gauges.

  Like the clock synchronisation guard, the alert and dashboard scenarios read the provisioning
  files and build the dashboard patch in memory - they do not talk to Grafana.

  @yjit-monitoring
  Scenario: A process running YJIT reports it as running, expected, and its memory
    When I take a YJIT metrics snapshot
    Then the snapshot reports YJIT as running and expected
    And the snapshot reports YJIT's code and bookkeeping memory

  @yjit-monitoring
  Scenario: With config.yjit off, YJIT is reported as not expected
    When I take a YJIT metrics snapshot with config.yjit off
    Then the snapshot reports YJIT as not expected

  @yjit-monitoring
  Scenario: A process without YJIT where config.yjit asks for it is alerted on
    When I read the provisioned Grafana alert rules
    Then there should be an alert rule titled "YJIT Not Running Where Expected"
    And that rule should watch "ruby_yjit_expected - ruby_yjit_enabled"

  @yjit-monitoring
  Scenario: YJIT memory is alerted on before it reaches YJIT's 128 MB limit
    When I read the provisioned Grafana alert rules
    Then there should be an alert rule titled "YJIT Memory Near Limit (>115MB of 128MB)"
    And that rule should watch "ruby_yjit_code_region_bytes + ruby_yjit_alloc_bytes"
    And that rule's threshold should be below YJIT's 128 MB memory limit

  @yjit-monitoring
  Scenario: The Rails Metrics dashboard gets one YJIT row, however often it is provisioned
    When the YJIT dashboard patch is applied twice to the Rails Metrics dashboard
    Then the dashboard has one "YJIT" row
    And the dashboard has panels "YJIT Expected but Off (processes)", "YJIT Memory per Process (MB, limit 128)", "Puma Worker Memory (MB)" and "YJIT Compile Failures (per 15 min)"
