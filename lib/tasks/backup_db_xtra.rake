# lib/tasks/xtrabackup.rake

require 'aws-sdk-s3'
require 'fileutils'

namespace :xtrabackup do
  module Helpers
    extend self

    def config(key, env_var)
      Rails.application.credentials.dig(*key) || ENV[env_var] || raise("Missing config for #{key.join('.')}")
    end

    def aws_region
      config(["AWS_S3_REGION"], "AWS_S3_REGION")
    end

    def s3_client
      @s3_client ||= Aws::S3::Client.new(
        access_key_id: aws_access_key_id,
        secret_access_key: aws_secret_access_key,
        region: aws_region
      )
    end

    def s3_resource
      @s3_resource ||= Aws::S3::Resource.new(client: s3_client)
    end

    def ensure_s3_bucket_exists
      bucket_name = s3_bucket
      bucket = s3_resource.buckets.find { |b| b.name == bucket_name }

      if bucket
        puts "S3 bucket #{bucket_name} already exists."
      else
        puts "Creating S3 bucket: #{bucket_name}"
        s3_resource.create_bucket({
                                    acl: "private",
                                    bucket: bucket_name,
                                    create_bucket_configuration: {
                                      location_constraint: aws_region
                                    }
                                  })
        puts "S3 bucket #{bucket_name} created successfully."
      end
    rescue StandardError => e
      abort("Failed to ensure S3 bucket exists: #{e.message}")
    end

    def mysql_user
      config(["DB_USER"], "DB_USER")
    end

    def mysql_password
      config(["DB_PASS"], "DB_PASS")
    end

    def aws_access_key_id
      config(["AWS_ACCESS_KEY_ID"], "AWS_ACCESS_KEY_ID")
    end

    def aws_secret_access_key
      config(["AWS_SECRET_ACCESS_KEY"], "AWS_SECRET_ACCESS_KEY")
    end

    def s3_bucket
      config(["AWS_S3_BUCKET"], "AWS_S3_BUCKET") + ".db-backup-xbcloud"
    end

    def xtrabackup_bin
      # config([:backups, :xtrabackup_bin], "XTRABACKUP_BIN")
      "xtrabackup"
    end

    def xbcloud_bin
      # config([:backups, :xbcloud_bin], "XBCLOUD_BIN")
      "xbcloud"
    end

    def backup_target_dir
      "/tmp/backup/full_#{Time.now.strftime('%Y-%m-%d_%H-%M-%S')}"
    end
  end

  desc "Run the xtrabackup script with environment variables set from Rails credentials and .env"
  task generate_backup_script: :environment do
    # Path to the original and temporary script
    original_script_path = Rails.root.join("lib/tasks/db_backup_xtra.sh")
    temp_script_path = Rails.root.join('tmp', "db_backup_xtra_#{Rails.env}.sh")
    puts "Generating backup script from #{original_script_path} to #{temp_script_path}"

    # Read the original script content
    script_content = File.read(original_script_path)

    # Replace placeholders with credentials
    script_content.gsub!('__BUCKET__', ENV.fetch("AWS_S3_BUCKET", nil) + "-backup-xtra")
    script_content.gsub!('__AWS_REGION__', ENV["AWS_S3_REGION"].to_s)
    script_content.gsub!('__AWS_ACCESS_KEY_ID__', Rails.application.credentials.dig("AWS_ACCESS_KEY_ID").to_s)
    script_content.gsub!('__AWS_SECRET_ACCESS_KEY__', Rails.application.credentials.dig("AWS_SECRET_ACCESS_KEY").to_s)
    script_content.gsub!('__MYSQL_PASSWORD__', Rails.application.credentials.dig("DB_PASS").to_s)
    script_content.gsub!('__MYSQL_USER__', Rails.application.credentials.dig("DB_USER").to_s)
    # Database name from CONFIG, not from a live connection: during DR this
    # runs BEFORE the restore, against a virgin MySQL with no database yet —
    # `connection.current_database` raised NoDatabaseError there (found on the
    # first truly-fresh-AMI drill, 2026-07-10; earlier runs were masked by an
    # empty IRM_<env> that pre-SKIP_MIGRATE deploys had accidentally created).
    script_content.gsub!('__DATABASE_NAME__', ActiveRecord::Base.connection_db_config.database)

    # Write the modified content to a temporary script
    File.write(temp_script_path, script_content)
    FileUtils.chmod(0o755, temp_script_path)

    puts "Temporary script created at #{temp_script_path}"

    # Execute the temporary script
    # puts "Executing temporary script: #{temp_script_path} #{command}"
    # system("#{temp_script_path} #{command}")

    # # Clean up the temporary script
    # FileUtils.rm(temp_script_path)
  end

  desc "Prepare AWS ENV vars"
  task :setup_env do
    ENV["AWS_ACCESS_KEY_ID"]     = Helpers.aws_access_key_id
    ENV["AWS_SECRET_ACCESS_KEY"] = Helpers.aws_secret_access_key
    ENV["AWS_REGION"]            = Helpers.aws_region
  end

  # Seeds the SSM parameters the baked backup script reads at runtime (see
  # db_backup_xtra.sh + db_redis_es.ami.pkr.hcl). SSM parameters are REGIONAL:
  # run once per region that hosts DB instances — including the DR region, so
  # a recovered DB server finds its config without any manual seeding mid-DR.
  # Idempotent: --overwrite updates values in place (rotation = re-run).
  # ex: rake "xtrabackup:seed_ssm_params[production.in, ap-south-1]"
  #     rake "xtrabackup:seed_ssm_params[production.in, ap-south-2]"   # DR region
  desc "Seed SSM Parameter Store with DB backup config for baked AMIs (run per region)"
  task :seed_ssm_params, [:env_name, :region] => :environment do |t, args|
    require 'open3'

    env_name = args[:env_name] or raise "env_name required, e.g. production.in"
    region   = args[:region] || ENV["AWS_REGION"] or raise "region required, e.g. ap-south-1"

    # Load the env-specific .env + AWS SDK credentials (same mechanism as the
    # other aws:* tasks use)
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(env_name)

    # Decrypt the env-specific credentials pair (e.g. production.in.yml.enc) —
    # Rails.application.credentials would be the *current* RAILS_ENV's, which is
    # not necessarily the environment we are seeding for.
    creds = Rails.application.encrypted(
      Rails.root.join("config", "credentials", "#{env_name}.yml.enc"),
      key_path: Rails.root.join("config", "credentials", "#{env_name}.key")
    )

    rails_env = env_name.split(".").first # production.in -> production
    prefix = "/irm/#{rails_env}/db_backup"

    params = {
      "mysql_user"    => creds[:DB_USER] || ENV.fetch("DB_USER"),
      "mysql_password" => creds[:DB_PASS] || ENV.fetch("DB_PASS"),
      # Same bucket naming as generate_backup_script (line ~97): <bucket>-backup-xtra
      "bucket"        => "#{ENV.fetch('AWS_S3_BUCKET')}-backup-xtra",
      # Region of the BUCKET (stays fixed in DR) — not the instance's region
      "bucket_region" => ENV.fetch("AWS_S3_REGION"),
      "database_name" => "IRM_#{rails_env}"
    }

    params.each do |key, value|
      raise "Empty value for #{prefix}/#{key} — check credentials/.env for #{env_name}" if value.to_s.empty?

      # Argument-array form: the secret never passes through a shell
      _out, err, status = Open3.capture3(
        "aws", "ssm", "put-parameter",
        "--name", "#{prefix}/#{key}",
        "--value", value.to_s,
        "--type", "SecureString",
        "--overwrite",
        "--region", region
      )
      raise "Failed to seed #{prefix}/#{key} in #{region}: #{err}" unless status.success?

      puts "✅ Seeded #{prefix}/#{key} (#{region})" # value deliberately not printed
    end

    puts "🎉 SSM backup config seeded for #{env_name} in #{region}."
  end

  # Retention cleanup for the xtrabackup S3 buckets, runnable by hand or from
  # cron. Belt-and-braces alongside the lifecycle rules that
  # rake aws:provision_s3_buckets applies — ensure_lifecycle! there is
  # deliberately "never clobbers", so a bucket that already carried ANY
  # lifecycle config never received the retention rule, which is exactly how
  # snapshots pile up unbounded.
  #
  # Chain-safety: each incremental is CUMULATIVE against the last full backup
  # (incr_backup in db_backup_xtra.sh reads its starting LSN from $LSNDIR,
  # which only full_backup writes; restore_latest_chain applies only the
  # newest incr). A restore chain is therefore "one full + any one incr taken
  # after it". We pick the oldest full we intend to KEEP and delete every
  # backup prefix that sorts lexically before it — nothing a kept full depends
  # on is ever removed, and no incr is ever orphaned from its base full.
  #
  # The buckets are versioned (required for replication), so a plain delete
  # would only add delete markers and the bytes would keep billing as
  # noncurrent versions. This task deletes SPECIFIC VERSION IDS (and delete
  # markers), which removes the data permanently and immediately.
  #
  # DRY RUN by default — set CONFIRM=1 to actually delete.
  #   rake "xtrabackup:cleanup_old_backups[production.in]"              # report only
  #   CONFIRM=1 rake "xtrabackup:cleanup_old_backups[production.in]"    # delete
  # Tunables (env vars):
  #   DB_BACKUP_RETENTION_DAYS  keep fulls newer than this (default 120, same
  #                             default as the lifecycle rule in aws.rake)
  #   DB_BACKUP_MIN_KEEP_FULLS  always keep at least this many fulls even if
  #                             they exceed retention (default 60 — fulls are
  #                             nightly, so ≈ the last 60 days of restore points)
  #   SKIP_REPLICA=1            clean only the primary-region bucket. Deletes
  #                             do NOT replicate (delete_marker_replication is
  #                             disabled by design), so by default the replica
  #                             bucket is cleaned with the same policy.
  desc "Delete xtrabackup S3 backups older than the retention window (dry run unless CONFIRM=1)"
  task :cleanup_old_backups, [:env_name] => :environment do |t, args|
    require "aws-sdk-s3"

    env_name = args[:env_name] or raise "env_name required, e.g. production.in"
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(env_name)

    retention_days = ENV.fetch("DB_BACKUP_RETENTION_DAYS", "120").to_i
    min_keep_fulls = ENV.fetch("DB_BACKUP_MIN_KEEP_FULLS", "60").to_i
    execute        = ENV["CONFIRM"] == "1"
    raise "DB_BACKUP_RETENTION_DAYS must be positive" unless retention_days.positive?
    raise "DB_BACKUP_MIN_KEEP_FULLS must be at least 1" unless min_keep_fulls >= 1

    # Same bucket naming/region resolution as aws:provision_s3_buckets — the
    # two tasks must always target the same buckets.
    source_region = ENV.fetch("AWS_S3_REGION")
    targets = [
      { bucket: "#{ENV.fetch('AWS_S3_BUCKET')}-backup-xtra", region: source_region }
    ]
    unless ENV["SKIP_REPLICA"] == "1"
      replica_bucket = ENV.fetch("AWS_S3_BUCKET_REPLICA_XTRA",
                                 "#{ENV.fetch('AWS_S3_BUCKET_REPLICA', ENV.fetch('AWS_S3_BUCKET'))}-backup-xtra")
      replica_region = ENV.fetch("AWS_S3_REPLICA_REGION", source_region)
      # Staging sets replica == source; don't clean the same bucket twice
      targets << { bucket: replica_bucket, region: replica_region } unless replica_bucket == targets.first[:bucket]
    end

    # A backup prefix looks like "2026-08-31_230000-full/" or "..._-incr/"
    # (TIMESTAMP from `date +%F_%H%M%S` in db_backup_xtra.sh). Lexical order ==
    # chronological order for this zero-padded format.
    backup_prefix_re = /\A(\d{4}-\d{2}-\d{2}_\d{6})-(full|incr)\/\z/
    cutoff_time = Time.now - (retention_days * 86_400)

    targets.each do |target|
      client = Aws::S3::Client.new(region: target[:region])
      puts "\n📦 Bucket: #{target[:bucket]} (#{target[:region]})"

      # Enumerate top-level backup prefixes (one per full/incr snapshot)
      prefixes = []
      client.list_objects_v2(bucket: target[:bucket], delimiter: "/").each do |page|
        prefixes.concat(page.common_prefixes.map(&:prefix))
      end

      known = prefixes.select { |p| p.match?(backup_prefix_re) }.sort
      (prefixes - known).each { |p| puts "  ⚠️  Skipping unrecognized prefix (left untouched): #{p}" }

      fulls = known.select { |p| p.end_with?("-full/") }
      if fulls.empty?
        puts "  ⚠️  No full backups found — nothing deleted (refusing to touch a bucket with no restorable chain)."
        next
      end

      # Fulls to keep: everything inside the retention window, but never fewer
      # than min_keep_fulls (protects a bucket where backups stopped running —
      # old snapshots are all we have, so age alone must not delete the last ones).
      kept_fulls = fulls.select do |p|
        Time.strptime(p[backup_prefix_re, 1], "%Y-%m-%d_%H%M%S") >= cutoff_time
      end
      kept_fulls = fulls.last(min_keep_fulls) if kept_fulls.size < min_keep_fulls

      # Everything strictly before the oldest kept full goes; incrs after it
      # belong to a kept chain and stay.
      oldest_kept = kept_fulls.first
      deletable = known.select { |p| p < oldest_kept }

      # Show what survives and WHY, so a dry run reads as a full audit: every
      # kept full is listed with its keep reason; kept incrs are summarized by
      # count (48/day × 120d ≈ thousands — listing each would drown the report).
      kept_incrs = known.count { |p| p.end_with?("-incr/") && p >= oldest_kept }
      puts "  Keeping #{kept_fulls.size} of #{fulls.size} full(s) + #{kept_incrs} incremental(s) after the oldest kept full:"
      kept_fulls.each do |p|
        within_retention = Time.strptime(p[backup_prefix_re, 1], "%Y-%m-%d_%H%M%S") >= cutoff_time
        reason = within_retention ? "within #{retention_days}d retention" : "min-keep floor (newest #{min_keep_fulls} fulls)"
        puts "    ✔ #{p.chomp('/')}  (#{reason})"
      end
      if deletable.empty?
        puts "  ✅ Nothing older than the kept chain — no cleanup needed."
        next
      end
      puts "  #{execute ? 'Deleting' : 'Would delete'} #{deletable.size} snapshot prefix(es):"

      total_bytes = 0
      total_objects = 0
      deletable.each do |prefix|
        # Collect every version + delete marker under the prefix so the bytes
        # are actually freed (versioned bucket — see header comment).
        versions = []
        prefix_bytes = 0
        client.list_object_versions(bucket: target[:bucket], prefix: prefix).each do |page|
          page.versions.each do |v|
            versions << { key: v.key, version_id: v.version_id }
            prefix_bytes += v.size.to_i
          end
          page.delete_markers.each { |m| versions << { key: m.key, version_id: m.version_id } }
        end
        total_bytes += prefix_bytes
        total_objects += versions.size

        # Two distinct delete reasons: plain age, or an incr/full stranded
        # before the oldest kept full — its base full is gone, so it cannot be
        # restored regardless of age. Label each so the report is self-explaining.
        aged_out = Time.strptime(prefix[backup_prefix_re, 1], "%Y-%m-%d_%H%M%S") < cutoff_time
        reason = aged_out ? "older than #{retention_days}d" : "orphaned — predates oldest kept full, base full missing"
        puts format("    %s %-32s %10.2f GB in %d object versions  (%s)",
                    execute ? "🗑" : "•", prefix.chomp("/"), prefix_bytes / 1024.0**3, versions.size, reason)
        next unless execute

        # delete_objects caps at 1000 keys per request
        versions.each_slice(1000) do |batch|
          resp = client.delete_objects(bucket: target[:bucket],
                                       delete: { objects: batch, quiet: true })
          # quiet mode returns only failures — surface them instead of moving on
          resp.errors.each { |e| puts "      ❌ #{e.key} (#{e.version_id}): #{e.code} #{e.message}" }
          raise "Aborting: #{resp.errors.size} delete failures in #{prefix}" if resp.errors.any?
        end
      end

      verb = execute ? "Deleted" : "Would delete"
      puts format("  %s %s %.2f GB across %d object versions.", execute ? "✅" : "🔍", verb.downcase, total_bytes / 1024.0**3, total_objects)
      puts "  ℹ️  Dry run — re-run with CONFIRM=1 to delete." unless execute
    end
  end
end
