# Watches the xtrabackup S3 buckets and alerts when database backups go stale.
#
# Why this exists: every part of the backup chain can fail silently — the cron
# on the DB server stops, the armed-marker is missing after a rebuild, an SSM
# parameter is rotated wrong, an IAM/bucket policy changes, or cross-region
# replication breaks. Restores are only as good as the newest backup, so
# staleness must page someone instead of being discovered mid-incident.
#
# What it checks (schedule: nightly full at 23:00 + incrementals every 30 min,
# see /etc/cron.d/irm-db-backup baked into the DB AMI):
#   1. PRIMARY backup bucket:  newest backup of any kind within INCR_MAX_AGE,
#      newest FULL backup within FULL_MAX_AGE.
#   2. REPLICA backup bucket:  same checks with REPLICA_LAG grace added —
#      catches broken cross-region replication (Point 6) even when the
#      primary-side backups are healthy.
#
# Object layout: xbcloud stores each backup under a top-level prefix named
# "<%F_%H%M%S>-full/" or "<%F_%H%M%S>-incr/" (see db_backup_xtra.sh FULL_NAME/
# INCR_NAME). We list only those prefixes (delimiter "/") instead of every
# object — one prefix per backup keeps the listing cheap even after months.
class DbBackupFreshnessJob < ApplicationJob
  # Nightly full at 23:00 + up to ~2h for the backup itself + grace ⇒ 26h.
  FULL_MAX_AGE = 26.hours
  # Incrementals run every 30 min; 2h tolerates a slow run + one missed slot
  # without false alarms.
  INCR_MAX_AGE = 2.hours
  # Extra allowance for S3 cross-region replication on the replica bucket.
  REPLICA_LAG = 1.hour

  # How many nightly FULLs the report sizes for its trend. The buckets hold far
  # more (435 fulls back to mid-2025 in IN production), but each one costs a
  # listing to size — ~0.12s — so 30 keeps the daily run a few seconds while
  # still showing a month of history the very first time it runs.
  FULL_HISTORY_COUNT = 30
  # How far back the morning report (#collect_report) looks.
  REPORT_WINDOW = 24.hours
  # The backup cron baked into the DB AMI (/etc/cron.d/irm-db-backup) runs the
  # FULL at 23:00 UTC and incrementals at :00/:30 for hours 0-22 only. That
  # leaves one EXPECTED 60-minute hole every night, between the 23:00 full and
  # the 00:00 incremental, so only a hole longer than this counts as a gap —
  # at 60 the report would cry wolf every single morning.
  MAX_EXPECTED_GAP_MINUTES = 90

  # Matches the timestamp format the backup script bakes into prefix names.
  TIMESTAMP_FORMAT = "%Y-%m-%d_%H%M%S".freeze
  PREFIX_RE = /\A(\d{4}-\d{2}-\d{2}_\d{6})-(full|incr)\/\z/

  # env_name (e.g. production.in / production.us): lets this run locally against a
  # specific prod deployment's AWS account. Rails.application.credentials only
  # resolves to the right region's AWS keys on the deployed server (Capistrano
  # symlinks config/credentials/production.yml.enc to the regional file there);
  # locally, passing env_name reads that regional .yml.enc directly instead
  # (see #credentials below).
  def perform(env_name: nil)
    failures = collect_failures(env_name: env_name)

    if failures.any?
      msg = "DB backup freshness check FAILED: #{failures.join(' | ')}"
      log(:error, msg)
      # Same alert channel S3CheckJob uses — lands wherever exception
      # notifications are delivered (email/Slack per environment config).
      ExceptionNotifier.notify_exception(StandardError.new(msg), data: { failures: failures })
    else
      log(:info, "✓ DB backup freshness check passed (primary + replica buckets).")
    end
  end

  # Runs all freshness checks and returns the failure strings (empty = healthy).
  # Public so `rake aws:dr_readiness` can reuse the EXACT same checks as the
  # hourly alert and report them in its scorecard instead of alerting.
  def collect_failures(env_name: nil)
    @env_name = env_name
    bucket_specs.flat_map { |spec| check_bucket(**spec) }
  end

  # The "what actually happened overnight" counterpart to #collect_failures.
  # Deliberately separate: #collect_failures answers "should this page someone
  # RIGHT NOW" and is what the hourly cron runs; this one never alerts — it
  # describes the last 24h so a human reading the morning report can watch the
  # nightly FULL land, instead of only being told that nothing is wrong.
  # Returns one hash per bucket; see #report_for_bucket for the shape.
  def collect_report(env_name: nil)
    @env_name = env_name
    bucket_specs.map { |spec| report_for_bucket(**spec.except(:grace)) }
  end

  private

  # The two buckets every check and every report covers, in order. Extracted
  # so #collect_failures and #collect_report can never drift apart about which
  # bucket — or which override — they are looking at.
  def bucket_specs
    [
      {
        bucket: "#{ENV.fetch('AWS_S3_BUCKET')}-backup-xtra",
        region: ENV.fetch('AWS_S3_REGION'),
        label: "primary",
        grace: 0.seconds
      },
      {
        # By convention the replica backup bucket is "#{AWS_S3_BUCKET_REPLICA}-backup-xtra"
        # (what rake aws:provision_s3_buckets creates). Some environments deviate —
        # e.g. IN production's replica was created manually as
        # "docs.caphive.com.production-backup-xtra-ap-south2" — so the FULL bucket
        # name can be overridden via AWS_S3_BUCKET_REPLICA_XTRA in the env.
        bucket: ENV.fetch('AWS_S3_BUCKET_REPLICA_XTRA', "#{ENV.fetch('AWS_S3_BUCKET_REPLICA')}-backup-xtra"),
        region: ENV.fetch('AWS_S3_REPLICA_REGION', ENV.fetch('AWS_S3_REGION')),
        label: "replica (cross-region copy)",
        grace: REPLICA_LAG
      }
    ]
  end

  # Every check/status line goes to both Rails.logger (the persisted record —
  # what the cron's log aggregation and ExceptionNotifier data rely on) and
  # stdout (so a local `rake s3:check_backup_freshness[...]` run shows progress
  # in the terminal instead of only landing in log/<env>.log).
  def log(level, msg)
    Rails.logger.public_send(level, msg)
    puts msg # rubocop:disable Rails/Output -- deliberate: visible when run interactively via rake, not just in logs
  end

  # env_name-aware credentials source — see the comment on #perform.
  def credentials
    @credentials ||= if @env_name
                       key_path = Rails.root.join("config", "credentials", "#{@env_name}.key")
                       raise "Key file not found for environment '#{@env_name}' at #{key_path}" unless File.exist?(key_path)

                       Rails.application.encrypted(
                         Rails.root.join("config", "credentials", "#{@env_name}.yml.enc"),
                         key_path: key_path
                       )
                     else
                       Rails.application.credentials
                     end
  end

  # Returns a list of human-readable failure strings for one bucket (empty when healthy).
  def check_bucket(bucket:, region:, label:, grace:)
    log(:info, "→ Checking #{label} bucket s3://#{bucket} (#{region})...")

    client = s3_client(region)

    latest_full, latest_any = newest_backup_times(client, bucket)

    # No parseable backup prefixes at all — brand-new bucket or wrong bucket
    # name; either way there is nothing to restore from.
    if latest_any.nil?
      failure = "#{label}: no backups found in s3://#{bucket}"
      log(:error, "  ✗ #{failure}")
      return [failure]
    end

    failures = []
    if latest_any < (INCR_MAX_AGE + grace).ago
      failures << "#{label}: newest backup in s3://#{bucket} is #{time_ago(latest_any)} old (limit #{((INCR_MAX_AGE + grace) / 1.hour.to_f).round(1)}h) — is the DB backup cron armed and running?"
    end
    if latest_full.nil?
      failures << "#{label}: no FULL backup found in s3://#{bucket} — incrementals alone cannot be restored"
    elsif latest_full < (FULL_MAX_AGE + grace).ago
      failures << "#{label}: newest FULL backup in s3://#{bucket} is #{time_ago(latest_full)} old (limit #{((FULL_MAX_AGE + grace) / 1.hour.to_f).round(1)}h)"
    end

    if failures.empty?
      log(:info, "  ✓ #{label}: newest backup #{time_ago(latest_any)} old, newest FULL #{time_ago(latest_full)} old")
    else
      failures.each { |f| log(:error, "  ✗ #{f}") }
    end
    failures
  rescue Aws::S3::Errors::ServiceError => e
    # Being unable to see the backups is itself an alertable condition —
    # a restore attempt would hit the same wall.
    failure = "#{label}: cannot list s3://#{bucket} (#{e.class}: #{e.message})"
    log(:error, "  ✗ #{failure}")
    [failure]
  end

  def s3_client(region)
    Aws::S3::Client.new(
      access_key_id: credentials[:AWS_ACCESS_KEY_ID],
      secret_access_key: credentials[:AWS_SECRET_ACCESS_KEY],
      region: region
    )
  end

  # Every parseable backup prefix in the bucket, as [time, kind, prefix].
  # One listing with delimiter "/" — one entry per backup rather than per
  # object — so this stays cheap even at 180-day retention (~47 backups/day).
  def all_backups(client, bucket)
    backups = []
    continuation = nil
    loop do
      resp = client.list_objects_v2(bucket: bucket, delimiter: "/", continuation_token: continuation)
      resp.common_prefixes.each do |cp|
        next unless (m = cp.prefix.match(PREFIX_RE))

        # The DB server writes timestamps in its own clock (UTC on the Ubuntu
        # AMIs); parse as UTC — thresholds are generous enough to absorb drift.
        backups << [Time.find_zone!("UTC").strptime(m[1], TIMESTAMP_FORMAT), m[2], cp.prefix]
      end
      break unless resp.is_truncated

      continuation = resp.next_continuation_token
    end
    backups
  end

  # [newest_full_time, newest_backup_time_of_any_kind], nils when absent.
  def newest_backup_times(client, bucket)
    backups = all_backups(client, bucket)
    [backups.select { |_t, kind, _p| kind == "full" }.map(&:first).max, backups.map(&:first).max]
  end

  # One bucket's last-24h picture, for the morning report. Never raises: a
  # bucket that cannot be listed becomes an :error row rather than blowing up
  # the whole report — turning that into an actual alert is #check_bucket's
  # job, and the hourly cron already does it.
  def report_for_bucket(bucket:, region:, label:)
    client = s3_client(region)
    backups = all_backups(client, bucket)
    window = backups.select { |time, _k, _p| time >= REPORT_WINDOW.ago }.sort_by(&:first)
    newest_any = window.last

    # Size the last FULL_HISTORY_COUNT fulls in one pass and reuse the newest
    # of them below, rather than sizing the newest a second time on its own.
    sized_fulls = backups.select { |_t, kind, _p| kind == "full" }
                         .sort_by(&:first)
                         .last(FULL_HISTORY_COUNT)
                         .map { |time, _k, prefix| { time: time, bytes: prefix_size(client, bucket, prefix) } }
    newest_full = sized_fulls.last

    {
      label: label, bucket: bucket, region: region, error: nil,
      newest_full: newest_full && {
        time: newest_full[:time], age_h: age_hours(newest_full[:time]),
        # Sized deliberately: a FULL that exists but is a fraction of its usual
        # size is the classic "backup started, died halfway" signature, and a
        # freshness-only check reports that as perfectly healthy.
        bytes: newest_full[:bytes]
      },
      # Read straight from the bucket, not accumulated day by day: every
      # nightly full is already sitting there under its own timestamped
      # prefix, so a month of trend is available the first time this runs.
      full_history: sized_fulls,
      newest_any: newest_any && { time: newest_any[0], kind: newest_any[1], age_h: age_hours(newest_any[0]) },
      counts: window.group_by { |_t, kind, _p| kind }.transform_values(&:size),
      largest_gap_minutes: largest_gap_minutes(window)
    }
  rescue Aws::S3::Errors::ServiceError => e
    { label: label, bucket: bucket, region: region, error: "#{e.class}: #{e.message}" }
  end

  # Total bytes across every object under one backup prefix.
  def prefix_size(client, bucket, prefix)
    bytes = 0
    continuation = nil
    loop do
      resp = client.list_objects_v2(bucket: bucket, prefix: prefix, continuation_token: continuation)
      bytes += resp.contents.sum(&:size)
      break unless resp.is_truncated

      continuation = resp.next_continuation_token
    end
    bytes
  end

  # Largest interval between consecutive backups in the window, in minutes;
  # nil when there are fewer than two backups to compare.
  def largest_gap_minutes(sorted)
    return nil if sorted.size < 2

    sorted.each_cons(2).map { |a, b| ((b[0] - a[0]) / 60).round }.max
  end

  def age_hours(time)
    ((Time.current - time) / 1.hour).round(1)
  end

  def time_ago(time)
    "#{age_hours(time)}h"
  end
end
