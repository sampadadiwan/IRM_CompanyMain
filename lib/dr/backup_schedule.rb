# frozen_string_literal: true

module Dr
  # The single source of truth, on the Ruby side, for "how does a DB server take backups, and is
  # that safe?" - used by the DR restore (lib/tasks/backup_db.rake), the early clean-up in
  # AwsUtils#setup_infra and dr:verify (lib/tasks/dr_verify.rake).
  #
  # The rules it encodes:
  # - A backup CHAIN (one full + the incrementals built on it) in S3 may have exactly ONE writer.
  #   A second writer produces incrementals based on the wrong data, and a later restore silently
  #   rebuilds the wrong database.
  # - The only sanctioned writer is /usr/local/bin/db_backup_xtra.sh, run by the cron SCHEDULE
  #   below and gated by the ARMED MARKER, which only a successful primary restore creates.
  # - Any backup job in a user or root crontab is an OLD job from before that design (the live
  #   boxes still back up via `/home/ubuntu/backup_db.sh`). Old jobs ignore the armed marker, and
  #   DR servers are cloned from a snapshot of the live box, so they arrive on every DR primary
  #   AND replica. They must be stripped there.
  #
  # Pure: no SSH, no AWS. Callers fetch the text and act on the answers.
  module BackupSchedule
    # Where the backup script, its schedule, its log rotation and the armed marker live on a DB
    # server - identical to the paths the Packer recipe bakes.
    SCRIPT_PATH = "/usr/local/bin/db_backup_xtra.sh"
    CRON_PATH = "/etc/cron.d/irm-db-backup"
    LOGROTATE_PATH = "/etc/logrotate.d/irm-db-backup"
    ARMED_MARKER = "/etc/db_backup_enabled"

    # The schedule, line for line as config/deploy/templates/packer/db_redis_es.ami.pkr.hcl bakes
    # it (features/misc/dr_backup_schedule.feature H4 fails if the two drift apart). PATH is
    # explicit because the script's aws CLI lives in /usr/local/bin, outside cron's default PATH.
    CRON_LINES = [
      "SHELL=/bin/bash",
      "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
      "0 23 * * *      root /usr/local/bin/db_backup_xtra.sh full >> /var/log/db_backup.log 2>&1",
      "0,30 0-22 * * * root /usr/local/bin/db_backup_xtra.sh incr >> /var/log/db_backup.log 2>&1"
    ].freeze
    CRON_CONTENT = "#{CRON_LINES.join("\n")}\n".freeze

    # Keeps /var/log/db_backup.log bounded, as the Packer recipe does.
    LOGROTATE_LINES = [
      "/var/log/db_backup.log {",
      "  weekly",
      "  rotate 8",
      "  compress",
      "  missingok",
      "  notifempty",
      "}"
    ].freeze
    LOGROTATE_CONTENT = "#{LOGROTATE_LINES.join("\n")}\n".freeze

    # A crontab line that runs any backup script that has ever written the chain from a crontab:
    # backup_db.sh (live boxes), backup_db.old.sh (its predecessor), db_backup_xtra*.sh (a copy
    # someone scheduled by hand). The sanctioned schedule lives in CRON_PATH, never in a crontab,
    # so every match in a crontab is an old, unguarded writer.
    OLD_JOB_PATTERN = /(?:\bbackup_db(?:\.[\w-]+)?\.sh|\bdb_backup_xtra[\w.-]*\.sh)\b/

    # A baked script resolves its config at run time and still carries its placeholders; a
    # generated one (xtrabackup:generate_backup_script) has them substituted with real values.
    BAKED_PLACEHOLDER = "__BUCKET__"

    # A verdict for dr:verify: status is :ok, :warn or :fail; detail is the operator-facing text.
    Grade = Data.define(:status, :detail)

    module_function

    # Splits `crontab -l` output into the lines to keep and the old backup jobs to remove.
    # Returns { kept: [...], removed: [...] } with lines unchanged (no trailing newline).
    def split_crontab(text)
      # `crontab -l` for a user with none prints "no crontab for <user>" - that is not a line
      lines = text.to_s.lines.map(&:chomp).grep_v(/\Ano crontab for /)
      # Only ACTIVE lines can run: a blank line or a comment is kept, whatever it mentions
      removed, kept = lines.partition { |line| active?(line) && line.match?(OLD_JOB_PATTERN) }
      { kept: kept, removed: removed }
    end

    # The old backup jobs in `crontab -l` output - what dr:verify grades on.
    def old_jobs(text)
      split_crontab(text)[:removed]
    end

    # Is the primary's backup schedule safe? schedule: CRON_PATH exists on the box;
    # old_jobs: active old backup lines across its ubuntu + root crontabs.
    def grade_primary(schedule:, old_jobs:)
      # X2 — both the baked schedule and an old job write the chain: two writers
      if schedule && old_jobs.any?
        Grade.new(:fail, "two backup writers: #{CRON_PATH} AND an old unguarded job (#{old_jobs.first}) — strip the old job")
      # H2 — the sanctioned schedule and nothing else
      elsif schedule
        Grade.new(:ok, "#{CRON_PATH} present, no old backup job")
      # E5 — today's live boxes: the old job is the only writer. Not broken, but not marker-gated.
      elsif old_jobs.any?
        Grade.new(:warn, "backups run only from an old unguarded job that ignores the armed marker (#{old_jobs.first}) — migrate to #{CRON_PATH}")
      # X1 — armed or not, nothing will ever run the backup script
      else
        Grade.new(:fail, "no #{CRON_PATH} and no other backup job — no backups will run")
      end
    end

    # Is the replica free of writers? It must never write the chain, and old jobs ignore the
    # armed marker, so any old job here is a second writer.
    def grade_replica(old_jobs:)
      # X3 — a cloned old job on the replica
      return Grade.new(:fail, "replica must never write the backup chain, but has an old unguarded job (#{old_jobs.first})") if old_jobs.any?

      # H3 — the baked schedule may be present; without the marker it skips every run
      Grade.new(:ok, "no backup job outside the marker-gated schedule")
    end

    # Is the primary armed - correctly for this kind of run?
    # Real recovery: it MUST be (without the marker the schedule skips every run).
    # Drill: it must NOT be. The live box is still alive and writing the same bucket, so an armed
    # drill primary would be a second writer on the live chain.
    def grade_armed(armed, drill: false)
      if drill
        # X5 — a drill primary armed is a second writer on the LIVE chain
        return Grade.new(:fail, "drill primary is ARMED — it would write into the live backup chain beside the live box") if armed

        # E7 — the drill proves the schedule is installed; arming is left to a real recovery
        return Grade.new(:ok, "drill: deliberately not armed — the live box still owns the backup chain")
      end
      # X4 — same wording dr:verify has always used for this check
      return Grade.new(:fail, "marker missing — no backups will be taken!") unless armed

      Grade.new(:ok, "#{ARMED_MARKER} present")
    end

    # Is this run a DR drill? aws:dr_drill sets DR_DRILL=true for its setup_infra run, and the
    # cap recovery tasks forward it to the rake tasks they run on the app servers.
    def drill?(env = ENV)
      env["DR_DRILL"] == "true"
    end

    # Is this script text (or its head) the baked, secret-free copy?
    def baked_script?(text)
      text.to_s.include?(BAKED_PLACEHOLDER)
    end

    # A line cron would act on: not blank, not a comment.
    def active?(line)
      stripped = line.strip
      !stripped.empty? && !stripped.start_with?("#")
    end
  end
end
