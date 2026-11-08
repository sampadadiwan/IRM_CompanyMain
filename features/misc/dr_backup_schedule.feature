@rack_test
Feature: A recovered database keeps exactly one backup writer, on the baked schedule
  MySQL backups form a chain in S3 - a nightly full plus incrementals built on it - and only one
  server may ever write to a chain. Every DB server image carries the backup script and its cron
  schedule (/etc/cron.d/irm-db-backup); the armed marker (/etc/db_backup_enabled) decides which
  server may act, and only a successful primary restore creates it.

  DR database servers are cloned from a weekly snapshot of the LIVE box, which predates that
  design: it backs up through an old ubuntu crontab job (/home/ubuntu/backup_db.sh) that ignores
  the armed marker and has the live bucket hard-coded. A DR restore therefore strips those old
  jobs, installs the baked schedule, and dr:verify fails any server that would take no backups
  or that has a second writer.

  These scenarios exercise Dr::BackupSchedule, the logic the restore and verify tasks call. The
  SSH and AWS paths around it are proven by the staging DR drill (see the qa-checklist of
  openspec/changes/fix-dr-backup-cron-after-restore).

  # H1 — Happy path: the staging live box's crontab, verbatim from the 2026-11-08 probe
  Scenario: Old backup jobs are stripped from a cloned crontab and the docker start-up lines are kept
    Given a DB server crontab:
      """
      @reboot /bin/bash -l -c 'sudo docker run -d --rm --name elasticsearch -p 9200:9200 -p 9300:9300 -e "discovery.type=single-node" -e "xpack.security.enabled=false" elasticsearch:8.19.0'
      @reboot /bin/bash -l -c 'sudo docker run -d --rm --name redis-stack-server -p 6379:6379  redis/redis-stack-server:latest'
      0 23 * * * /home/ubuntu/backup_db.sh full >> /tmp/mysql_backup_full.log 2>&1
      0 0-22 * * * /home/ubuntu/backup_db.sh incr >> /tmp/mysql_backup_incr.log 2>&1
      """
    When the old backup jobs are stripped from that crontab
    Then 2 crontab lines are kept
    And 2 old backup jobs are removed
    And no kept crontab line runs a backup script

  # H2 — Happy path
  Scenario: A DR primary with the baked schedule and no old job is healthy
    When a DR primary's backups are graded with the schedule "present" and old jobs "absent"
    Then the backup grade is "ok"

  # H3 — Happy path
  Scenario: A DR replica with no old job is healthy
    When a DR replica's backups are graded with old jobs "absent"
    Then the backup grade is "ok"

  # H4 — Happy path: drift guard between the restore and the Packer bake
  Scenario: The schedule a restore installs is the one the Packer recipe bakes
    When I read the backup schedule and log rotation baked by the Packer recipe
    Then they match the schedule and log rotation a DR restore installs

  # E1 — Edge case: nothing to strip, so the crontab must be left exactly as it was
  Scenario: A crontab with no old backup jobs is left unchanged
    Given a DB server crontab:
      """
      @reboot /bin/bash -l -c 'sudo docker run -d --rm --name redis-stack-server -p 6379:6379  redis/redis-stack-server:latest'
      """
    When the old backup jobs are stripped from that crontab
    Then 1 crontab lines are kept
    And 0 old backup jobs are removed

  # E2 — Edge case: `crontab -l` on a user with no crontab prints this to stderr
  Scenario: A user with no crontab yields nothing to keep and nothing to strip
    Given a DB server crontab:
      """
      no crontab for ubuntu
      """
    When the old backup jobs are stripped from that crontab
    Then 0 crontab lines are kept
    And 0 old backup jobs are removed

  # E3 — Edge case: a commented-out job never runs, so it is left alone
  Scenario: A commented-out old backup job is kept
    Given a DB server crontab:
      """
      # 0 * * * * /home/ubuntu/backup_db.sh incr
      """
    When the old backup jobs are stripped from that crontab
    Then 1 crontab lines are kept
    And 0 old backup jobs are removed

  # E4 — Edge case: every script name that has ever written the chain from a crontab
  Scenario: Every old backup script variant is stripped
    Given a DB server crontab:
      """
      0 * * * * /home/ubuntu/backup_db.sh incr
      30 * * * * /home/ubuntu/backup_db.old.sh incr
      0 23 * * * /home/ubuntu/db_backup_xtra.sh full
      """
    When the old backup jobs are stripped from that crontab
    Then 0 crontab lines are kept
    And 3 old backup jobs are removed

  # E5 — Edge case: today's live primary - the old job is its only writer, so warn, don't fail
  Scenario: A primary backed up only by the old job is warned about, not failed
    When a DR primary's backups are graded with the schedule "absent" and old jobs "present"
    Then the backup grade is "warn" mentioning "old unguarded job"

  # E6 — Edge case: baked copies still carry their placeholders; generated copies do not
  Scenario Outline: The backup script on a server is classified as baked or generated
    When the backup script line "<line>" is classified
    Then the backup script is classified as "<kind>"

    Examples:
      | line                                            | kind      |
      | BUCKET='__BUCKET__'                             | baked     |
      | BUCKET='docs.altx.com.staging-backup-xtra'      | generated |

  # X1 — Error case: armed, but nothing will ever run the script (the 2026-11-08 drill)
  Scenario: An armed primary with no schedule fails verification
    When a DR primary's backups are graded with the schedule "absent" and old jobs "absent"
    Then the backup grade is "fail" mentioning "no backups will run"

  # X2 — Error case: the baked schedule AND the cloned old job both write the chain
  Scenario: A primary with two backup writers fails verification
    When a DR primary's backups are graded with the schedule "present" and old jobs "present"
    Then the backup grade is "fail" mentioning "two backup writers"

  # X3 — Error case: the cloned old job ignores the marker, so the replica writes the chain
  Scenario: A replica with an old backup job fails verification
    When a DR replica's backups are graded with old jobs "present"
    Then the backup grade is "fail" mentioning "replica must never write"

  # X4 — Error case: no armed marker means the baked schedule skips every run
  Scenario: A primary without the armed marker fails verification
    When a DR primary's armed marker is graded as "absent"
    Then the backup grade is "fail" mentioning "marker missing"

  # E7 — Edge case: a drill restores and schedules, but leaves the live box as the only writer
  Scenario: A drill primary that is not armed passes verification
    When a DR drill primary's armed marker is graded as "absent"
    Then the backup grade is "ok" mentioning "deliberately not armed"

  # X5 — Error case: an armed drill primary is a second writer on the LIVE chain
  Scenario: A drill primary that is armed fails verification
    When a DR drill primary's armed marker is graded as "present"
    Then the backup grade is "fail" mentioning "would write into the live backup chain"

  # E8 — Edge case: only an explicit DR_DRILL=true makes a run a drill
  Scenario Outline: A run is a drill only when DR_DRILL is "true"
    When the drill flag is read from DR_DRILL "<value>"
    Then the run is treated as a drill: "<drill>"

    Examples:
      | value | drill |
      | true  | yes   |
      | false | no    |
      |       | no    |
