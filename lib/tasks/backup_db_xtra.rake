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
  # after it". We keep every full inside the retention window PLUS the newest
  # full at-or-before the cutoff (the retention window almost never opens
  # exactly at a full, so that straddling full is the base of the oldest
  # in-window incrementals — deleting it would orphan them). We then delete
  # only prefixes that BOTH sort lexically before that oldest kept full AND
  # are past the retention window — nothing a kept full depends on is ever
  # removed, no retained incr loses its base, and nothing newer than
  # retention_days is ever deleted (age is a hard floor). Net effect:
  # retention is "at least N days", reaching up to one full-interval further back.
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
  #   DB_BACKUP_RETENTION_DAYS  keep fulls newer than this (default 180, same
  #                             default as the lifecycle rule in aws.rake)
  #   DB_BACKUP_MIN_KEEP_FULLS  always keep at least this many fulls even if
  #                             they exceed retention (default 60 — fulls are
  #                             nightly, so ≈ the last 60 days of restore points)
  #   VERBOSE=1                 itemize kept fulls and (in dry run) each
  #                             deletable prefix; default output is stats-only
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

    retention_days = ENV.fetch("DB_BACKUP_RETENTION_DAYS", "180").to_i
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
      # AWS_S3_BUCKET_REPLICA is REQUIRED here (same loud KeyError as
      # provisioning): a silent fallback would let a missing/typo'd env var
      # quietly skip the replica bucket, which — since deletes and lifecycle
      # actions never replicate — would then grow unbounded with green output.
      # Envs without a replica must say so explicitly via SKIP_REPLICA=1.
      replica_bucket = ENV.fetch("AWS_S3_BUCKET_REPLICA_XTRA") { "#{ENV.fetch('AWS_S3_BUCKET_REPLICA')}-backup-xtra" }
      replica_region = ENV.fetch("AWS_S3_REPLICA_REGION", source_region)
      if replica_bucket == targets.first[:bucket]
        # Staging sets replica == source — one bucket; announce rather than silently dedup
        puts "ℹ️  Replica bucket equals the source bucket — cleaning a single bucket."
      else
        targets << { bucket: replica_bucket, region: replica_region }
      end
    end

    # A backup prefix looks like "2026-08-31_230000-full/" or "...-incr/" —
    # TIMESTAMP is `date +%F_%H%M%S` run IN UTC on the DB hosts (same parsing
    # concern DbBackupFreshnessJob handles with an explicit UTC zone). The
    # cutoff is therefore computed in UTC and compared LEXICALLY: zero-padded
    # timestamps sort chronologically, so string compares are exact, immune to
    # the rake host's timezone (the app TZ is IST — Time.strptime here would
    # judge every snapshot ~5.5h older than it is, firing permanent deletes
    # early), and cannot crash on a calendar-invalid junk name.
    backup_prefix_re = /\A(\d{4}-\d{2}-\d{2}_\d{6})-(full|incr)\/\z/
    cutoff_key = (Time.now.utc - (retention_days * 86_400)).strftime("%Y-%m-%d_%H%M%S")

    failures = []
    targets.each do |target|
      client = Aws::S3::Client.new(region: target[:region])
      puts "\n📦 Bucket: #{target[:bucket]} (#{target[:region]})"

      # The S3 lifecycle rule is the OTHER retention enforcer and acts
      # server-side regardless of what this task decides. ensure_lifecycle! in
      # aws.rake never overwrites an existing config, so a bucket provisioned
      # under the old 90d default still expires backups at 90d — 30 days
      # short of the retention promised here. Detect and shout (read-only).
      begin
        lc_rules = client.get_bucket_lifecycle_configuration(bucket: target[:bucket]).rules
        min_expiry = lc_rules.select { |r| r.status == "Enabled" }.filter_map { |r| r.expiration&.days }.min
        if min_expiry && min_expiry < retention_days
          puts "  🚨 Bucket lifecycle expires backups after #{min_expiry}d — SHORTER than the #{retention_days}d retained here."
          puts "     S3 keeps deleting at #{min_expiry}d until the rule is updated (aws:provision_s3_buckets never overwrites existing rules)."
        end
      rescue Aws::S3::Errors::NoSuchLifecycleConfiguration
        puts "  ℹ️  No lifecycle configuration on this bucket — this task is the only retention enforcement."
      end

      # Enumerate top-level backup prefixes (one per full/incr snapshot).
      # list_object_versions rather than list_objects_v2: on a versioned
      # bucket the latter sees only CURRENT versions, so a prefix whose
      # objects were already expired/deleted (delete marker current) would be
      # invisible — exactly the noncurrent bytes this task exists to reclaim.
      prefixes = []
      client.list_object_versions(bucket: target[:bucket], delimiter: "/").each do |page|
        prefixes.concat(page.common_prefixes.map(&:prefix))
      end
      prefixes.uniq!

      known = prefixes.select { |p| p.match?(backup_prefix_re) }.sort
      (prefixes - known).each { |p| puts "  ⚠️  Skipping unrecognized prefix (left untouched): #{p}" }

      fulls = known.select { |p| p.end_with?("-full/") }
      if fulls.empty?
        puts "  ⚠️  No full backups found — nothing deleted (refusing to touch a bucket with no restorable chain)."
        next
      end

      # Fulls to keep: everything inside the retention window PLUS the newest
      # full at-or-before the cutoff — the "straddle" full. The oldest
      # in-window incrementals are based on it (the window almost never opens
      # exactly at a full), so deleting it would orphan restore points inside
      # the advertised retention. Never fewer than min_keep_fulls total
      # (protects a bucket where backups stopped running — old snapshots are
      # all we have, so age alone must not delete the last ones).
      in_window_fulls = fulls.select { |p| p[backup_prefix_re, 1] >= cutoff_key }
      straddle_full   = fulls.select { |p| p[backup_prefix_re, 1] < cutoff_key }.last
      kept_fulls = ([straddle_full] + in_window_fulls).compact
      kept_fulls = fulls.last(min_keep_fulls) if kept_fulls.size < min_keep_fulls

      # A snapshot is deleted only when BOTH hold:
      #   1. it sorts before the oldest kept full (chain-safety — nothing a
      #      kept full depends on is ever removed), AND
      #   2. its timestamp is past the retention window (age).
      # With the straddle full kept, everything before oldest_kept is normally
      # also aged out, so young_orphans is non-empty only when a base full is
      # GENUINELY missing from the bucket (deleted by an old lifecycle rule or
      # by hand) — those in-window-but-unrestorable incrs are still retained:
      # age is a hard floor, and they age out naturally on later runs.
      oldest_kept = kept_fulls.first
      deletable     = known.select { |p| p < oldest_kept && p[backup_prefix_re, 1] < cutoff_key }
      young_orphans = known.select { |p| p < oldest_kept && p[backup_prefix_re, 1] >= cutoff_key }

      # Itemized listings are opt-in (VERBOSE=1): the stats block below is the
      # default report. Kept incrs are only ever summarized by count even in
      # verbose mode (48/day × 120d ≈ thousands of lines).
      verbose = ENV["VERBOSE"] == "1"
      kept_incrs = known.count { |p| p.end_with?("-incr/") && p >= oldest_kept }
      puts "  Keeping #{kept_fulls.size} of #{fulls.size} full(s) + #{kept_incrs} incremental(s) after the oldest kept full."
      if verbose
        kept_fulls.each do |p|
          reason = if p == straddle_full
                     "base full for the oldest in-window incrs (straddles the #{retention_days}d cutoff)"
                   elsif p[backup_prefix_re, 1] >= cutoff_key
                     "within #{retention_days}d retention"
                   else
                     "min-keep floor (newest #{min_keep_fulls} fulls)"
                   end
          puts "    ✔ #{p.chomp('/')}  (#{reason})"
        end
      end
      if young_orphans.any?
        puts "  ⚠️  #{young_orphans.size} orphaned snapshot(s) within #{retention_days}d retained (their base full no longer " \
             "exists in the bucket — unrestorable, but age is a hard floor; they age out on later runs):"
        puts "       first: #{young_orphans.first.chomp('/')}"
        puts "       last:  #{young_orphans.last.chomp('/')}"
      end
      # At-a-glance stats: how many snapshots survive vs go, and the exact
      # boundaries of each range (first/last name), so the retention window is
      # verifiable from the summary alone without scanning the itemized lists.
      retained = known - deletable
      puts "  📊 Stats:"
      puts "     Retained: #{retained.size} snapshot(s)"
      puts "       first: #{retained.first.chomp('/')}"
      puts "       last:  #{retained.last.chomp('/')}"
      if deletable.empty?
        puts "     To delete: 0 snapshot(s)"
        puts "  ✅ Nothing older than the kept chain — no cleanup needed."
        next
      end
      puts "     To delete: #{deletable.size} snapshot(s)"
      puts "       first: #{deletable.first.chomp('/')}"
      puts "       last:  #{deletable.last.chomp('/')}"

      # Sizing needs one paginated list_object_versions per prefix (~2k
      # versions each) — over a year's backlog that is tens of thousands of
      # sequential S3 calls. A plain dry run therefore reports counts only and
      # skips the version walk entirely; sizes appear under VERBOSE=1 (slow)
      # or during the real deletion, where the walk is needed anyway.
      unless execute || verbose
        puts "  ℹ️  Sizes not computed (needs one S3 listing per prefix — set VERBOSE=1 to size, slow on big backlogs)."
        puts "  ℹ️  Dry run — re-run with CONFIRM=1 to delete."
        next
      end

      puts "  #{execute ? 'Deleting' : 'Sizing (dry run)'} #{deletable.size} snapshot prefix(es):"

      total_bytes = 0
      total_objects = 0
      deletable.each_with_index do |prefix, idx|
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

        # Everything deletable is past retention AND before the oldest kept
        # full (both enforced above), so a single reason label suffices. The
        # [i/N] counter doubles as a progress indicator on long backlogs.
        # Age is display-only (selection stays lexical): date part vs today's
        # UTC date, tolerant of a calendar-invalid name (shows "?").
        age_days = begin
          (Time.now.utc.to_date - Date.parse(prefix[0, 10])).to_i
        rescue ArgumentError
          "?"
        end
        puts format("    %s [%d/%d] %-32s %10.2f GB in %d object versions  (aged %sd — older than %dd)",
                    execute ? "🗑" : "•", idx + 1, deletable.size, prefix.chomp("/"),
                    prefix_bytes / 1024.0**3, versions.size, age_days, retention_days)
        next unless execute

        # delete_objects caps at 1000 keys per request
        versions.each_slice(1000) do |batch|
          resp = client.delete_objects(bucket: target[:bucket],
                                       delete: { objects: batch, quiet: true })
          # quiet mode returns only failures — surface them instead of moving on
          resp.errors.first(10).each { |e| puts "      ❌ #{e.key} (#{e.version_id}): #{e.code} #{e.message}" }
          if resp.errors.any?
            # State progress before bailing: deletions run oldest-first, so
            # everything up to this prefix is fully gone and a re-run resumes
            # here; only THIS prefix may be left partially deleted.
            puts format("  ⚠️  Progress before failure: removed %.2f GB / %d object versions; prefix '%s' is PARTIALLY deleted.",
                        total_bytes / 1024.0**3, total_objects, prefix.chomp("/"))
            raise "#{resp.errors.size} delete failures in #{prefix} (first error: #{resp.errors.first.code})"
          end
        end
      end

      verb = execute ? "Deleted" : "Would delete"
      puts format("  %s %s %.2f GB across %d object versions.", execute ? "✅" : "🔍", verb.downcase, total_bytes / 1024.0**3, total_objects)
      puts "  ℹ️  Dry run — re-run with CONFIRM=1 to delete." unless execute
    rescue StandardError => e
      # Isolate failures per bucket: a throttle, permission error, or missing
      # bucket on the primary must not silently skip the replica (or vice
      # versa). Partial deletion progress is safe — oldest-first order means a
      # re-run simply continues where this one stopped.
      failures << "#{target[:bucket]}: #{e.class}: #{e.message}"
      puts "  ❌ Aborted cleaning #{target[:bucket]}: #{e.class}: #{e.message}"
    end

    # Non-zero exit so cron/CI notices, but only after every bucket had its turn.
    raise "Cleanup failed for #{failures.size} bucket(s):\n  #{failures.join("\n  ")}" if failures.any?
  end
end
