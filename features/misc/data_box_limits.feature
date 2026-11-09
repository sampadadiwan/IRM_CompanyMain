@rack_test
Feature: The data box's Elasticsearch and Redis get memory limits sized from their own peaks
  On prod IN the data box sat at ~85% memory: Elasticsearch had auto-sized its heap to half the RAM
  (3.9 GB) for 117.5 MB of live data, and Redis peaked at 4.2 MB with no maxmemory. One rule sizes
  both (agreed 2026-11-09): limit = max(3 x peak usage, 512 MB). rake "ops:data_box_limits[<env>]"
  applies it, gives Elasticsearch a data volume and a restart policy, and makes the limits survive
  a reboot through start_data_containers.sh.

  These scenarios exercise the pure decisions (lib/data_box_limits.rb) - they touch no box.

  # H1 — Happy path: prod IN's real numbers (Prometheus, 2026-11-09)
  Scenario Outline: The limits follow max(3 x peak, 512 MB)
    When the data box limits are sized for an Elasticsearch old-generation peak of <old_mb> MB and a Redis peak of <redis_mb> MB
    Then the Elasticsearch heap is <heap> MB with a container cap of <cap> MB
    And the Redis maxmemory is <maxmemory> MB

    Examples:
      | old_mb | redis_mb | heap | cap  | maxmemory |
      | 117.5  | 4.2      | 512  | 1536 | 512       |
      | 400    | 300      | 1280 | 2560 | 900       |
      | 0      | 0        | 512  | 1536 | 512       |

  # H2 — Happy path: today's container (raw crontab line: --rm, no cap, no volume, auto heap)
  Scenario: Every difference from the target is listed
    Given the live Elasticsearch container runs "elasticsearch:8.19.0" with --rm, no memory cap, no volume and settings "discovery.type=single-node,xpack.security.enabled=false"
    When its drift from a 512 MB heap and a 1536 MB cap is checked
    Then the Elasticsearch drift mentions "memory cap none", "heap auto", "--rm" and "inside the container"
    And re-creating the Elasticsearch container is allowed

  # E1 — Edge case: a re-run after the change finds nothing to do
  Scenario: A container already at the target is not touched
    Given the live Elasticsearch container already matches a 512 MB heap, a 1536 MB cap, the volume and unless-stopped
    When its drift from a 512 MB heap and a 1536 MB cap is checked
    Then there is no Elasticsearch drift

  # X1 — Error case: a setting the start script does not carry would be lost
  Scenario: A container with an extra setting is not re-created
    Given the live Elasticsearch container runs "elasticsearch:8.19.0" with --rm, no memory cap, no volume and settings "discovery.type=single-node,cluster.name=caphive"
    Then re-creating the Elasticsearch container is refused mentioning "cluster.name"

  # X2 — Error case: another image could not be swapped in silently
  Scenario: A container on another image is not re-created
    Given the live Elasticsearch container runs "elasticsearch:8.11.1" with --rm, no memory cap, no volume and settings "discovery.type=single-node"
    Then re-creating the Elasticsearch container is refused mentioning "align them first"

  # X5 — Error case (prod US, 2026-11-09): a leftover volume would bring back stale indexes
  Scenario Outline: An existing volume the live container does not use is moved aside first
    Given the live Elasticsearch container runs "elasticsearch:8.19.0" with --rm, no memory cap, no volume and settings "discovery.type=single-node"
    Then an existing elasticsearch-data volume "<exists>" is "<verdict>"

    Examples:
      | exists | verdict          |
      | yes    | moved aside      |
      | no     | not a stale case |

  # H3 — Happy path: staging's crontab, verbatim shape from the 2026-11-08 probe
  Scenario: The raw boot lines are replaced by the start script, other lines kept
    Given a data box crontab:
      """
      @reboot /bin/bash -l -c 'sudo docker run -d --rm --name elasticsearch -p 9200:9200 elasticsearch:8.19.0'
      @reboot sudo docker run -d --rm --name redis-stack-server -p 6379:6379 redis/redis-stack-server:latest
      0 23 * * * /home/ubuntu/backup_db.sh full >> /tmp/mysql_backup_full.log 2>&1
      """
    When the data box crontab is planned
    Then the data box crontab change is "changed" removing 2 lines
    And the data box crontab boots through the start script
    And the data box crontab still has "0 23 * * * /home/ubuntu/backup_db.sh full >> /tmp/mysql_backup_full.log 2>&1"

  # E2 — Edge case: the second run finds the script line already there
  Scenario: A crontab already on the start script is left alone
    Given a data box crontab:
      """
      @reboot /usr/local/bin/start_data_containers.sh >> /home/ubuntu/start_data_containers.log 2>&1
      """
    When the data box crontab is planned
    Then the data box crontab change is "unchanged" removing 0 lines

  # E3 — Edge case: Redis INFO arrives with CRLF line endings from redis-cli
  Scenario: Redis INFO memory is read field by field
    When Redis INFO memory reports used 3815064, peak 4404019, maxmemory 0 and policy "noeviction"
    Then the data box Redis reading is used 3815064, peak 4404019, maxmemory 0 and policy "noeviction"

  # X3 — Error case: Elasticsearch did not answer
  Scenario: A non-JSON answer from Elasticsearch is not mistaken for stats
    When the Elasticsearch JVM stats are "curl: (7) Failed to connect to localhost port 9200"
    Then there are no Elasticsearch JVM stats

  # H4 — Happy path: the limits survive a reboot because the start script reads them
  Scenario: The start script takes its limits from the per-box file and keeps the index in a volume
    When I read the data box start script
    Then the data box start script sources "/etc/default/irm-data-containers"
    And the data box start script starts Elasticsearch with "--restart unless-stopped", "--memory=\"$ES_MEMORY\"" and "-v elasticsearch-data:/usr/share/elasticsearch/data"
    And the data box start script starts Redis with "--maxmemory $REDIS_MAXMEMORY --maxmemory-policy noeviction"
    And the start script's floor values are the rule's floor

  # X4 — Error case (decision 2026-11-09): only the data box environments
  Scenario Outline: Only known environments may be changed
    When the data box limits task is asked for "<env>"
    Then the data box limits task is "<allowed>"

    Examples:
      | env           | allowed |
      | staging.in    | allowed |
      | production.in | allowed |
      | development   | refused |
