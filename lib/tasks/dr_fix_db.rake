#  dr:fix:db_* — database-tier component recovery
# =============================================================================
# Phase 5 of component recovery (see docs/DR_COMPONENT_RECOVERY.md).
# Continues the dr:fix namespace opened in lib/tasks/dr_fix.rake.
#
# Always run rake "dr:assess[<env>]" first — it says WHICH of these applies.
#
#   dr:fix:db_replica       replica box is broken or gone; primary is fine
#   dr:fix:promote_replica  primary is gone, replica is healthy   → RPO ≈ 0
#   dr:fix:db_primary       primary is gone, replica is unusable  → RPO ≈ 1h
#
# The choice between the last two is the most consequential in this whole tool:
# rebuilding from S3 discards everything written since the newest incremental,
# which a healthy replica is still holding. Promote when you can.
#
# THREE THINGS MAKE THESE DIFFERENT FROM THE APP-SERVER REPAIR:
#
#  1. NOT host-filtered. DB_HOST lives in the committed encrypted credentials,
#     so EVERY app server must be redeployed to learn a new address. Filtering
#     to one host would leave the other pointing at a dead box.
#  2. The primary box is DB-Redis-ES: losing it also loses Redis (Sidekiq
#     queues, ActionCable) and the Elasticsearch indexes. Neither is replicated.
#     Rails.cache is solid_cache (MySQL), so the cache itself is unaffected.
#  3. A restore DELETES the target box's MySQL data directory.
# =============================================================================

require_relative "aws_utils"

include AwsUtils

# Refuse to deploy anything other than what is already live. commit_dr_changes
# branches from local HEAD, so HEAD must match the running revision or an
# incident deploy quietly ships unreleased work. Returns the SHA to deploy.
def dr_fix_db_revision_guard!(host, cap_key)
  deployed = dr_fix_deployed_revision(host, cap_key)
  local_head = `git rev-parse HEAD`.strip

  if deployed.empty?
    puts "⚠️  Could not read REVISION from #{host} — cannot confirm HEAD matches what is deployed."
  elsif deployed != local_head
    abort "\n❌ ABORT: #{host} is running #{deployed[0, 12]} but your HEAD is #{local_head[0, 12]}.\n" \
          "   Check out the deployed revision so this repair ships nothing new:\n" \
          "     git checkout #{deployed}\n" \
          "   (then re-run this task)"
  else
    puts "✅ Local HEAD matches the revision #{host} is running (#{deployed[0, 12]})."
  end
  local_head
end

# Run a cap task across ALL app servers (see rule 1 in the header). LB=true so
# stage files that gate their second host on it include it.
def dr_fix_db_cap(env, task, deploy_ref: nil, extra_env: "")
  puts "   ▶ #{task}"
  dr_fix_db_cap_run(env, task, deploy_ref: deploy_ref, extra_env: extra_env) ||
    abort("\n❌ cap #{task} failed — stopping here so the state is inspectable.")
end

# Same invocation, but returns the result instead of aborting — for verification
# steps, where a failure must be REPORTED alongside the follow-ups rather than
# cutting the run off before the operator sees what to do next.
#
# Shares the command construction with dr_fix_db_cap deliberately: a hand-built
# `system("... cap recovery:verify")` silently drops the branch pin, so
# verification could run against a different revision than the one just deployed.
def dr_fix_db_cap_run(env, task, deploy_ref: nil, extra_env: "")
  cmd = "#{"branch=#{deploy_ref} " if deploy_ref}LB=true SKIP_NOTIFICATION=true #{extra_env} " \
        "bundle exec cap #{env[:cap_stage]} #{task}"
  system(cmd)
end

# Locate a DB box's Pulumi instance resource by its private IP.
def dr_fix_db_instance(resources, private_ip, label)
  # Skip `delete: true` entries — pending-deletion leftovers from an interrupted
  # update, which must never be the target of a repair.
  instance = resources.find do |r|
    r["type"] == "aws:ec2/instance:Instance" && !r["delete"] &&
      r.dig("outputs", "privateIp") == private_ip
  end
  raise "Could not find the #{label} (#{private_ip}) in the Pulumi stack" unless instance

  instance
