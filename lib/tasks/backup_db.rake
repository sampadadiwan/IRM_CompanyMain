

namespace :db do
  # ---------------------------------------------------------------------------
  # DR restore path (the RIGHT way to restore the real primary/replica):
  # SSH from the app server to the DB box and run the backup script that is
  # BAKED into the DB AMI (/usr/local/bin/db_backup_xtra.sh — secret-free,
  # config from SSM via the instance role). No script generation, no IAM
  # creation, no service cleanup — those belong to DbRestoreService, whose job
  # is VERIFYING backups on a throwaway DbCheckInstance, not DR.
  # Runs on the app server (rake via cap recovery:load_db_from_backups):
  # the DB boxes are reachable only from there.
  # ---------------------------------------------------------------------------

  # Streams `sudo db_backup_xtra.sh restore_primary` on the given DB host.
  # disarm_after: the script ARMS the backup cron on whatever it restores —
  # correct for the primary, wrong for the replica (one writer per chain).
  # bucket/bucket_region: optional source override (e.g. the DR-region replica
  # bucket when the primary region's S3 is gone) — forwarded to the script as
  # BUCKET_OVERRIDE/AWS_REGION_OVERRIDE, its highest-priority config source.
  def run_baked_restore(host, disarm_after: false, bucket: nil, bucket_region: nil)
    require 'net/ssh'
    raise "No DB host resolved — check credentials DB_HOST/DB_HOST_REPLICA" if host.to_s.empty?

    key_path = File.expand_path("~/.ssh/#{ENV.fetch('KEYNAME')}.pem")
    script = "/usr/local/bin/db_backup_xtra.sh"
    puts "→ Restoring via baked script on #{host} (this can take a while)"

    exit_code = nil
    Net::SSH.start(host, "ubuntu", keys: [key_path], timeout: 15) do |ssh|
      # Instances from pre-bake AMIs (no rebake since the backup tooling was
      # added to the Packer template) don't have the baked script — bridge by
      # generating the env-specific script here and uploading it. Same script,
      # same restore_primary entrypoint; only the delivery differs.
      unless ssh.exec!("test -x #{script} && echo yes").to_s.strip == "yes"
        puts "ℹ️ #{script} not on #{host} (pre-bake AMI) — uploading generated script instead."
        require 'net/scp'
        local_script = Rails.root.join("tmp", "db_backup_xtra_#{Rails.env}.sh")
        unless File.exist?(local_script)
          Rake::Task['xtrabackup:generate_backup_script'].invoke # substitutes secrets from credentials
        end
        script = "/home/ubuntu/db_backup_xtra.sh"
        Net::SCP.start(host, "ubuntu", keys: [key_path], timeout: 15) do |scp|
          scp.upload!(local_script.to_s, script)
        end
        # Contains credentials — owner-only, executable
        ssh.exec!("chmod 700 #{script}")
      end

      # Optional source-bucket override travels via `sudo env` (plain
      # `sudo VAR=x` does not pass environment assignments through)
      env_prefix = ""
      if bucket
        env_prefix = "env BUCKET_OVERRIDE=#{bucket} "
        env_prefix += "AWS_REGION_OVERRIDE=#{bucket_region} " if bucket_region
        puts "→ Restoring from OVERRIDE bucket: #{bucket}#{" (#{bucket_region})" if bucket_region}"
      end

      # Stream the restore live so the operator sees xtrabackup progress
      ssh.open_channel do |ch|
        ch.exec("sudo #{env_prefix}#{script} restore_primary") do |c, success|
          raise "Could not start restore on #{host}" unless success

          c.on_data { |_, data| print data }
          c.on_extended_data { |_, _, data| print data }
          c.on_request("exit-status") { |_, data| exit_code = data.read_long }
        end
      end
      ssh.loop

      raise "restore_primary exited with status #{exit_code} on #{host}" unless exit_code&.zero?

      if disarm_after
        # Replica must never write to the backup chain — remove the marker
        # restore_primary just created
        ssh.exec!("sudo rm -f /etc/db_backup_enabled")
        puts "→ Backup cron disarmed on #{host} (replica: single writer per chain)"
      end
    end
    puts "✅ Restore complete on #{host}"
  end

  # Optional args pick the SOURCE bucket, e.g. restoring from the DR-region
  # replica during a true region loss:
  #   rake "db:restore_primary_remote[docs.altx.com.staging-replica-backup-xtra, ap-south-2]"
  # No args = the env's default bucket (<AWS_S3_BUCKET>-backup-xtra).
  desc "DR: restore the REAL primary by running the baked backup script on the DB server"
  task :restore_primary_remote, [:bucket, :bucket_region] => :environment do |t, args|
    run_baked_restore(Rails.application.credentials[:DB_HOST],
                      bucket: args[:bucket], bucket_region: args[:bucket_region])
    # Backup cron is now armed on the primary (restore_primary side effect) —
    # backups resume automatically on the next cron tick
  end

  desc "DR: restore the replica via the baked script, then re-point replication"
  task :restore_replica_remote, [:bucket, :bucket_region] => :environment do |t, args|
    run_baked_restore(Rails.application.credentials[:DB_HOST_REPLICA], disarm_after: true,
                      bucket: args[:bucket], bucket_region: args[:bucket_region])
    # Replica now holds the same dataset as the restored primary — connect the
    # replication stream from the correct binlog position
    AwsUtils.reset_replication('2')
    puts "DB replication reset completed."
  end

  desc "Reset MySQL replication: point the replica at the primary and restart the stream"
  task :reset_replication, [:server_id] => :environment do |t, args|
    args.with_defaults(server_id: '2')
    server_id = args[:server_id]
    AwsUtils.reset_replication(server_id)
    puts "DB replication reset completed."
  end

  # LEGACY: goes through DbRestoreService (the backup VERIFIER). Kept for
  # instances from pre-baked-AMI eras; the DR path is restore_primary_remote.
  desc "Restore primary database using DbRestoreService (legacy — prefer db:restore_primary_remote)"
  task :restore_primary_db => :environment do
    puts "Starting DB restore process..."
    DbRestoreService.run!(instance_name: "DB-Redis-ES", stop_instance_flag: false)
    # After a primary restore the replica's replication position is stale — reset it
    # so it re-syncs from the newly restored primary instead of replaying from an old offset.
    AwsUtils.reset_replication('2')
    puts "DB restore process completed."
  end

  # LEGACY: see restore_primary_db note above; DR path is restore_replica_remote.
  desc "Restore replica database using DbRestoreService (legacy — prefer db:restore_replica_remote)"
  task :restore_replica_db => :environment do
    puts "Starting DB restore process..."
    DbRestoreService.run!(instance_name: "DB-Redis-ES-Replica", stop_instance_flag: false)
    AwsUtils.reset_replication('2')
    puts "DB restore process completed."
  end

  # NOTE: a second `task :reset_replication` used to be defined here. Rake
  # MERGES same-named tasks (both blocks run on one invocation), so replication
  # was being reset twice per call. Keep exactly one definition (above).
end
