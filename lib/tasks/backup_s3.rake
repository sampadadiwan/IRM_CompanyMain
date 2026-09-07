require 'aws-sdk-s3'
require 'dotenv'

namespace :s3 do
  desc 'Check if the latest file in the source bucket is present in the destination bucket'
  task :check_latest_file, [:env_name] do |_t, args|
    # env_name is what makes this usable from a laptop. Without it the job (and
    # the AWS_S3_* bucket vars) resolve to the default credentials/.env, i.e.
    # a different account than the one being verified.
    if args[:env_name]
      Rake::Task['aws:environment'].reenable
      Rake::Task['aws:environment'].invoke(args[:env_name])
    end
    S3CheckJob.perform_now(env_name: args[:env_name])
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

  # The morning-report counterpart to :check_backup_freshness, driven by
  # bin/check_db_backup_freshness's `daily` mode. Same buckets, same job — but
  # it prints what actually happened in the last 24h (did the nightly FULL
  # land? how big? any hole in the incremental chain?) instead of only a
  # pass/fail verdict, then appends the verdict at the end.
  #
  # Both halves run in ONE :environment boot on purpose: booting Rails twice
  # per region would quadruple a cron run that already takes ~15s per boot.
  #
  #   rake "s3:backup_daily_report[production.in]"
  desc 'Print a 24h DB backup report (nightly full, chain gaps) + pass/fail verdict'
  task :backup_daily_report, [:env_name] => :environment do |_t, args|
    if args[:env_name]
      env_file = ".env.#{args[:env_name]}"
      raise "Environment file not found: #{env_file}" unless File.exist?(env_file)

      Dotenv.overload(env_file)
    end

    job = DbBackupFreshnessJob.new
    label = args[:env_name] || Rails.env

    puts "=== #{label}: DB backups, last #{(DbBackupFreshnessJob::REPORT_WINDOW / 1.hour).to_i}h " \
         "(now #{Time.current.utc.strftime('%Y-%m-%d %H:%M')} UTC) ==="

    # The SUMMARY| lines printed at the end are what bin/check_db_backup_freshness
    # builds its notification from — parsing one stable delimited line is far
    # less brittle than re-parsing the human-readable report above, which is
    # free to change layout whenever it reads better.
    summaries = []
    histories = []

    # Adaptive units, not a fixed "GB": the US database is currently well under
    # a gigabyte, and rounding it to "0.0 GB" would hide the single number most
    # worth watching — a full backup that suddenly shrinks.
    human_size = lambda do |bytes|
      if bytes >= 1024**3 then "#{(bytes / (1024.0**3)).round(2)} GB"
      elsif bytes >= 1024**2 then "#{(bytes / (1024.0**2)).round(1)} MB"
      else "#{(bytes / 1024.0).round(1)} KB"
      end
    end
    max_gap = DbBackupFreshnessJob::MAX_EXPECTED_GAP_MINUTES

    job.collect_report(env_name: args[:env_name]).each do |r|
      puts "\n#{r[:label]} — s3://#{r[:bucket]} (#{r[:region]})"

      if r[:error]
        puts "  ! cannot list bucket: #{r[:error]}"
        summaries << [r[:label], '', '', 'n/a', 0, '', 'UNREADABLE']
        next
      end

      full = r[:newest_full]
      size = full ? human_size.call(full[:bytes]) : nil
      if full
        puts "  last FULL     #{full[:time].strftime('%Y-%m-%d %H:%M')} UTC  (#{full[:age_h]}h ago)  #{size}"
      else
        puts "  last FULL     none found"
      end

      if (any = r[:newest_any])
        puts "  last backup   #{any[:time].strftime('%Y-%m-%d %H:%M')} UTC  (#{any[:age_h]}h ago)  #{any[:kind]}"
      end

      counts = r[:counts]
      puts "  in window     #{counts.fetch('full', 0)} full + #{counts.fetch('incr', 0)} incr"
      hist = r[:full_history]
      puts "  full history  #{hist.size} nightly fulls on record, oldest #{hist.first[:time].strftime('%Y-%m-%d')}" if hist.any?

      gap = r[:largest_gap_minutes]
      if gap.nil?
        puts "  chain         too few backups in window to assess"
      elsif gap > max_gap
        # Worth eyeballing: the nightly 23:00->00:00 hole is expected and sits
        # under the threshold, so anything above it is a genuinely missed slot.
        puts "  chain         GAP of #{gap} min (expected <= #{max_gap})"
      else
        puts "  chain         unbroken (largest gap #{gap} min)"
      end

      status = if full.nil?
                 'NO FULL'
               elsif gap && gap > max_gap
                 "GAP #{gap}m"
               else
                 'ok'
               end
      summaries << [r[:label], full ? full[:age_h] : '', full ? full[:bytes] : '', size || 'n/a', counts.fetch('incr', 0), gap || '', status]
      histories << { label: r[:label],
                     points: r[:full_history].map { |h| "#{h[:time].strftime('%Y-%m-%d')}:#{h[:bytes]}" }.join(',') }
    end

    # HISTORY| carries the real nightly-full trend read out of the bucket, as
    # date:bytes pairs — the dashboard does not have to accumulate it.
    histories.each { |h| puts "HISTORY|#{label}|#{h[:label]}|#{h[:points]}" }

    # Field order: env | bucket | full_age_h | full_bytes | full_size | incr | gap_min | status
    summaries.each { |s| puts "SUMMARY|#{label}|#{s.join('|')}" }
    puts "\n--- verdict ---"
    DbBackupFreshnessJob.perform_now(env_name: args[:env_name])
  end
end