end

# Shared preamble: resolve, guard the account, and find a way in to the DB tier.
# Returns [env, cap_key, inventory, app_host].
def dr_fix_db_context(env_name)
  env = dr_assess_resolve_env(env_name)
  dr_account_guard!(env)
  cap_key = dr_assess_cap_key(env[:deploy_file])

  # State rather than stack outputs — the outputs are stale on every live stack
  # and, on staging, disagree with the state about how many servers exist.
  inventory = dr_stack_inventory(env[:pulumi_stack])
  app_ips = inventory[:app_servers].filter_map { |i| i[:public_ip] }
  app_host = dr_fix_live_app_host(app_ips, cap_key)
  # Every DB operation here runs from an app server, because the DB boxes accept
  # SSH only from web-sg. No app server means no data-tier repair is possible.
  unless app_host
    abort "❌ No app server is reachable. Repair one first (rake \"dr:fix:app_server[#{env_name}, <ip>]\") — " \
          "the DB boxes are only reachable through them."
  end

  [env, cap_key, inventory, app_host]
end

namespace :dr do
  namespace :fix do
    # -------------------------------------------------------------------
    # Replica box — the primary keeps serving throughout
    # -------------------------------------------------------------------
    desc "Repair the DB replica: restart it, reset replication, or rebuild the box and restore it"
    task :db_replica, [:env_name] => :environment do |_t, args|
      env_name = args[:env_name] or raise "Usage: rake \"dr:fix:db_replica[production.in]\""
      env, cap_key, inventory, app_host = dr_fix_db_context(env_name)

      db_host = inventory.dig(:db_primary, :private_ip)
      replica = inventory.dig(:db_replica, :private_ip)

      puts ""
      puts "=" * 78
      puts "🔧 DR FIX · DB replica · #{env_name} · #{env[:region]}"
      puts "   Primary #{db_host} keeps serving writes throughout this repair."
      puts "   Reads DO fail while the replica is down: DatabaseSelector routes them"
      puts "   to the replica 5s after a write (config/initializers/multi_db.rb)."
      puts "=" * 78

      if replica.to_s.empty? || replica == db_host
        abort "❌ This stack has no separate replica (DB_HOST_REPLICA == DB_HOST) — nothing to repair."
      end

      reachable = begin
        dr_assess_ssh_via_app(app_host, cap_key, replica, env[:db_keyname], "echo up").include?("up")
      rescue StandardError => e
        puts "   no SSH to #{replica}: #{e.message.to_s.lines.first.to_s.strip}"
        false
      end

      # --- cheap rungs: the box is alive --------------------------------
      if reachable
        puts "✅ #{replica} is reachable — repairing in place (no rebuild, no restore)."

        state = dr_assess_ssh_via_app(app_host, cap_key, replica, env[:db_keyname], "systemctl is-active mysql")
        if state != "active"
          puts "🔧 mysqld is #{state} — starting it..."
          dr_assess_ssh_via_app(app_host, cap_key, replica, env[:db_keyname], "sudo systemctl start mysql")
          sleep 10
          state = dr_assess_ssh_via_app(app_host, cap_key, replica, env[:db_keyname], "systemctl is-active mysql")
          puts "   #{state == 'active' ? '✅' : '❌'} mysqld is now #{state}"
          abort "\n❌ mysqld will not start on #{replica}. If its data is damaged, rebuild instead:\n" \
                "   terminate the box, then re-run this task." unless state == "active"
        end

        # A replica that is up but not replicating is a reset, not a restore —
        # provided nothing was rebuilt, so both boxes still share a lineage.
        puts "🔁 Re-pointing replication at #{db_host} and restarting the stream..."
        dr_fix_db_cap(env, "partial:reset_replication")

        # Single writer per backup chain — the replica must never be armed.
        armed = dr_assess_ssh_via_app(app_host, cap_key, replica, env[:db_keyname],
                                      "test -f /etc/db_backup_enabled && echo yes")
        if armed == "yes"
          puts "🔧 Replica had the backup marker set — removing it (two writers corrupt the chain)."
          dr_assess_ssh_via_app(app_host, cap_key, replica, env[:db_keyname], "sudo rm -f /etc/db_backup_enabled")
        end

        puts "\n🟢 Replica repaired in place. Verify: LB=true bundle exec cap #{env[:cap_stage]} recovery:verify"
        next
      end

      # --- rebuild rung ---------------------------------------------------
      puts "\n🔴 #{replica} is unreachable — rebuilding the box and restoring it from the backup chain."
      resources = dr_fix_stack_resources(env[:pulumi_stack])
      instance = dr_fix_db_instance(resources, replica, "DB replica")
      # DB boxes have no target-group attachment — nothing to carry along.
      dr_fix_preview_guard!(env[:pulumi_stack], [instance["urn"]])
      dr_fix_await_pulumi!(env[:pulumi_stack], [instance["urn"]])

      new_output = pulumi_stack_output(env[:pulumi_stack])
      new_replica = new_output.dig("private_ips", "DB_HOST_REPLICA")
      raise "Stack no longer reports a DB_HOST_REPLICA address" if new_replica.to_s.empty?

      deploy_ref = `git rev-parse HEAD`.strip
      if new_replica == replica
        # Frequent in these small subnets: same address, so the credentials
        # already point at the right place and no deploy is needed at all.
        puts "✅ The replacement reused #{replica} — no credential change, no deploy needed."
      else
        puts "📌 New replica address: #{replica} → #{new_replica}"
        dr_fix_db_revision_guard!(app_host, cap_key)
        update_rails_credentials(env[:stack], env[:variant], "DB_HOST_REPLICA", new_replica)
        fix_branch = "dr_fix_replica_#{Time.now.strftime('%Y_%m_%d_%H%M')}"
        commit_dr_changes(env[:stack], env[:variant], env[:region], fix_branch)
        deploy_ref = fix_branch

        # ALL app servers: the new address lives in the committed credentials,
        # so every box needs the new release (see rule 1 in this file's header).
        puts "\n🚀 Deploying the new replica address to EVERY app server..."
        dr_fix_db_cap(env, "deploy", deploy_ref: deploy_ref, extra_env: "SKIP_MIGRATE=true")
      end

      # partial:restore_replica restores via the baked script, disarms the backup
      # cron on the replica, and calls reset_replication — all existing, tested.
      puts "\n🗄️  Restoring the new replica from the backup chain..."
      dr_fix_db_cap(env, "partial:restore_replica", deploy_ref: deploy_ref)

      puts "\n🔎 Verifying..."
      verified = dr_fix_db_cap_run(env, "recovery:verify", deploy_ref: deploy_ref)
      puts "\n#{verified ? '🟢 DB replica repaired and verified.' : '🔴 Replica rebuilt but recovery:verify FAILED — see above.'}"
      abort "" unless verified
    end

    # -------------------------------------------------------------------
    # Promote the replica — the fast path when the primary dies
    # -------------------------------------------------------------------
    desc "Promote the DB replica to primary (RPO ~0). Use when the primary is gone and the replica is healthy."
    task :promote_replica, [:env_name] => :environment do |_t, args|
      env_name = args[:env_name] or raise "Usage: rake \"dr:fix:promote_replica[production.in]\""
      env, cap_key, inventory, app_host = dr_fix_db_context(env_name)

      db_host = inventory.dig(:db_primary, :private_ip)
      replica = inventory.dig(:db_replica, :private_ip)

      puts ""
      puts "=" * 78
      puts "🔧 DR FIX · PROMOTE REPLICA · #{env_name} · #{env[:region]}"
      puts "   Promotes #{replica} to primary. Recovers everything the replica had"
      puts "   received — no restore, so RPO is ~0 rather than the last incremental."
      puts "=" * 78

      abort "❌ This stack has no separate replica — nothing to promote." if replica.to_s.empty? || replica == db_host

      # --- split-brain gate ----------------------------------------------
      # A live primary plus a promoted replica is the one outcome worse than the
      # outage: two writers, diverging, with no way to merge them afterwards.
      puts "\n🔎 Confirming the old primary #{db_host} is really gone..."
      primary_alive = begin
        dr_assess_ssh_via_app(app_host, cap_key, db_host, env[:db_keyname], "systemctl is-active mysql") == "active"
      rescue StandardError
        false
      end
      if primary_alive
        abort "\n❌ ABORT: mysqld is STILL RUNNING on the primary #{db_host}.\n" \
              "   Promoting now would create two writers (split brain). Stop the primary\n" \
              "   deliberately first, or use dr:fix:db_primary instead."
      end
      puts "   ✅ primary is not serving MySQL"

      puts "\n🔎 Checking the replica is healthy enough to promote..."
      status = dr_assess_ssh_via_app(app_host, cap_key, replica, env[:db_keyname],
                                     "sudo mysql -N -e \"SHOW REPLICA STATUS\\G\" 2>&1 | " \
                                     "grep -E 'Replica_(IO|SQL)_Running:|Seconds_Behind_Source:|Last_Error:'")
      puts status.to_s.lines.map { |l| "   #{l}" }.join
      # .to_s first: grep matching nothing (or an empty SSH result) yields nil,
      # and promotion must not die with a NoMethodError at its health check.
      error = status.to_s[/Last_Error:\s*(.+)/, 1].to_s.strip
      puts "   ⚠️  replica reported a replication error — data may be incomplete" unless error.empty?

      puts "\n⚠️  What promotion costs, regardless of how well it goes:"
      puts "   • Sidekiq queues, retries and scheduled jobs die with the old box's Redis."
      puts "   • Elasticsearch indexes are empty on the new box until rake chewy:reset."
      puts "   • Until you rebuild a replica, this environment runs on a SINGLE database."
      print "\nType 'promote' to proceed, anything else aborts: "
      abort "\n❌ Aborted — nothing changed." unless STDIN.gets.to_s.strip.casecmp("promote").zero?

      # --- take traffic offline -------------------------------------------
      puts "\n🚧 Switching nginx to maintenance mode (the app is already broken; this makes it a clean page)..."
      dr_fix_db_cap(env, "nginx:switch_maintenance")

      # --- promote ---------------------------------------------------------
      puts "\n⬆️  Promoting #{replica}..."
      dr_assess_ssh_via_app(app_host, cap_key, replica, env[:db_keyname],
                            "sudo mysql -e 'STOP REPLICA; RESET REPLICA ALL;'")
      puts "   ✅ replication stopped and cleared — this box is now a standalone primary"

      # Arming is normally a side effect of restore_primary. A promoted box never
      # ran a restore, so without this it would silently take NO backups.
      dr_assess_ssh_via_app(app_host, cap_key, replica, env[:db_keyname], "sudo touch /etc/db_backup_enabled")
      puts "   ✅ backup cron armed (/etc/db_backup_enabled)"

      # Same AMI as the old primary, so the containers exist — but they were
      # never needed on a replica and may not be running.
      dr_assess_ssh_via_app(app_host, cap_key, replica, env[:db_keyname],
                            "sudo /usr/local/bin/start_data_containers.sh || true")
      names = dr_assess_ssh_via_app(app_host, cap_key, replica, env[:db_keyname],
                                    "docker ps --format {{.Names}} 2>/dev/null || sudo docker ps --format {{.Names}}")
      %w[elasticsearch redis-stack-server].each do |c|
        puts "   #{names.include?(c) ? '✅' : '❌'} #{c}"
      end

      # --- repoint the application -----------------------------------------
      puts "\n📝 Repointing the application at #{replica}..."
      dr_fix_db_revision_guard!(app_host, cap_key)
      update_rails_credentials(env[:stack], env[:variant], "DB_HOST", replica)
      # Both roles point at the promoted box on purpose: there IS no replica now,
      # and dr:verify skips its replication checks when the two match — so the
      # existing verifier reports honestly on a degraded single-DB stack instead
      # of failing on a replica that deliberately does not exist.
      update_rails_credentials(env[:stack], env[:variant], "DB_HOST_REPLICA", replica)
      # Redis and Elasticsearch lived on the dead box too.
      update_env_file(".env.#{env_name}", "REDIS_URL", "redis://#{replica}:6379")
      update_env_file(".env.#{env_name}", "ELASTIC_SEARCH_URL", "#{replica}:9200")

      fix_branch = "dr_fix_promote_#{Time.now.strftime('%Y_%m_%d_%H%M')}"
      commit_dr_changes(env[:stack], env[:variant], env[:region], fix_branch)

      puts "\n🚀 Deploying to EVERY app server..."
      dr_fix_db_cap(env, "deploy", deploy_ref: fix_branch)

      puts "\n🟢 Restoring traffic..."
      dr_fix_db_cap(env, "nginx:switch_app", deploy_ref: fix_branch)

      puts "\n🔎 Verifying..."
      verified = dr_fix_db_cap_run(env, "recovery:verify", deploy_ref: fix_branch)
      data_tier = dr_fix_db_cap_run(env, "partial:verify_data_tier", deploy_ref: fix_branch)

      puts ""
      puts "=" * 78
      puts "#{verified && data_tier ? '🟢' : '🔴'} Promotion #{verified && data_tier ? 'complete and verified' : 'finished with FAILED checks — see above'}"
      puts "=" * 78
      puts "\n📋 Required follow-ups, in order:"
      puts "   1. Rebuild the Elasticsearch indexes (they died with the old box):"
      puts "      LB=true bundle exec cap #{env[:cap_stage]} deploy:chewy_reset   # or rake chewy:reset on a box"
      puts "   2. Rebuild a replica so this environment is not on a single database:"
      puts "      rake \"dr:fix:db_replica[#{env_name}]\"  (after terminating the dead box)"
      puts "   3. Sidekiq jobs queued at the moment of failure are GONE — re-drive anything critical."
      puts "\n⚠️  Role inversion: DB_HOST now points at Pulumi's db-replica-* resource. This is harmless"
      puts "    and self-heals at the next full DR (which rebuilds both from S3 and rewrites both"
      puts "    credentials), but do NOT run a bare untargeted `pulumi up` on this stack before then."
      abort "" unless verified && data_tier
    end

    # -------------------------------------------------------------------
    # Rebuild the primary from S3 — the fallback when promotion is not open
    # -------------------------------------------------------------------
    desc "Rebuild the DB primary from AMI and restore it (and the replica) from the backup chain"
    task :db_primary, [:env_name] => :environment do |_t, args|
      env_name = args[:env_name] or raise "Usage: rake \"dr:fix:db_primary[production.in]\""
      env, cap_key, inventory, app_host = dr_fix_db_context(env_name)

      db_host = inventory.dig(:db_primary, :private_ip)
      replica = inventory.dig(:db_replica, :private_ip)

      puts ""
      puts "=" * 78
      puts "🔧 DR FIX · DB primary · #{env_name} · #{env[:region]}"
      puts "   Rebuilds #{db_host} and restores it from S3. Everything written since"
      puts "   the newest incremental backup is LOST (roughly up to an hour)."
      puts "=" * 78

      # If the replica is healthy it is holding data this path would discard, so
      # make the operator reject promotion explicitly rather than by omission.
      if !replica.to_s.empty? && replica != db_host
        replica_ok = begin
          dr_assess_ssh_via_app(app_host, cap_key, replica, env[:db_keyname], "systemctl is-active mysql") == "active"
        rescue StandardError
          false
        end
        if replica_ok
          puts "\n⚠️  The replica #{replica} is UP and holds data newer than any backup."
          puts "    rake \"dr:fix:promote_replica[#{env_name}]\" would recover it with RPO ~0."
          unless ENV["CONFIRM_DATA_LOSS"] == "true"
            abort "\n❌ Refusing to discard recoverable data. Promote instead, or set CONFIRM_DATA_LOSS=true " \
                  "if you have a reason to rebuild from backups (a corrupted replica, say)."
          end
          puts "    CONFIRM_DATA_LOSS=true — proceeding with the rebuild anyway."
        end
      end

      puts "\n🚧 Switching nginx to maintenance mode..."
      dr_fix_db_cap(env, "nginx:switch_maintenance")

      resources = dr_fix_stack_resources(env[:pulumi_stack])
      instance = dr_fix_db_instance(resources, db_host, "DB primary")
      dr_fix_preview_guard!(env[:pulumi_stack], [instance["urn"]])
      dr_fix_await_pulumi!(env[:pulumi_stack], [instance["urn"]])

      new_output = pulumi_stack_output(env[:pulumi_stack])
      new_primary = new_output.dig("private_ips", "DB_HOST")
      raise "Stack no longer reports a DB_HOST address" if new_primary.to_s.empty?

      deploy_ref = `git rev-parse HEAD`.strip
      if new_primary == db_host
        puts "✅ The replacement reused #{db_host} — no credential change needed."
      else
        puts "📌 New primary address: #{db_host} → #{new_primary}"
        dr_fix_db_revision_guard!(app_host, cap_key)
        update_rails_credentials(env[:stack], env[:variant], "DB_HOST", new_primary)
        # Redis and Elasticsearch live on this box too.
        update_env_file(".env.#{env_name}", "REDIS_URL", "redis://#{new_primary}:6379")
        update_env_file(".env.#{env_name}", "ELASTIC_SEARCH_URL", "#{new_primary}:9200")
        fix_branch = "dr_fix_primary_#{Time.now.strftime('%Y_%m_%d_%H%M')}"
        commit_dr_changes(env[:stack], env[:variant], env[:region], fix_branch)
        deploy_ref = fix_branch
      end

      # SKIP_MIGRATE is required, not tidy: the restore has not run yet, so there
      # is no schema to migrate — and on a virgin box there is no database at
      # all. recovery:migrate replays real migrations AFTER the restore.
      puts "\n🚀 Deploying the new address to EVERY app server (migrations deferred)..."
      dr_fix_db_cap(env, "deploy", deploy_ref: deploy_ref, extra_env: "SKIP_MIGRATE=true")

      # Both boxes, in parallel, then replication reset — the existing tested
      # path. Restoring only the primary would leave the replica holding data
      # from the OLD primary at binlog positions that do not match the restored
      # one: silent drift rather than an error.
      puts "\n🗄️  Restoring the database from the backup chain (both boxes, in parallel)..."
      dr_fix_db_cap(env, "recovery:load_db_from_backups", deploy_ref: deploy_ref)

      puts "\n⬆️  Replaying migrations newer than the backup..."
      dr_fix_db_cap(env, "recovery:migrate", deploy_ref: deploy_ref)

      puts "\n🟢 Restoring traffic..."
      dr_fix_db_cap(env, "nginx:switch_app", deploy_ref: deploy_ref)

      puts "\n🔎 Verifying..."
      verified = dr_fix_db_cap_run(env, "recovery:verify", deploy_ref: deploy_ref)
      data_tier = dr_fix_db_cap_run(env, "partial:verify_data_tier", deploy_ref: deploy_ref)

      puts ""
      puts "=" * 78
      puts "#{verified && data_tier ? '🟢' : '🔴'} DB primary rebuild #{verified && data_tier ? 'complete and verified' : 'finished with FAILED checks — see above'}"
      puts "=" * 78
      puts "\n📋 Follow-ups:"
      puts "   1. Rebuild the Elasticsearch indexes: rake chewy:reset (on an app server)"
      puts "   2. Sidekiq jobs queued at the moment of failure are GONE."
      puts "   3. Confirm backups resumed: rake \"s3:check_backup_freshness[#{env_name}]\""
      puts "   4. Re-assess: rake \"dr:assess[#{env_name}]\""
      abort "" unless verified && data_tier
    end
  end
end
