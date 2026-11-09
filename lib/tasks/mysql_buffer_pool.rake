# frozen_string_literal: true

# Grows MySQL's InnoDB buffer pool online on the DB boxes (replica first, then primary), and makes
# it survive a restart — staging first, then production.
#
#   rake "ops:mysql_buffer_pool[staging.in]"             # dry run: measures, prints the working, changes nothing
#   EXECUTE=1 rake "ops:mysql_buffer_pool[staging.in]"   # resizes, waits for it, verifies, prints the rollback
#
# Sizing rule and why: lib/mysql_buffer_pool.rb. In short: the pool gets what the box has left once
# Elasticsearch and Redis are at their caps, mysqld's other memory has 25% head-room and the OS keeps
# 1.5 GB — but never more than 1.25 x the dataset, and never less than today.
#
# How: `SET PERSIST innodb_buffer_pool_size` — MySQL 8 resizes the pool online, chunk by chunk,
# without a restart, and writes the value to mysqld-auto.cnf so a restart keeps it. Growing does
# not block queries for long, but do production in a quiet window.
#
# Safety:
# - AWS account guard first (dr_account_guard!); staging / production only.
# - The MySQL password travels over SSH stdin into a 0600 temp file on the box and is removed at
#   exit — never on a command line (no `ps` or shell history exposure, on the app box either).
# - Refuses a box with a container whose memory is not capped (the budget would be fiction), a box
#   already past its budget, and MySQL older than 8.0 (no SET PERSIST).
# - Replica before primary: a surprise shows up on the box that is not serving writes.

require "net/ssh"

# Run a bash script on a box behind the app server, sending the script on STDIN (not as an
# argument like dbx_remote), because this one carries the MySQL password. Keepalives on both hops:
# the resize wait can be silent for minutes.
def mbp_remote(ctx, host, script, timeout: 30)
  output = +""
  inner = "ssh -i ~/.ssh/#{ctx[:keyname]}.pem -o StrictHostKeyChecking=no -o ConnectTimeout=10 " \
          "-o LogLevel=ERROR -o ServerAliveInterval=15 ubuntu@#{host} 'bash -s' 2>&1"
  Net::SSH.start(ctx[:app_host], "ubuntu", keys: [ctx[:cap_key]], timeout: timeout, verify_host_key: :never,
                                           keepalive: true, keepalive_interval: 15) do |ssh|
    ssh.open_channel do |channel|
      channel.exec(inner) do |ch, ok|
        raise "could not start a shell on #{host}" unless ok

        ch.on_data { |_c, data| output << data }
        ch.on_extended_data { |_c, _type, data| output << data }
        ch.send_data(script)
        ch.eof!
      end
    end
    ssh.loop
  end
  output
end

# The shell preamble every MySQL script starts with: a 0600 option file holding the credentials,
# removed on exit, and m() to run one statement through it.
def mbp_mysql_preamble(cnf)
  <<~BASH
    set -uo pipefail
    f=$(mktemp)
    chmod 600 "$f"
    trap 'rm -f "$f"' EXIT
    cat > "$f" <<'CNF_EOF'
    #{cnf}CNF_EOF
    m() { mysql --defaults-extra-file="$f" -NBe "$1" 2>&1; }
  BASH
end

# Bytes (Integer or the probe's String) as "1234 MB"
def mbp_mb(bytes)
  MysqlBufferPool.mb(bytes.to_i)
end

# Read-only snapshot of one MySQL box, as "key: value" lines (MysqlBufferPool.parse_probe).
MBP_PROBE = <<~'BASH'
  echo "version: $(m 'SELECT @@version')"
  echo "pool: $(m 'SELECT @@innodb_buffer_pool_size')"
  echo "chunk: $(m 'SELECT @@innodb_buffer_pool_chunk_size')"
  echo "instances: $(m 'SELECT @@innodb_buffer_pool_instances')"
  echo "dataset: $(m "SELECT COALESCE(SUM(data_length + index_length), 0) FROM information_schema.tables WHERE engine = 'InnoDB'")"
  echo "reads: $(m "SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads'")"
  echo "requests: $(m "SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests'")"
  echo "persisted: $(m "SELECT VARIABLE_VALUE FROM performance_schema.persisted_variables WHERE VARIABLE_NAME = 'innodb_buffer_pool_size'")"
  pid=$(pidof mysqld | awk '{print $1}')
  echo "rss: $(( $(awk '/^VmRSS/ {print $2}' /proc/$pid/status) * 1024 ))"
  echo "total: $(( $(awk '/^MemTotal/ {print $2}' /proc/meminfo) * 1024 ))"
  echo "available: $(( $(awk '/^MemAvailable/ {print $2}' /proc/meminfo) * 1024 ))"
  echo "containers: $(sudo docker ps --format '{{.Names}}' 2>/dev/null | tr '\n' ' ')"
  echo "es_cap: $(sudo docker inspect elasticsearch --format '{{.HostConfig.Memory}}' 2>/dev/null || echo 0)"
  echo "redis_max: $(sudo docker exec redis-stack-server redis-cli CONFIG GET maxmemory 2>/dev/null | tail -1 || echo 0)"
