@rack_test
Feature: The data box's Elasticsearch, Redis and MySQL memory are monitored
  The data box (MySQL + Elasticsearch + Redis on one host) sat at ~85% memory all week, and Grafana
  could not say which service held it: Prometheus scraped only node_exporter and mysqld_exporter.
  rake "observability:data_box_exporters[<env>]" installs elasticsearch_exporter and
  redis_exporter, turns on mysqld_exporter's memory collector and points Prometheus at them; the
  Grafana alerts and the Data Box dashboard row read what they report.

  These scenarios exercise the pure decisions (lib/data_box_exporters.rb) and read the repo's
  provisioning files - they do not touch a box, Prometheus or Grafana.

  # H1 — Happy path: each exporter runs as its own no-login user on its pinned port
  Scenario Outline: An exporter's systemd unit runs the pinned binary on its port
    When the data box unit for "<exporter>" is rendered
    Then the data box unit runs "/usr/local/bin/<exporter>" listening on ":<port>"
    And the data box unit runs as the user "<exporter>"

    Examples:
      | exporter               | port |
      | elasticsearch_exporter | 9114 |
      | redis_exporter         | 9121 |

  # H2 — Happy path (security): the download is verified before anything is installed
  Scenario: The install script checks the release checksum before installing the binary
    When the data box install script for "redis_exporter" is rendered
    Then the data box install script verifies "sha256sums.txt" before it installs the binary
    And the data box install script prints OK only after "/metrics" serves "redis_memory_used_bytes"

  # X4 — Error case (prod IN, 2026-11-09): elasticsearch_exporter was reported FAILED although it
  # served the metric - `curl | grep -q` under pipefail fails once /metrics outgrows the pipe buffer
  Scenario Outline: The metric check reads the whole of /metrics, however large
    When the data box install script for "<exporter>" is rendered
    Then the data box install script never pipes into grep -q

    Examples:
      | exporter               |
      | elasticsearch_exporter |
      | redis_exporter         |

  # H3 — Happy path: the unit setup.sh wrote, without the memory collector
  Scenario: The memory collector is added to mysqld_exporter's ExecStart line
    Given a data box mysqld_exporter unit:
      """
      [Service]
      User=mysqld_exporter
      ExecStart=/usr/local/bin/mysqld_exporter --config.my-cnf=/etc/.mysqld_exporter.cnf --collect.perf_schema.file_events --web.listen-address=:9104
      Restart=always
      """
    When the data box memory collector is added
    Then the data box collector change is "changed"
    And the data box ExecStart line reads "ExecStart=/usr/local/bin/mysqld_exporter --config.my-cnf=/etc/.mysqld_exporter.cnf --collect.perf_schema.file_events --collect.perf_schema.memory_events --web.listen-address=:9104"
    And every other data box unit line is unchanged

  # E1 — Edge case: a re-run finds the collector already there
  Scenario: A unit that already has the memory collector is left alone
    Given a data box mysqld_exporter unit:
      """
      ExecStart=/usr/local/bin/mysqld_exporter --collect.perf_schema.memory_events --web.listen-address=:9104
      """
    When the data box memory collector is added
    Then the data box collector change is "unchanged"

  # X1 — Error case: never guess at a unit it does not recognise
  Scenario: A unit without a mysqld_exporter ExecStart line is refused
    Given a data box mysqld_exporter unit:
      """
      [Service]
      ExecStart=/usr/local/bin/node_exporter
      """
    When the data box memory collector is added
    Then the data box collector change is "refused"

  # H4 — Happy path: live Prometheus is the repo copy from before this change
  Scenario: The repo config replaces the live one when only the new jobs differ
    Given the live Prometheus config is the "production.in" repo config without the "elasticsearch" and "redis" jobs
    When the data box Prometheus push is planned against the "production.in" repo config
    Then the data box Prometheus push is "push"

  # E2 — Edge case: a re-run after a successful push
  Scenario: A live config that already matches the repo is left alone
    Given the live Prometheus config is the "production.in" repo config
    When the data box Prometheus push is planned against the "production.in" repo config
    Then the data box Prometheus push is "unchanged"

  # X2 — Error case: a live edit nobody committed is never overwritten
  Scenario: A live config with an uncommitted change is refused, naming the job
    Given the live Prometheus config is the "production.in" repo config with the "node" job's targets changed
    When the data box Prometheus push is planned against the "production.in" repo config
    Then the data box Prometheus push is "refused" mentioning "node"

  # X5 — Error case (prod US, 2026-11-09): stray SSH output inside the read is named, not hidden
  Scenario: A live config read with an SSH warning in it is refused, naming the stray key
    Given the live Prometheus config is the "production.in" repo config preceded by "Warning: Permanently added '10.0.1.157' (ED25519) to the list of known hosts."
    When the data box Prometheus push is planned against the "production.in" repo config
    Then the data box Prometheus push is "refused" mentioning "Warning"

  # X3 — Error case: Prometheus is not where the task expects it
  Scenario: An unreadable live config is refused
    Given the live Prometheus config is "cat: /etc/prometheus/prometheus.yml: No such file or directory"
    When the data box Prometheus push is planned against the "production.in" repo config
    Then the data box Prometheus push is "refused" mentioning "could not be read"

  # H5 — Drift guard: Prometheus scrapes each exporter where the app's own service URL points
  Scenario Outline: Each region's Prometheus config scrapes the exporters on its data box
    Then the "<env>" repo Prometheus config scrapes "elasticsearch" on port 9114 at the ELASTIC_SEARCH_URL host
    And the "<env>" repo Prometheus config scrapes "redis" on port 9121 at the REDIS_URL host

    Examples:
      | env           |
      | production.in |
      | production.us |

  # E3 — Edge case: both URL forms in the .env files resolve to the bare host
  Scenario Outline: The data box host is read from either service URL form
    Then the data box host of "<url>" is "<host>"

    Examples:
      | url                         | host       |
      | 10.0.3.182:9200             | 10.0.3.182 |
      | redis://10.0.3.182:6379     | 10.0.3.182 |
      | redis://:secret@10.0.3.9:6379/0 | 10.0.3.9 |

  # H6 — Happy path: the alerts read what the exporters report
  Scenario Outline: The data box services are alerted on
    When I read the provisioned Grafana alert rules
    Then there should be an alert rule titled "<title>"
    And that rule should watch "<metric>"

    Examples:
      | title                                       | metric                         |
      | Redis Down                                  | redis_up                       |
      | Redis Memory Near Limit (>85% of maxmemory) | redis_memory_max_bytes > 0     |
      | Elasticsearch Down                          | elasticsearch_clusterinfo_up   |
      | Elasticsearch Cluster Red                   | color="red"                    |
      | Elasticsearch Heap High (>90%)              | elasticsearch_jvm_memory_max_bytes |
      | Data Box Exporter Down                      | up{job=~"elasticsearch\|redis"} |

  # E4 — Edge case: provisioning twice must not add a second row, and a re-run replaces the panels
  # an earlier version put there (three moved to the Elasticsearch / Redis dashboards, 2026-11-09)
  Scenario: The Rails Metrics dashboard gets one Data Box row, however often it is provisioned
    When the data box dashboard patch is applied twice to the Rails Metrics dashboard
    Then the dashboard has one "Data Box" row
    And the dashboard has the data box panels
    And the dashboard has no "Elasticsearch Heap (used vs max)" panel

  # H7 — Happy path: Elasticsearch and Redis each get their own dashboard
  Scenario Outline: The service dashboards are built with their panels, browser-safe
    When the "<uid>" service dashboard is built
    Then the service dashboard is titled "<title>" with panels "<first>" and "<last>"
    And every service dashboard panel has a unique id and the datasource uid
    And no service dashboard query contains "})/"

    Examples:
      | uid                   | title         | first                               | last                           |
      | caphive-elasticsearch | Elasticsearch | Health (0 green · 1 yellow · 2 red) | Index Size per Index (primary) |
      | caphive-redis         | Redis         | Redis down (0 = up)                 | Error Replies (per s)          |
