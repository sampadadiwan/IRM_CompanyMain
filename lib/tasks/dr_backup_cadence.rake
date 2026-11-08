# frozen_string_literal: true

# Puts a LIVE database server's incremental backups on a 30-minute cadence, so the recovery point
# we promise clients (30 minutes, security questionnaire H3) is met (openspec
# fix-backup-rpo-and-size-checks).
#
# Staging's live DB server ran incrementals hourly (`0 0-22 * * * … backup_db.sh incr`), so a
# recovery could lose up to 59 minutes. Production already runs every 30 minutes. This changes
# ONE crontab line on the staging server, and nothing else.
#
#   rake "dr:set_backup_cadence[staging.in]"              # dry run: shows the change, touches nothing
#   EXECUTE=1 rake "dr:set_backup_cadence[staging.in]"    # applies it
#
# Guards: staging only (decision 2026-11-08); the AWS keys must belong to that environment's
# account; refuses within 5 minutes of a :00/:30 run or while a backup runs; saves the old
# crontab on the server first; re-reads afterwards to prove the change; prints the rollback.
require "active_support/encrypted_configuration"

namespace :dr do
  # No :environment: like the aws:* tasks, this runs from the operator's machine against AWS and
  # SSH, and must not need a database connection (the Dr modules come from dr_requires.rb).
  desc "Put the staging live DB server's backups on a 30-minute cadence (dry run; EXECUTE=1 applies)"
  task :set_backup_cadence, [:env_name] do |_t, args| # rubocop:disable Rails/RakeEnvironment
    env_name = args[:env_name].to_s
    unless Dr::BackupSchedule.cadence_env_allowed?(env_name)
      abort "❌ Refusing #{env_name.presence || '(no env)'}: only #{Dr::BackupSchedule::CADENCE_ENVS.join(', ')} " \
            "may be changed (production already backs up every 30 minutes). Nothing touched."
    end
    execute = ENV["EXECUTE"] == "1"

    # 1. The keys in use must belong to this environment's AWS account
    Rake::Task["aws:environment"].invoke(env_name)
    expected = DR_ASSESS_ENVIRONMENTS.fetch(env_name)[:account]
    actual = Aws::STS::Client.new.get_caller_identity.account
    abort "❌ AWS account #{actual} is not #{env_name}'s (#{expected}). Nothing touched." unless actual == expected
    puts "✅ AWS account #{actual} (#{env_name})"

    # 2. Where the live DB server is: DB_HOST from the env's credentials; reached through the
    #    first app server in its deploy file (DB servers accept SSH only from app servers)
    stack, variant = env_name.split(".")
    creds = ActiveSupport::EncryptedConfiguration.new(
      config_path: Rails.root.join("config/credentials/#{env_name}.yml.enc"),
      key_path: Rails.root.join("config/credentials/#{env_name}.key"),
      env_key: "RAILS_MASTER_KEY_UNUSED", raise_if_missing_key: true
    )
    db_host = creds.config[:DB_HOST].to_s
    deploy_file = Rails.root.join("config/deploy/#{stack}_#{variant}.rb").read
    app_ip = deploy_file.scan(Dr::DrillTeardown::SERVER_LINE).flatten.first.to_s
    abort "❌ Could not resolve the DB host (#{db_host.inspect}) or an app server (#{app_ip.inspect})." if db_host.empty? || app_ip.empty?

    dr_db_ssh(app_ip, db_host, dr_ssh_keys(stack, variant)) do |ssh|
      puts "🔌 #{db_host} (via #{app_ip}): #{ssh.exec!('hostname').to_s.strip}"
      # 3. The plan: only the hourly incremental line changes
      current = ssh.exec!("crontab -l 2>&1").to_s
      plan = Dr::BackupSchedule.thirty_minute_cadence(current)
      case plan[:status]
      when :unchanged
        next puts "✅ Already every 30 minutes — nothing to do."
      when :refused
        abort "❌ #{plan[:reason]}. Crontab left as it is:\n#{current}"
      end
      puts "   before: #{plan[:before]}"
      puts "   after:  #{plan[:after]}"
      next puts "ℹ️  Dry run — nothing changed. Re-run with EXECUTE=1 to apply." unless execute

      # 4. Never race a backup: not within 5 minutes of :00/:30, and not while one runs
      minute = Time.now.utc.min % 30
      abort "❌ Too close to a :00/:30 backup run (minute #{Time.now.utc.min}). Retry between :05–:25 or :35–:55." if minute < 5 || minute >= 25
      running = ssh.exec!("pgrep -af 'backup_db.sh|db_backup_xtra.sh' | grep -v pgrep || true").to_s.strip
      abort "❌ A backup is running right now:\n#{running}\nRetry in a few minutes." unless running.empty?

      # 5. Save the current crontab on the server, then write the new one (base64: quotes intact)
      saved = "~/crontab.before-30min.#{Time.now.utc.strftime('%Y%m%d%H%M%S')}"
      ssh.exec!("crontab -l > #{saved}")
      written = ssh.exec!("echo #{Base64.strict_encode64(plan[:text])} | base64 -d | crontab - && echo OK").to_s
      abort "❌ Writing the crontab failed: #{written.strip}. Saved copy: #{saved}" unless written.include?("OK")

      # 6. Prove it: re-read and check the 30-minute line is there
      after = ssh.exec!("crontab -l 2>&1").to_s
      verdict = Dr::BackupSchedule.thirty_minute_cadence(after)
      abort "❌ Re-read does not show the 30-minute line. Roll back with: crontab #{saved}" unless verdict[:status] == :unchanged

      puts "✅ Verified: incrementals now run at :00 and :30 on #{db_host}."
      puts "   Rollback (on the DB server): crontab #{saved}"
      puts "   Check tomorrow: rake \"s3:backup_daily_report[#{env_name}]\" should show 46 incrementals."
    end
  end
end
