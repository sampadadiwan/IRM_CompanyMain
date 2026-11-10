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

  # X4 — Error case (prod IN, 2026-11-10): a re-run straight after a grow. The new pool is mostly
  #      untouched, so mysqld's resident memory (1572 MB) is below the 2432 MB pool. Measured as
  #      rss - configured pool this floored to 0 and grew the pool again to 4224 MB; measured as
  #      rss - the 136 MB in use it is 1436 MB, and the pool is left alone.
  Scenario: A pool grown minutes ago is not grown again
    Given a DB box with 7840 MB RAM, 2048 MB reserved for other services and mysqld resident at 1572 MB
    And its buffer pool is 2432 MB in 128 MB units with a 25996 MB dataset
    And only 136 MB of the pool is in use
    When the buffer pool is planned
    Then the buffer pool plan is "unchanged"
    And the room is 2461 MB

  # E6 — Edge case: the part of the pool in use, from the probe's page counts
  Scenario Outline: The pool in use comes from its pages
    When the pool in use is worked out from "<total>" pages in total, "<free>" free and a "<size>" byte page
    Then <in_use> MB of the pool is in use

    Examples:
      | total  | free   | size  | in_use |
      | 155648 | 146944 | 16384 | 136    |
      | 8192   | 0      | 16384 | 128    |
      |        |        |       | 0      |

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

  # H3 — Happy path (prod IN, 2026-11-10): the idle replica's own room (3328 MB) is capped to the
  #      primary's 2432 MB - after a failover it carries the primary's load
  # E4 — Edge case (prod US): within the primary's pool, the replica's own plan stands
  # E5 — Edge case: the primary's pool is no bigger than the replica's today - left alone, never shrunk
  Scenario Outline: A replica never gets a bigger pool than the primary
    Given a DB box with 7840 MB RAM, <reserved> MB reserved for other services and mysqld resident at <rss> MB
    And its buffer pool is <pool> MB in 128 MB units with a <dataset> MB dataset
    When the buffer pool is planned
    And the plan is capped at a primary pool of <primary> MB
    Then the buffer pool plan is "<status>" to <target> MB

    Examples:
      | reserved | rss | pool | dataset | primary | status    | target |
      | 2048     | 858 | 128  | 25836   | 2432    | grow      | 2432   |
      | 0        | 759 | 128  | 300     | 384     | grow      | 384    |
      | 2048     | 858 | 1024 | 25836   | 512     | unchanged | 1024   |

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
