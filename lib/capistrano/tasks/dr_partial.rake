#  partial:* — Capistrano entry points for single-component recovery
# =============================================================================
# Phase 2 of component recovery (see docs/operations/dr/dr_component_recovery.md).
#
# These are THIN wrappers over rake tasks that already exist and are drill-
# tested. They add no recovery logic of their own; what they add is a way to run
# a SINGLE-BOX restore from your laptop.
#
# The gap they close: db:restore_primary_remote and db:restore_replica_remote
# have to run ON an app server, because the DB boxes accept SSH only from there
# (see the header of lib/tasks/backup_db.rake). Until now the only Capistrano
# route to them was recovery:load_db_from_backups, which restores BOTH boxes —
# so repairing one replica meant SSHing to an app server and running rake by
# hand, mid-incident. These wrappers make the single-box path a one-liner.
#
#   bundle exec cap production_in partial:restore_replica
#   BUCKET=docs.caphive.com.production-replica-backup-xtra BUCKET_REGION=ap-south-2 \
#     bundle exec cap production_in partial:restore_primary
#
# This file is picked up by the Capfile's Dir.glob over lib/capistrano/tasks —
# config/deploy.rb is deliberately not edited, so nothing tested changes.
#
# ⚠️  A restore DELETES the existing MySQL data directory on the target box.
#    Run rake "dr:assess[<env>]" first and repair the cheapest rung it names.
# =============================================================================

namespace :partial do
  # Optional source-bucket override, forwarded to the baked script as
  # BUCKET_OVERRIDE/AWS_REGION_OVERRIDE. Used when the environment's own backup
  # bucket is unreachable and the DR-region replica bucket has to stand in.
  # Returns "[bucket,region]" or "" so the task name is valid rake either way.
  def partial_bucket_args
    bucket = ENV["BUCKET"].to_s.strip
    return "" if bucket.empty?

    region = ENV["BUCKET_REGION"].to_s.strip
    region.empty? ? "[#{bucket}]" : "[#{bucket},#{region}]"
  end

  # Announce what is about to happen on which box. Restores are long and
  # destructive; the operator should never have to guess which one is running.
  def partial_banner(action)
    info "=" * 70
    info "🔧 partial:#{action} on #{fetch(:stage)} (#{fetch(:env_variant)})"
    info "   Source bucket: #{ENV['BUCKET'].to_s.empty? ? "environment default (<AWS_S3_BUCKET>-backup-xtra)" : ENV['BUCKET']}"
    info "   Follow with: LB=true bundle exec cap #{fetch(:stage)}_#{fetch(:env_variant)} recovery:verify"
    info "=" * 70
  end

  desc "Restore ONLY the DB primary from the backup chain (leaves the replica untouched)"
  task :restore_primary do
    # roles(:primary) is the first app server — the only host that can reach the
    # DB boxes. Same role the tested recovery:load_db_from_backups uses.
    on roles(:primary), in: :sequence, wait: 5 do
      within release_path do
        partial_banner("restore_primary")
        info "🗄️  Restoring the DB primary via the baked script (this can take a while)..."
        # db:restore_primary_remote arms the backup cron on whatever it restores,
        # which is correct for the primary — backups resume on the next tick.
        execute :rake, "'db:restore_primary_remote#{partial_bucket_args}' RAILS_ENV=#{fetch(:stage)}"
        info "✅ Primary restore finished."
        # Deliberately NOT resetting replication here: after restoring only the
        # primary, the replica holds data from the OLD primary and its binlog
        # positions do not correspond to the restored one. Re-pointing it
        # without also restoring it produces silent drift. Restore both
        # (recovery:load_db_from_backups) or promote instead — dr:assess says which.
        info "⚠️  Replication was NOT reset. If this box has a replica, the replica is now"
        info "    inconsistent with it — restore the replica too (partial:restore_replica)"
        info "    or re-run dr:assess for the correct path."
      end
    end
  end

  desc "Restore ONLY the DB replica from the backup chain, then re-point replication at the primary"
  task :restore_replica do
    on roles(:primary), in: :sequence, wait: 5 do
      within release_path do
        partial_banner("restore_replica")
        info "🗄️  Restoring the DB replica via the baked script, then resetting replication..."
        # db:restore_replica_remote also disarms the backup cron on the replica
        # (single writer per chain) and calls AwsUtils.reset_replication('2').
        execute :rake, "'db:restore_replica_remote#{partial_bucket_args}' RAILS_ENV=#{fetch(:stage)}"
        info "✅ Replica restored, backup cron disarmed, replication re-pointed."
      end
    end
  end

  desc "Verify Redis, Sidekiq and Elasticsearch from inside the app (closes the gap dr:verify leaves)"
  task :verify_data_tier do
    # Every app server, not just the primary: each one has its own Redis and ES
    # connections, and a repair that fixed one box says nothing about the other.
    on roles(:app), in: :sequence do
      within release_path do
        info "🩺 Verifying the data tier from #{host}..."
        # dr:verify_data_tier aborts non-zero on any failed check, which makes
        # execute raise here — so a green run is proof, not a summary.
        execute :rake, "dr:verify_data_tier RAILS_ENV=#{fetch(:stage)}"
      end
    end
  end

  desc "Re-point the replica at the primary and restart the replication stream (no restore)"
  task :reset_replication do
    on roles(:primary), in: :sequence do
      within release_path do
        info "🔁 Resetting replication (replica → primary) on #{fetch(:stage)}..."
        # Only safe when the two boxes already hold the same dataset — i.e. the
        # stream stopped but neither box was rebuilt. If either was restored,
        # use partial:restore_replica so the data matches before the stream starts.
        execute :rake, "'db:reset_replication[2]' RAILS_ENV=#{fetch(:stage)}"
        info "✅ Replication reset. Verify with: LB=true bundle exec cap #{fetch(:stage)}_#{fetch(:env_variant)} recovery:verify"
      end
    end
  end
end
