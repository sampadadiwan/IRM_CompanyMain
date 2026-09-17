# Binary log retention for the production primaries. Each app server's own
# Rails connection already points at its region's DB_HOST (the primary) — no
# SSH/SSM/AMI plumbing needed, unlike the cross-region replication setup in
# aws_utils.rb (reset_replication), which genuinely needs its own explicit
# Mysql2::Client to reach a SECOND server.
#
# Scheduled weekly from config/schedule.rb (roles: [:primary]), which renders
# the same crontab content on every stage (staging + production, both
# regions) — Rails.env.production? here is what actually scopes this to
# production, same idiom as website_leads:purge running daily everywhere but
# only doing something where WebsiteLead rows exist to expire.
namespace :db do
  desc "Purge binary log files older than DB_BINLOG_RETENTION_DAYS (default 14) — production only"
  task purge_binlogs: :environment do
    unless Rails.env.production?
      puts "db:purge_binlogs — not production (#{Rails.env}), skipping"
      next
    end

    retention_days = ENV.fetch("DB_BINLOG_RETENTION_DAYS", "14").to_i
    cutoff = retention_days.days.ago

    # BEFORE a cutoff, not TO a filename: MySQL's own purge leaves alone (with
    # a warning) any file still being read by a connected replica's dump
    # thread rather than purging it out from under an active replica. That
    # only protects a replica that's actually connected — one down longer
    # than the retention window still needs a resync after reconnecting
    # (rake aws_utils:reset_replication), same tradeoff as MySQL's own
    # binlog_expire_logs_seconds.
    quoted_cutoff = ActiveRecord::Base.connection.quote(cutoff.strftime("%Y-%m-%d %H:%M:%S"))
    ActiveRecord::Base.connection.execute("PURGE BINARY LOGS BEFORE #{quoted_cutoff}")

    message = "db:purge_binlogs — purged binary logs before #{cutoff} (retention: #{retention_days}d)"
    Rails.logger.info message
    puts message
  end
end