BASH

namespace :ops do
  desc "Grow MySQL's InnoDB buffer pool online, replica first (dry run; EXECUTE=1 applies)"
  task :mysql_buffer_pool, [:env_name] => :environment do |_t, args|
    env_name = args[:env_name].to_s
    abort "❌ Refusing #{env_name.presence || '(no env)'}: only #{MysqlBufferPool::ENVS.join(', ')}. Nothing touched." unless MysqlBufferPool.env_allowed?(env_name)
    execute = ENV["EXECUTE"] == "1"
    puts "\n🗄  MySQL buffer pool · #{env_name} · #{execute ? 'EXECUTE' : 'dry run'}"

    # 1. Environment and account: nothing is touched if the AWS keys belong to another account
    env = dr_assess_resolve_env(env_name)
    dr_account_guard!(env)

    # 2. The MySQL boxes and the credentials (DB_USER is root, which holds SYSTEM_VARIABLES_ADMIN).
    #    Replica first; staging's "replica" is the primary itself.
    creds = Rails.application.encrypted(Rails.root.join("config/credentials/#{env_name}.yml.enc"),
                                        key_path: Rails.root.join("config/credentials/#{env_name}.key"))
    primary = creds[:DB_HOST].to_s
    replica = creds[:DB_HOST_REPLICA].to_s
    abort "❌ DB_HOST missing in the #{env_name} credentials. Nothing touched." if primary.empty?
    hosts = [replica, primary].reject(&:empty?).uniq

    # 3. The route in: first app server in the stage file that answers SSH
    cap_key = dr_assess_cap_key(env[:deploy_file])
    app_ips = File.read(env[:deploy_file]).scan(Dr::DrillTeardown::SERVER_LINE).flatten.uniq
    app_host = dr_fix_live_app_host(app_ips, cap_key) or abort "❌ No app server in #{env[:deploy_file].basename} answers SSH. Nothing touched."
    abort "❌ KEYNAME is not set in .env.#{env_name}. Nothing touched." if env[:db_keyname].empty?
    ctx = { app_host: app_host, cap_key: cap_key, keyname: env[:db_keyname] }
    # Each box is reached on its own address, the way the app servers reach it
    preamble = ->(host) { mbp_mysql_preamble(MysqlBufferPool.client_cnf(user: creds[:DB_USER], password: creds[:DB_PASS], host: host)) }
    puts "🔌 via app server #{app_host}"

    # 4. Measure and plan each box (read-only)
    plans = hosts.map do |host|
      role = host == primary ? "primary" : "replica"
      probe = MysqlBufferPool.parse_probe(mbp_remote(ctx, host, preamble.call(host) + MBP_PROBE))
      puts "\n📋 #{host} (#{role}#{' + data box' if probe['containers'].to_s.strip.present?})"

      version = probe["version"].to_s
      unless version.match?(/\A(8|9)\./)
        puts "   ⛔ MySQL version #{version.presence || '(no answer)'} — need 8.0+ for an online, persisted resize"
        next { host: host, role: role, status: :refused, reason: "MySQL #{version.presence || 'unreachable'}" }
      end

      containers = probe["containers"].to_s.split
      reserve = MysqlBufferPool.reserved(containers: containers, es_cap_bytes: probe["es_cap"].to_i,
                                         redis_maxmemory_bytes: probe["redis_max"].to_i)
      unit = probe["chunk"].to_i * [probe["instances"].to_i, 1].max
      puts "   MySQL #{version}: pool #{mbp_mb(probe['pool'])} (#{probe['persisted'].present? ? "persisted #{mbp_mb(probe['persisted'])}" : 'not persisted'}), " \
           "resize unit #{mbp_mb(unit)}, mysqld resident #{mbp_mb(probe['rss'])}"
      puts "   dataset #{mbp_mb(probe['dataset'])}; reads from disk #{MysqlBufferPool.miss_percent(reads: probe['reads'], requests: probe['requests'])}% since start"
      puts "   box #{mbp_mb(probe['total'])}, #{mbp_mb(probe['available'])} available; containers: #{containers.join(', ').presence || 'none'}"

      if reserve[:refusal]
        puts "   ⛔ #{reserve[:refusal]}"
        next { host: host, role: role, status: :refused, reason: reserve[:refusal] }
      end

      plan = MysqlBufferPool.plan(total_bytes: probe["total"].to_i, reserved_bytes: reserve[:bytes],
                                  mysqld_rss_bytes: probe["rss"].to_i, current_pool_bytes: probe["pool"].to_i,
                                  dataset_bytes: probe["dataset"].to_i, unit_bytes: unit)
      # The working, so the number can be checked by hand
      puts "   room = #{mbp_mb(probe['total'])} RAM - #{mbp_mb(reserve[:bytes])} (ES cap + Redis maxmemory) - " \
           "1.25 x #{mbp_mb(plan[:non_pool])} (mysqld outside the pool) - 1536 MB (OS) = #{mbp_mb(plan[:room])}"
      puts "   cap  = 1.25 x #{mbp_mb(probe['dataset'])} dataset = #{mbp_mb(plan[:dataset_cap])}"
      verdict = case plan[:status]
                when :grow then "→ grow #{mbp_mb(probe['pool'])} → #{mbp_mb(plan[:target])}"
                when :unchanged then "→ unchanged: #{plan[:reason]}"
                else "⛔ #{plan[:reason]}"
                end
      puts "   #{verdict}"
      plan.merge(host: host, role: role, current: probe["pool"].to_i)
    end

    puts "\n🗺  Plan: #{plans.map { |p| "#{p[:role]} #{p[:status] == :grow ? "#{mbp_mb(p[:current])} → #{mbp_mb(p[:target])}" : p[:status]}" }.join('; ')}"
    next puts "\nℹ️  Dry run — nothing changed. Re-run with EXECUTE=1 to apply." unless execute

    rollback = []
    failures = plans.select { |p| p[:status] == :refused }.map { |p| "#{p[:role]} #{p[:host]}: #{p[:reason]}" }

    # 5. Resize, replica first. A failed box stops the run before the next one is touched.
    plans.select { |p| p[:status] == :grow }.each do |p|
      puts "\n🔧 #{p[:role]} #{p[:host]}: SET PERSIST innodb_buffer_pool_size = #{p[:target]} (#{mbp_mb(p[:target])})"
      out = mbp_remote(ctx, p[:host], preamble.call(p[:host]) + <<~BASH, timeout: 30)
        # Any error from the statement itself is echoed, so a refusal (privileges, ...) is visible
        echo "set: $(m 'SET PERSIST innodb_buffer_pool_size = #{p[:target]}')"
        # MySQL resizes in the background, chunk by chunk: wait until it says so, up to 10 minutes
        for _ in $(seq 1 120); do
          size=$(m 'SELECT @@innodb_buffer_pool_size')
          code=$(m "SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_resize_status_code'")
          if [ "$size" = "#{p[:target]}" ] && [ "${code:-0}" = "0" ]; then break; fi
          if [ "$code" = "7" ]; then echo "RESIZE_FAILED"; break; fi
          sleep 5
        done
        echo "size: $(m 'SELECT @@innodb_buffer_pool_size')"
        echo "persisted: $(m "SELECT VARIABLE_VALUE FROM performance_schema.persisted_variables WHERE VARIABLE_NAME = 'innodb_buffer_pool_size'")"
        echo "status: $(m "SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_resize_status'")"
      BASH
      after = MysqlBufferPool.parse_probe(out)
      puts "   #{after['status']}"
      if after["size"].to_i == p[:target] && after["persisted"].to_i == p[:target]
        puts "✅ #{p[:role]} #{p[:host]}: pool #{mbp_mb(p[:target])}, persisted (survives a restart)"
        rollback << "#{p[:role]} #{p[:host]}: mysql -e 'SET PERSIST innodb_buffer_pool_size = #{p[:current]}'"
      else
        failures << "#{p[:role]} #{p[:host]}: pool reads #{after['size'].presence || '?'}, persisted #{after['persisted'].presence || 'none'} " \
                    "(wanted #{p[:target]})#{' — resize failed, see the MySQL error log' if out.include?('RESIZE_FAILED')}" \
                    "#{" — MySQL said: #{after['set']}" if after['set'].present?}"
        break # do not go on to the primary after a failed replica
      end
    end

    # 6. Outcome
    puts "\n#{'=' * 78}"
    puts "↩️  Rollback, if needed (on each box, as root):"
    rollback.each { |r| puts "   #{r}" }
    if failures.any?
      puts "🔴 Not everything applied:"
      failures.each { |f| puts "   • #{f}" }
      abort ""
    end
    puts "🟢 Buffer pool resized on #{env_name}. Watch mysqld memory and the InnoDB miss rate for a day."
  end
end
