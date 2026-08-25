require 'aws-sdk-s3'
require 'dotenv'

namespace :s3 do
  desc 'Check if the latest file in the source bucket is present in the destination bucket'
  task :check_latest_file do
    S3CheckJob.perform_now
  end

  # Manual/DR-verification entry point for the hourly cron job (see
  # config/initializers/sidekiq.rb). Run after a restore or region setup to
  # confirm the backup chain is alive before walking away.
  #
  # Pass env_name to run this locally against a specific prod deployment
  # instead of whatever .env.<Rails.env> loaded at boot — it both overloads
  # bucket/region ENV vars from that .env file AND routes DbBackupFreshnessJob's
  # AWS credentials to config/credentials/<env_name>.yml.enc directly, since
  # Rails.application.credentials only resolves to the right account on the
  # deployed server (where it's symlinked to the regional file). No AWS key
  # export needed — IN and US prod are separate AWS accounts, but each has its
  # own credentials file checked into this repo:
  #
  #   rake "s3:check_backup_freshness[production.in]"
  #   rake "s3:check_backup_freshness[production.us]"
  desc 'Alert if DB backups (xtrabackup buckets, primary + replica) are stale'
  task :check_backup_freshness, [:env_name] => :environment do |_t, args|
    if args[:env_name]
      env_file = ".env.#{args[:env_name]}"
      raise "Environment file not found: #{env_file}" unless File.exist?(env_file)

      Dotenv.overload(env_file)
      puts "✅ Overloaded environment variables from #{env_file}"
    end

    DbBackupFreshnessJob.perform_now(env_name: args[:env_name])
  end
end