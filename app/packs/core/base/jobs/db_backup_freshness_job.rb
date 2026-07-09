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

  # Matches the timestamp format the backup script bakes into prefix names.
  TIMESTAMP_FORMAT = "%Y-%m-%d_%H%M%S".freeze
  PREFIX_RE = /\A(\d{4}-\d{2}-\d{2}_\d{6})-(full|incr)\/\z/

  def perform
    failures = collect_failures

    if failures.any?
      msg = "DB backup freshness check FAILED: #{failures.join(' | ')}"
      Rails.logger.error msg
      # Same alert channel S3CheckJob uses — lands wherever exception
      # notifications are delivered (email/Slack per environment config).
      ExceptionNotifier.notify_exception(StandardError.new(msg), data: { failures: failures })
    else
      Rails.logger.info "✓ DB backup freshness check passed (primary + replica buckets)."
    end
  end

  # Runs all freshness checks and returns the failure strings (empty = healthy).
  # Public so `rake aws:dr_readiness` can reuse the EXACT same checks as the
  # hourly alert and report them in its scorecard instead of alerting.
  def collect_failures
    failures = []
    failures += check_bucket(
      bucket: "#{ENV.fetch('AWS_S3_BUCKET')}-backup-xtra",
      region: ENV.fetch('AWS_S3_REGION'),
      label: "primary",
      grace: 0.seconds
    )
    failures += check_bucket(
      bucket: "#{ENV.fetch('AWS_S3_BUCKET_REPLICA')}-backup-xtra",
      region: ENV.fetch('AWS_S3_REPLICA_REGION', ENV.fetch('AWS_S3_REGION')),
      label: "replica (cross-region copy)",
      grace: REPLICA_LAG
    )
    failures
  end

  private

  # Returns a list of human-readable failure strings for one bucket (empty when healthy).
  def check_bucket(bucket:, region:, label:, grace:)
    client = Aws::S3::Client.new(
      access_key_id: Rails.application.credentials[:AWS_ACCESS_KEY_ID],
      secret_access_key: Rails.application.credentials[:AWS_SECRET_ACCESS_KEY],
      region: region
    )

    latest_full, latest_any = newest_backup_times(client, bucket)

    # No parseable backup prefixes at all — brand-new bucket or wrong bucket
    # name; either way there is nothing to restore from.
    return ["#{label}: no backups found in s3://#{bucket}"] if latest_any.nil?

    failures = []
    if latest_any < (INCR_MAX_AGE + grace).ago
      failures << "#{label}: newest backup in s3://#{bucket} is #{time_ago(latest_any)} old (limit #{((INCR_MAX_AGE + grace) / 1.hour.to_f).round(1)}h) — is the DB backup cron armed and running?"
    end
    if latest_full.nil?
      failures << "#{label}: no FULL backup found in s3://#{bucket} — incrementals alone cannot be restored"
    elsif latest_full < (FULL_MAX_AGE + grace).ago
      failures << "#{label}: newest FULL backup in s3://#{bucket} is #{time_ago(latest_full)} old (limit #{((FULL_MAX_AGE + grace) / 1.hour.to_f).round(1)}h)"
    end
    failures
  rescue Aws::S3::Errors::ServiceError => e
    # Being unable to see the backups is itself an alertable condition —
    # a restore attempt would hit the same wall.
    ["#{label}: cannot list s3://#{bucket} (#{e.class}: #{e.message})"]
  end

  # Scans only the top-level prefixes (one per backup) and returns
  # [newest_full_time, newest_backup_time_of_any_kind], nils when absent.
  def newest_backup_times(client, bucket)
    latest_full = nil
    latest_any = nil
    continuation = nil
    loop do
      resp = client.list_objects_v2(bucket: bucket, delimiter: "/", continuation_token: continuation)
      resp.common_prefixes.each do |cp|
        next unless (m = cp.prefix.match(PREFIX_RE))

        # The DB server writes timestamps in its own clock (UTC on the Ubuntu
        # AMIs); parse as UTC — thresholds are generous enough to absorb drift.
        time = Time.find_zone!("UTC").strptime(m[1], TIMESTAMP_FORMAT)
        latest_any = time if latest_any.nil? || time > latest_any
        latest_full = time if m[2] == "full" && (latest_full.nil? || time > latest_full)
      end
      break unless resp.is_truncated

      continuation = resp.next_continuation_token
    end
    [latest_full, latest_any]
  end

  def time_ago(time)
    hours = ((Time.current - time) / 1.hour).round(1)
    "#{hours}h"
  end
end
