# frozen_string_literal: true

# Makes the MySQL replica read-only (read_only + super_read_only, persisted) — for any environment
# with a separate replica.
#
#   rake "ops:replica_read_only[production.us]"             # dry run: checks the replica, prints the plan
#   EXECUTE=1 rake "ops:replica_read_only[production.us]"   # applies, verifies replication still runs
#
# Why and the rest of the picture: lib/replica_read_only.rb. Online, no restart; the app does not
# use the replica (ApplicationRecord reads and writes the primary), and the replication health job
# only reads it, with prevent_writes.
#
# Safety: AWS account guard first; refuses the primary, a box that is not replicating from the
# primary, and unhealthy replication. Reuses the stdin MySQL helpers from mysql_buffer_pool.rake
# (mbp_remote / mbp_mysql_preamble), so the password is never on a command line.

# Read-only state of the replica: its replication status (with field names) and the two flags
RRO_PROBE = <<~'BASH'
  mysql --defaults-extra-file="$f" -e 'SHOW REPLICA STATUS\G' 2>&1 | sed 's/^ *//'
  echo "read_only: $(m 'SELECT @@read_only')"
  echo "super_read_only: $(m 'SELECT @@super_read_only')"
  echo "persisted_super_read_only: $(m "SELECT VARIABLE_VALUE FROM performance_schema.persisted_variables WHERE VARIABLE_NAME = 'super_read_only'")"
BASH

namespace :ops do
  desc "Make the MySQL replica read-only, persisted (dry run; EXECUTE=1 applies)"
  task :replica_read_only, [:env_name] => :environment do |_t, args|
    env_name = args[:env_name].to_s
    abort "❌ Refusing #{env_name.presence || '(no env)'}: only #{ReplicaReadOnly::ENVS.join(', ')}. Nothing touched." unless ReplicaReadOnly.env_allowed?(env_name)
    execute = ENV["EXECUTE"] == "1"
    puts "\n🔒 Replica read-only · #{env_name} · #{execute ? 'EXECUTE' : 'dry run'}"

    # 1. Environment and account: nothing is touched if the AWS keys belong to another account
    env = dr_assess_resolve_env(env_name)
    dr_account_guard!(env)

    # 2. Hosts and credentials
    creds = Rails.application.encrypted(Rails.root.join("config/credentials/#{env_name}.yml.enc"),
                                        key_path: Rails.root.join("config/credentials/#{env_name}.key"))
    primary = creds[:DB_HOST].to_s
    replica = creds[:DB_HOST_REPLICA].to_s

    # 3. The route in
    cap_key = dr_assess_cap_key(env[:deploy_file])
    app_ips = File.read(env[:deploy_file]).scan(Dr::DrillTeardown::SERVER_LINE).flatten.uniq
    app_host = dr_fix_live_app_host(app_ips, cap_key) or abort "❌ No app server in #{env[:deploy_file].basename} answers SSH. Nothing touched."
    abort "❌ KEYNAME is not set in .env.#{env_name}. Nothing touched." if env[:db_keyname].empty?
    ctx = { app_host: app_host, cap_key: cap_key, keyname: env[:db_keyname] }
    preamble = mbp_mysql_preamble(MysqlBufferPool.client_cnf(user: creds[:DB_USER], password: creds[:DB_PASS], host: replica))
    probe = lambda do
      out = mbp_remote(ctx, replica, preamble + RRO_PROBE)
      flags = MysqlBufferPool.parse_probe(out)
      [ReplicaReadOnly.parse_replica_status(out), flags]
    end

    # 4. Check (read-only). The staging-style "replica == primary" case is refused before any SSH.
    if replica.empty? || replica == primary
      plan = ReplicaReadOnly.plan(replica_host: replica, primary_host: primary, status: {}, read_only: nil, super_read_only: nil)
      next puts "ℹ️  #{plan[:reason]}"
    end
    status, flags = probe.call
    puts "🔌 replica #{replica} via app server #{app_host}"
    puts "   replicating from #{status['Source_Host'].presence || '(nothing)'}: IO #{status['Replica_IO_Running'] || '-'}, " \
         "SQL #{status['Replica_SQL_Running'] || '-'}, #{status['Seconds_Behind_Source'] || '-'} s behind"
    puts "   read_only #{flags['read_only']}, super_read_only #{flags['super_read_only']} " \
         "(persisted: #{flags['persisted_super_read_only'].presence || 'not set'})"

    plan = ReplicaReadOnly.plan(replica_host: replica, primary_host: primary, status: status,
                                read_only: flags["read_only"], super_read_only: flags["super_read_only"])
    puts "\n🗺  Plan: #{plan[:status]} — #{plan[:reason]}"
    abort "\n❌ #{plan[:reason]}. Nothing touched." if plan[:status] == :refused
    next puts "\n✅ Nothing to do." if plan[:status] == :unchanged
    next puts "\nℹ️  Dry run — nothing changed. Re-run with EXECUTE=1 to apply." unless execute

    # 5. Apply. read_only first, then super_read_only (which needs read_only); PERSIST so a restart
    #    keeps them. Errors from MySQL are echoed rather than hidden.
    apply = %(echo "set: $(m 'SET PERSIST read_only = ON; SET PERSIST super_read_only = ON')"\n)
    out = mbp_remote(ctx, replica, [preamble, apply].join)
    puts "   #{out.strip}" if out.strip != "set:"

    # 6. Verify: flags on and persisted, and replication still applying the primary's changes
    sleep 3
    status_after, flags_after = probe.call
    ok = flags_after["read_only"] == "1" && flags_after["super_read_only"] == "1" && flags_after["persisted_super_read_only"] == "ON"
    replicating = status_after["Replica_IO_Running"] == "Yes" && status_after["Replica_SQL_Running"] == "Yes"
    puts "\n#{ok ? '✅' : '❌'} read_only #{flags_after['read_only']}, super_read_only #{flags_after['super_read_only']}, persisted #{flags_after['persisted_super_read_only'].presence || 'no'}"
    puts "#{replicating ? '✅' : '❌'} replication IO #{status_after['Replica_IO_Running']}, SQL #{status_after['Replica_SQL_Running']}, " \
         "#{status_after['Seconds_Behind_Source']} s behind"
    puts "\n↩️  Rollback (on #{replica}): SET PERSIST super_read_only = OFF; SET PERSIST read_only = OFF;"
    abort "🔴 Not applied cleanly — see above" unless ok && replicating

    puts "🟢 #{replica} is read-only for every client; replication keeps applying the primary's changes."
  end
end
