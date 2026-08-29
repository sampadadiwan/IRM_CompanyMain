

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

  # Serializes the pre-bake-AMI fallback (script generation via a Rake task,
  # which is NOT safe to invoke from two threads at once) when primary and
  # replica restores run in parallel (db:restore_all_remote).
  RESTORE_FALLBACK_MUTEX = Mutex.new

  # Streams `sudo db_backup_xtra.sh restore_primary` on the given DB host.
  # disarm_after: the script ARMS the backup cron on whatever it restores —
  # correct for the primary, wrong for the replica (one writer per chain).
  # bucket/bucket_region: optional source override (e.g. the DR-region replica
  # bucket when the primary region's S3 is gone) — forwarded to the script as
  # BUCKET_OVERRIDE/AWS_REGION_OVERRIDE, its highest-priority config source.
  # label: prefixes every output line (e.g. "[primary]") so two restores
  # streaming in parallel stay readable.
  def run_baked_restore(host, disarm_after: false, bucket: nil, bucket_region: nil, label: nil)
    require 'net/ssh'
    raise "No DB host resolved — check credentials DB_HOST/DB_HOST_REPLICA" if host.to_s.empty?

    prefix = label ? "[#{label}] " : ""
    # Line-buffered, prefixed emitter: SSH hands us arbitrary chunks; split on
    # lines so parallel streams don't interleave mid-line
    emit = lambda do |data|
      data.to_s.each_line { |l| puts "#{prefix}#{l.chomp}" }
    end

    key_path = File.expand_path("~/.ssh/#{ENV.fetch('KEYNAME')}.pem")
    script = "/usr/local/bin/db_backup_xtra.sh"
    puts "#{prefix}→ Restoring via baked script on #{host} (this can take a while)"

    exit_code = nil
    # verify_host_key: :never — DR boxes get torn down and recreated with a
    # fresh SSH host key but frequently land back on the same private IP
    # (small subnet, low-order IP reuse); a strict host-key check rejects that
    # as a fingerprint mismatch even though it's a legitimate new box. Matches
    # config/deploy/staging_in.rb's ssh_options, which disables it for the
    # same reason.
    Net::SSH.start(host, "ubuntu", keys: [key_path], timeout: 15, verify_host_key: :never) do |ssh|
      # Clear staging left behind by a PREVIOUS failed restore, before anything
      # else touches the box.
      #
      # Each attempt stages the backup in /tmp/xb_<pid> — tens of GB on
      # production — and an aborted run never reaches the script's own
      # cleanup(). Two failures in a row therefore fill the disk to 0 bytes, at
      # which point the next attempt cannot even SCP this 24KB script onto the
      # box: DR becomes unrecoverable without someone SSHing in by hand, which
      # is the worst possible time to need manual intervention. Found on both
      # staging and production DB boxes during the 2026-08-29 drills.
      #
      # Runs over the already-open SSH session and needs no disk space itself.
      stale = ssh.exec!("sudo du -shc /tmp/xb_* 2>/dev/null | tail -1 | awk '{print $1}'").to_s.strip
      unless stale.empty?
        puts "#{prefix}🧹 Clearing #{stale} of staging left by a previous failed restore (/tmp/xb_*)"
        ssh.exec!("sudo rm -rf /tmp/xb_*")
      end

      # Instances from pre-bake AMIs (no rebake since the backup tooling was
      # added to the Packer template) don't have the baked script — bridge by
      # generating the env-specific script here and uploading it. Same script,
      # same restore_primary entrypoint; only the delivery differs.
      # `sudo test`: the baked script is root:root 0700, so a plain `test -x`
      # as ubuntu is ALWAYS false — that silently sent every restore down the
      # fallback path and the baked/SSM path never ran (found 2026-07-10).
      unless ssh.exec!("sudo test -x #{script} && echo yes").to_s.strip == "yes"
        puts "#{prefix}ℹ️ #{script} not on #{host} (pre-bake AMI) — uploading generated script instead."
        require 'net/scp'
        local_script = Rails.root.join("tmp", "db_backup_xtra_#{Rails.env}.sh")
        # Mutex: parallel restores must not both invoke the generator task
        RESTORE_FALLBACK_MUTEX.synchronize do
          unless File.exist?(local_script)
            Rake::Task['xtrabackup:generate_backup_script'].invoke # substitutes secrets from credentials
          end
        end
        script = "/home/ubuntu/db_backup_xtra.sh"
        Net::SCP.start(host, "ubuntu", keys: [key_path], timeout: 15, verify_host_key: :never) do |scp|
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
        puts "#{prefix}→ Restoring from OVERRIDE bucket: #{bucket}#{" (#{bucket_region})" if bucket_region}"
      end

      # Stream the restore live so the operator sees xtrabackup progress
      ssh.open_channel do |ch|
        ch.exec("sudo #{env_prefix}#{script} restore_primary") do |c, success|
          raise "Could not start restore on #{host}" unless success

          c.on_data { |_, data| emit.call(data) }
          c.on_extended_data { |_, _, data| emit.call(data) }
          c.on_request("exit-status") { |_, data| exit_code = data.read_long }
        end
      end
      ssh.loop

      raise "restore_primary exited with status #{exit_code} on #{host}" unless exit_code&.zero?

      if disarm_after
        # Replica must never write to the backup chain — remove the marker
        # restore_primary just created
        ssh.exec!("sudo rm -f /etc/db_backup_enabled")
        puts "#{prefix}→ Backup cron disarmed on #{host} (replica: single writer per chain)"
      end
    end
    puts "#{prefix}✅ Restore complete on #{host}"
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

  # Primary and replica are separate boxes restoring the SAME chain from S3 —
  # the heavy work (download + xtrabackup prepare + datadir swap) is fully
  # independent, so running them in parallel cuts the longest DR phase from
  # primary+replica to max(primary, replica). The ONLY ordering constraint is
  # reset_replication at the end: it reads the PRIMARY's live binlog position
  # (SHOW BINARY LOG STATUS on 8.4+, SHOW MASTER STATUS on 8.0 — the fleet runs
  # both), so it must wait for BOTH restores to finish.
  # Safe because traffic is off (nginx maintenance mode) between restore and
  # replication setup — nothing writes to the primary in that window.
  desc "DR: restore primary AND replica in parallel, then re-point replication"
  task :restore_all_remote, [:bucket, :bucket_region] => :environment do |t, args|
    primary_host = Rails.application.credentials[:DB_HOST]
    replica_host = Rails.application.credentials[:DB_HOST_REPLICA]
    has_replica = replica_host.present? && replica_host != primary_host

    errors = Queue.new # thread-safe collector — either restore failing must fail the task
    threads = []
    threads << Thread.new do
      run_baked_restore(primary_host,
                        bucket: args[:bucket], bucket_region: args[:bucket_region], label: "primary")
    rescue StandardError => e
      # Keep the top of the backtrace: e.message alone hides WHERE it raised
      errors << "primary (#{primary_host}): #{e.message} [at #{e.backtrace&.first}]"
    end

    if has_replica
      threads << Thread.new do
        run_baked_restore(replica_host, disarm_after: true,
                          bucket: args[:bucket], bucket_region: args[:bucket_region], label: "replica")
      rescue StandardError => e
        errors << "replica (#{replica_host}): #{e.message} [at #{e.backtrace&.first}]"
      end
    else
      puts "ℹ️ No separate replica configured — restoring primary only."
    end

    threads.each(&:join)
    unless errors.empty?
      failures = Array.new(errors.size) { errors.pop }
      raise "Parallel restore FAILED (#{failures.size}/#{threads.size} restores errored): #{failures.join('; ')}"
    end

    if has_replica
      # Both boxes now hold the same dataset — point the replica at the
      # freshly restored primary and start the stream
      AwsUtils.reset_replication('2')
      puts "DB replication reset completed."
    end
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
