require 'aws-sdk-s3'

namespace :s3 do
  desc 'Check if the latest file in the source bucket is present in the destination bucket'
  task :check_latest_file do
    S3CheckJob.perform_now
  end

  # Manual/DR-verification entry point for the hourly cron job (see
  # config/initializers/sidekiq.rb). Run after a restore or region setup to
  # confirm the backup chain is alive before walking away.
  desc 'Alert if DB backups (xtrabackup buckets, primary + replica) are stale'
  task check_backup_freshness: :environment do
    DbBackupFreshnessJob.perform_now
  end
end