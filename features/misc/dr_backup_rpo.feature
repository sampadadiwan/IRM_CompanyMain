@rack_test
Feature: Backups keep the 30-minute recovery-point promise and are checked for size
  We promise clients a recovery point of 30 minutes, so incrementals must run at least every
  30 minutes; staging ran them hourly. And a backup that lands empty or truncated used to pass
  as healthy because only its age was checked. Staging moves to :00/:30 through a guarded rake
  task (staging only), and the nightly full is now compared with the usual size.

  # H1 — Happy path: staging's live crontab, verbatim from the 2026-11-08 probe
  Scenario: The hourly incremental becomes every 30 minutes and nothing else changes
    Given a live backup crontab:
      """
      @reboot /bin/bash -l -c 'sudo docker run -d --rm --name elasticsearch -p 9200:9200 elasticsearch:8.19.0'
      0 23 * * * /home/ubuntu/backup_db.sh full >> /tmp/mysql_backup_full.log 2>&1
      0 0-22 * * * /home/ubuntu/backup_db.sh incr >> /tmp/mysql_backup_incr.log 2>&1
      """
    When it is moved to a 30-minute cadence
    Then the cadence change is "changed"
    And the incremental line reads "0,30 0-22 * * * /home/ubuntu/backup_db.sh incr >> /tmp/mysql_backup_incr.log 2>&1"
    And every other line is unchanged

  # E1 — Edge case: running it twice changes nothing the second time
  Scenario: A crontab already on 30 minutes is left alone
    Given a live backup crontab:
      """
      0,30 0-22 * * * /home/ubuntu/backup_db.sh incr >> /tmp/mysql_backup_incr.log 2>&1
      """
    When it is moved to a 30-minute cadence
    Then the cadence change is "unchanged"

  # X2 — Error case: anything unexpected is refused, never guessed at
  Scenario: A crontab without the hourly incremental line is refused
    Given a live backup crontab:
      """
      0 23 * * * /home/ubuntu/backup_db.sh full
      """
    When it is moved to a 30-minute cadence
    Then the cadence change is "refused"

  # X1 — Error case (decision 2026-11-08): staging only
  Scenario Outline: Only staging's cadence may be changed by the task
    When the cadence task is asked for "<env>"
    Then it is "<allowed>"

    Examples:
      | env           | allowed |
      | staging.in    | allowed |
      | production.in | refused |
      | production.us | refused |

  # H2 — Happy path: today's real staging sizes
  Scenario: A normal nightly full passes the size check
    When a full of 138078727 bytes is size-checked against 138156453, 138165902 and 138165103
    Then the size grade is "ok"

  # E2 — Edge case: not enough history to judge
  Scenario: With fewer than three earlier fulls the size is not judged
    When a full of 1000 bytes is size-checked against 138156453 and 138165902
    Then the size grade is "ok" mentioning "not enough history"

  # E3 — Edge case: noticeably small, but maybe genuine (a big purge) - warn, don't page
  Scenario: A full at 65% of the usual size is a warning
    When a full of 90000000 bytes is size-checked against 138156453, 138165902 and 138165103
    Then the size grade is "warn" mentioning "65%"

  # X3 — Error case: the blind spot - a truncated full used to pass as healthy
  Scenario: A truncated full fails the size check
    When a full of 2000000 bytes is size-checked against 138156453, 138165902 and 138165103
    Then the size grade is "fail" mentioning "truncated or empty"

  # X4 — Error case
  Scenario: An empty full fails the size check
    When a full of 0 bytes is size-checked against 138156453, 138165902 and 138165103
    Then the size grade is "fail" mentioning "truncated or empty"
