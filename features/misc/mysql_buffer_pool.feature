@rack_test
Feature: MySQL's buffer pool is sized from what the DB box has left
  Every DB box ran MySQL's default 128 MB buffer pool - on prod IN 0.5% of a 26 GB dataset, with up
  to 3.7% of reads going to disk. Once Elasticsearch and Redis were capped, the data box had ~3.5 GB
  free. rake "ops:mysql_buffer_pool[<env>]" grows the pool online with SET PERSIST, by one rule:
  room = RAM - other services' caps - 1.25 x mysqld's non-pool memory - 1.5 GB for the OS, and
  pool = min(room, 1.25 x dataset), in whole resize units, never shrinking.

  These scenarios exercise the pure decisions (lib/mysql_buffer_pool.rb) - they touch no box.

  # H1 — Happy path: staging's probe (2026-11-09) - the dataset cap decides
  Scenario: A small dataset caps the pool below the room the box has
    Given a DB box with 7840 MB RAM, 2048 MB reserved for other services and mysqld resident at 1056 MB
    And its buffer pool is 128 MB in 128 MB units with a 1040 MB dataset
    When the buffer pool is planned
    Then the buffer pool plan is "grow" to 1408 MB
    And the room is 3096 MB

  # H2 — Happy path: prod IN's shape - a 26 GB dataset, so the room decides
  Scenario: A large dataset gets all the room the box has, in whole units
    Given a DB box with 7840 MB RAM, 2048 MB reserved for other services and mysqld resident at 1100 MB
    And its buffer pool is 128 MB in 128 MB units with a 26004 MB dataset
    When the buffer pool is planned
    Then the buffer pool plan is "grow" to 2944 MB

  # E1 — Edge case: a re-run after growing finds nothing to do
  Scenario: A pool already at the target is left alone
    Given a DB box with 7840 MB RAM, 2048 MB reserved for other services and mysqld resident at 2336 MB
    And its buffer pool is 1408 MB in 128 MB units with a 1040 MB dataset
    When the buffer pool is planned
    Then the buffer pool plan is "unchanged"

  # X1 — Error case: a box already past its budget never grows (the OOM killer picks mysqld)
  Scenario: A box without room is refused
    Given a DB box with 3000 MB RAM, 2048 MB reserved for other services and mysqld resident at 1056 MB
    And its buffer pool is 128 MB in 128 MB units with a 26004 MB dataset
    When the buffer pool is planned
    Then the buffer pool plan is "refused" mentioning "no room"

  # X2 — Error case: an uncapped service makes the budget fiction
  Scenario Outline: A box with a service whose memory is not capped is refused
    When the memory reserved for "<containers>" with an Elasticsearch cap of <es_cap> MB and Redis maxmemory of <redis_max> MB is worked out
    Then the reservation is refused mentioning "<text>"

    Examples:
      | containers                       | es_cap | redis_max | text                 |
      | elasticsearch,redis-stack-server | 0      | 512       | elasticsearch has no |
      | elasticsearch,redis-stack-server | 1536   | 0         | Redis has no         |
      | grafana                          | 0      | 0         | unknown container    |

  # E2 — Edge case: capped services, and a replica box with none
  Scenario Outline: Capped services reserve exactly their caps
    When the memory reserved for "<containers>" with an Elasticsearch cap of <es_cap> MB and Redis maxmemory of <redis_max> MB is worked out
    Then <reserved> MB is reserved

    Examples:
      | containers                       | es_cap | redis_max | reserved |
      | elasticsearch,redis-stack-server | 1536   | 512       | 2048     |
      |                                  | 0      | 0         | 0        |

  # E3 — Edge case (security): a password with option-file specials is read whole
  Scenario: The client option file quotes the password
    When the client option file is written for a password with a hash, a semicolon, a space, a double quote and a backslash
    Then reading the option file back gives the same password

  # X3 — Error case (decision 2026-11-09): only the DB environments
  Scenario Outline: Only known environments may be changed
    When the buffer pool task is asked for "<env>"
    Then the buffer pool task is "<allowed>"

    Examples:
      | env           | allowed |
      | staging.in    | allowed |
      | production.us | allowed |
      | development   | refused |
