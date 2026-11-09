# frozen_string_literal: true

# Installs the data box's Elasticsearch and Redis exporters, turns on mysqld_exporter's memory
# collector, and points Prometheus at them — for any environment.
#
#   rake "observability:data_box_exporters[production.in]"             # dry run: report + plan, changes nothing
#   EXECUTE=1 rake "observability:data_box_exporters[production.in]"   # applies, verifies, prints the rollback
#
# Then provision the alerts and dashboard row to that region's Grafana:
#   GRAFANA_URL=https://graphana.caphive.com bundle exec rake grafana:provision:alert_rules grafana:provision:dashboards
#
# Why: Grafana showed the data box at ~85% memory all week but could not say whether MySQL,
# Elasticsearch or Redis held it (no exporters for the last two). What gets installed, and why
# each choice, is in lib/data_box_exporters.rb.
#
# Safety:
# - The AWS keys must belong to the environment's account (dr_account_guard!), checked first.
# - Purely additive on the data services: Elasticsearch, Redis and MySQL are never restarted.
#   Only mysqld_exporter restarts (for the new collector), and its old unit is kept as a backup
#   and restored automatically if it fails to come back.
# - Release downloads are checked against the release's sha256sums.txt before install.
# - The live Prometheus config is replaced only when it matches the repo copy apart from the new
#   jobs — a live edit nobody committed is never overwritten (the task refuses and says so).
# - Every step is idempotent: re-running reports ALREADY / unchanged.
#
# Reaches the boxes the way the dr:fix tasks do: SSH to an app server with the stage file's key,
# then on to the DB / observability box with the app server's ~/.ssh/<KEYNAME>.pem (the data and
# observability boxes accept SSH only from web-sg).

require "base64"
require "json"
require "shellwords"

# Run a bash script on a box behind the app server. Base64 so the script survives both SSH hops
# untouched; output (stdout + stderr) comes back as one string. LogLevel=ERROR: the first hop to a
# box prints "Warning: Permanently added ... to the list of known hosts", which landed inside the
# Prometheus config read on prod US (2026-11-09) and parsed as an extra YAML key.
def dbx_remote(ctx, host, script, timeout: 30)
  encoded = Base64.strict_encode64(script)
  dr_assess_ssh(ctx[:app_host], ctx[:cap_key],
                "echo #{encoded} | ssh -i ~/.ssh/#{ctx[:keyname]}.pem -o StrictHostKeyChecking=no " \
                "-o ConnectTimeout=10 -o LogLevel=ERROR -o ServerAliveInterval=15 ubuntu@#{host} 'base64 -d | bash -s' 2>&1",
                timeout: timeout)
end

# Ask the observability box's Prometheus itself whether it scrapes the new targets, after two
# scrape intervals. Prints one line per target and returns the failures.
def dbx_verify_targets(ctx, obs_host)
  sleep 35
  query = %(up{job=~"#{DataBoxExporters::NEW_JOBS.join('|')}"})
  raw = dbx_remote(ctx, obs_host, "curl -s http://localhost:9090/api/v1/query --data-urlencode #{Shellwords.escape("query=#{query}")}")
  results = begin
    Array(JSON.parse(raw).dig("data", "result"))
  rescue JSON::ParserError
    []
  end
  # No series at all: the jobs are not loaded yet (or the reload did not take)
  if results.empty?
    puts "   ⚠️  Prometheus returned no #{query} series yet — check Status › Targets in Grafana's Prometheus"
    return []
  end

  results.filter_map do |r|
    up = r.dig("value", 1) == "1"
    puts "   #{up ? '✅' : '❌'} #{r.dig('metric', 'job')} #{r.dig('metric', 'instance')} up=#{r.dig('value', 1)}"
    "Prometheus cannot scrape #{r.dig('metric', 'instance')}" unless up
  end
end

# Read-only snapshot of one box: memory, containers, exporter ports and versions, collector state.
DBX_REPORT_SCRIPT = <<~'BASH'
  echo "hostname: $(hostname)"
  free -m | awk '/^Mem:/ {printf "memory: %d MB total, %d MB available\n", $2, $7}'
  echo "containers: $(sudo docker ps --format '{{.Names}}' 2>/dev/null | tr '\n' ' ')"
  for p in 9104 9114 9121; do
    if ss -tln | grep -q ":$p "; then echo "port $p: listening"; else echo "port $p: -"; fi
  done
  for n in elasticsearch_exporter redis_exporter; do
    if [ -x /usr/local/bin/$n ]; then echo "$n: $(/usr/local/bin/$n --version 2>&1 | head -1)"; fi
  done
  if [ -f /etc/systemd/system/mysqld_exporter.service ]; then
    if grep -q -- '--collect.perf_schema.memory_events' /etc/systemd/system/mysqld_exporter.service; then
      echo "mysqld memory collector: on"
    else
      echo "mysqld memory collector: off"
    fi
  else
    echo "mysqld_exporter: not installed"
  fi
BASH

namespace :observability do
  desc "Install the data box's Elasticsearch + Redis exporters and MySQL memory collector (dry run; EXECUTE=1 applies)"
  task :data_box_exporters, [:env_name] => :environment do |_t, args|
    env_name = args[:env_name].presence or abort 'Usage: rake "observability:data_box_exporters[production.in]"'
    execute = ENV["EXECUTE"] == "1"
    stamp = Time.now.utc.strftime("%Y%m%d%H%M%S")
    puts "\n🔭 Data box exporters · #{env_name} · #{execute ? 'EXECUTE' : 'dry run'}"

    # 1. Environment and account: every value below derives from env_name, and nothing is touched
    #    if the AWS keys in use belong to another account
    env = dr_assess_resolve_env(env_name)
    dr_account_guard!(env)

    # 2. Hosts. The exporters go where the app's own service URLs point (.env.<env_name>); the
    #    memory collector goes on every MySQL box (primary + replica, from the credentials)
    service_hosts = DataBoxExporters::EXPORTERS.index_with { |e| DataBoxExporters.host_of(ENV.fetch(e.service_url_env, nil)) }
    missing = service_hosts.select { |_e, host| host.empty? }.keys.map(&:service_url_env)
    abort "❌ #{missing.join(', ')} not set in .env.#{env_name} — cannot tell where the data box is. Nothing touched." if missing.any?

    creds = Rails.application.encrypted(Rails.root.join("config/credentials/#{env_name}.yml.enc"),
                                        key_path: Rails.root.join("config/credentials/#{env_name}.key"))
    db_hosts = [creds[:DB_HOST], creds[:DB_HOST_REPLICA]].map(&:to_s).reject(&:empty?).uniq
    hosts = (service_hosts.values + db_hosts).uniq

    # 3. The route in: first app server in the stage file that answers SSH
    cap_key = dr_assess_cap_key(env[:deploy_file])
    app_ips = File.read(env[:deploy_file]).scan(Dr::DrillTeardown::SERVER_LINE).flatten.uniq
    app_host = dr_fix_live_app_host(app_ips, cap_key) or abort "❌ No app server in #{env[:deploy_file].basename} answers SSH. Nothing touched."
    abort "❌ KEYNAME is not set in .env.#{env_name} — needed for the hop to the data box. Nothing touched." if env[:db_keyname].empty?
    ctx = { app_host: app_host, cap_key: cap_key, keyname: env[:db_keyname] }
    puts "🔌 via app server #{app_host}"

    # 4. Report (read-only, every run)
    hosts.each do |host|
      roles = []
      roles << "Elasticsearch" if service_hosts[DataBoxExporters::ELASTICSEARCH] == host
      roles << "Redis" if service_hosts[DataBoxExporters::REDIS] == host
      roles << "MySQL #{host == db_hosts.first ? 'primary' : 'replica'}" if db_hosts.include?(host)
      puts "\n📋 #{host} (#{roles.join(', ')})"
      puts dbx_remote(ctx, host, DBX_REPORT_SCRIPT).lines.map { |l| "   #{l}" }.join
    end

    # 5. Prometheus: which repo config this env uses, and whether it may replace the live one
    repo_rel = DataBoxExporters::PROMETHEUS_FILES[env_name]
    prometheus = nil
    if repo_rel
      repo_text = Rails.root.join(repo_rel).read
      # The repo copy must already scrape each exporter where it is being installed
      DataBoxExporters::EXPORTERS.each do |e|
        wanted = "#{service_hosts[e]}:#{e.port}"
        next if DataBoxExporters.targets_for(repo_text, e.job).include?(wanted)

        abort "❌ #{repo_rel} has no #{e.job} job targeting #{wanted} — add it and re-run. Nothing touched."
      end
      obs_host = dr_stack_inventory(env[:pulumi_stack]).dig(:observability, :private_ip).to_s
      abort "❌ No observability box in the Pulumi state for #{env[:pulumi_stack]}. Nothing touched." if obs_host.empty?

      live_text = dbx_remote(ctx, obs_host, "sudo cat #{DataBoxExporters::LIVE_PROMETHEUS_PATH}")
      plan = DataBoxExporters.prometheus_push_plan(live_text: live_text, repo_text: repo_text)
      prometheus = { obs_host: obs_host, repo_rel: repo_rel, repo_text: repo_text, plan: plan }
      puts "\n📋 Prometheus on #{obs_host}: #{plan[:status]} — #{plan[:reason]}"
    else
      puts "\nℹ️  #{env_name} has no Prometheus config in the repo (nothing scrapes it): exporters only."
    end

    # 6. The plan
    puts "\n🗺  Plan"
    DataBoxExporters::EXPORTERS.each do |e|
      puts "   • #{e.name} #{e.version} on #{service_hosts[e]}:#{e.port} (install, or verify if already running)"
    end
    puts "   • mysqld_exporter #{DataBoxExporters::MEMORY_COLLECTOR} on #{db_hosts.join(', ')}"
    puts "   • push #{prometheus[:repo_rel]} to #{prometheus[:obs_host]} and reload Prometheus" if prometheus&.dig(:plan, :status) == :push
    next puts "\nℹ️  Dry run — nothing changed. Re-run with EXECUTE=1 to apply." unless execute

    failures = []
    exporter_failures = []
    rollback = []

    # 7. Exporters: install + prove /metrics serves each one's check metric
    DataBoxExporters::EXPORTERS.each do |e|
      host = service_hosts[e]
      puts "\n🔧 #{e.name} on #{host}"
      out = dbx_remote(ctx, host, DataBoxExporters.install_script(e), timeout: 60)
      puts out.lines.last(8).map { |l| "   #{l}" }.join
      # Installed (verified or not) means there is something to roll back
      rollback << "#{host}: sudo systemctl disable --now #{e.name}" if out.match?(/sha256sums|^(OK|ALREADY|FAILED) #{e.name}/)
      exporter_failures << "#{e.name} on #{host}" unless out.match?(/^(OK|ALREADY) #{e.name}/)
    end
    failures.concat(exporter_failures)

    # 8. MySQL memory collector, one box at a time; the old unit is kept and restored on failure
    unit_path = DataBoxExporters::MYSQLD_UNIT_PATH
    db_hosts.each do |host|
      current = dbx_remote(ctx, host, "sudo cat #{unit_path} 2>/dev/null")
      change = DataBoxExporters.add_memory_collector(current)
      puts "\n🔧 mysqld_exporter on #{host}: #{change[:status]}#{" — #{change[:reason]}" if change[:reason]}"
      next failures << "mysqld_exporter on #{host} (#{change[:reason]})" if change[:status] == :refused

      # Already enabled (a re-run): nothing to change, but still prove the metric is served
      if change[:status] == :unchanged
        served = dbx_remote(ctx, host, "#{DataBoxExporters.metric_served(9104, DataBoxExporters::MEMORY_CHECK_METRIC)} && echo SERVED")
        next puts "   ✅ #{DataBoxExporters::MEMORY_CHECK_METRIC} is served" if served.include?("SERVED")

        puts "   ⚠️  enabled, but no #{DataBoxExporters::MEMORY_CHECK_METRIC} — grant the exporter user SELECT on performance_schema"
        next
      end

      backup = "#{unit_path}.bak-#{stamp}"
      out = dbx_remote(ctx, host, <<~BASH, timeout: 60)
        set -euo pipefail
        sudo cp -p #{unit_path} #{backup}
        echo #{Base64.strict_encode64(change[:text])} | base64 -d | sudo tee #{unit_path} >/dev/null
        sudo systemctl daemon-reload
        sudo systemctl restart mysqld_exporter
        # The new metric within ~20 s means the collector works end to end
        for _ in $(seq 1 10); do
          if #{DataBoxExporters.metric_served(9104, DataBoxExporters::MEMORY_CHECK_METRIC)}; then echo OK; exit 0; fi
          sleep 2
        done
        # Running but no metric: usually the exporter's MySQL user cannot read performance_schema
        if systemctl is-active --quiet mysqld_exporter; then echo NOMETRIC; exit 0; fi
        # Not running at all: put the old unit back so MySQL monitoring is not lost
        sudo cp -p #{backup} #{unit_path}
        sudo systemctl daemon-reload
        sudo systemctl restart mysqld_exporter
        echo "FAILED (old unit restored)"
      BASH
      verdict = out.lines.last.to_s.strip
      puts "   #{verdict}"
      # The new unit is in place for OK and NOMETRIC, so both get a rollback line
      if %w[OK NOMETRIC].include?(verdict)
        rollback << "#{host}: sudo cp -p #{backup} #{unit_path} && sudo systemctl daemon-reload && sudo systemctl restart mysqld_exporter"
      else
        failures << "mysqld_exporter on #{host}"
      end
      puts "   ⚠️  running, but no #{DataBoxExporters::MEMORY_CHECK_METRIC} — grant the exporter user SELECT on performance_schema" if verdict == "NOMETRIC"
    end

    # 9. Prometheus, only once every exporter is up (otherwise it would scrape a dead target)
    if prometheus && exporter_failures.any?
      failures << "Prometheus config not pushed: an exporter failed to install"
    elsif prometheus
      case prometheus[:plan][:status]
      when :refused
        failures << "Prometheus config not pushed: #{prometheus[:plan][:reason]}"
      when :push
        live = DataBoxExporters::LIVE_PROMETHEUS_PATH
        backup = "#{live}.bak-#{stamp}"
        puts "\n🔧 Prometheus on #{prometheus[:obs_host]}"
        out = dbx_remote(ctx, prometheus[:obs_host], <<~BASH, timeout: 60)
          set -euo pipefail
          # Write beside the live file so relative paths in it resolve the same way
          echo #{Base64.strict_encode64(prometheus[:repo_text])} | base64 -d | sudo tee #{live}.new >/dev/null
          # Validate BEFORE touching the live file. --syntax-only where promtool has it: a full check
          # also demands every rule_files entry exist, and the live config's alerts.yml does not
          # (prod alerting is in Grafana; Prometheus skips a rule_files pattern that matches nothing),
          # so a full check rejects the very config Prometheus runs today (prod IN, 2026-11-09)
          if command -v promtool >/dev/null; then
            mode=""
            if promtool check config --help 2>&1 | grep -- '--syntax-only' >/dev/null; then mode="--syntax-only"; fi
            if ! sudo promtool check config $mode #{live}.new; then
              sudo rm -f #{live}.new
              echo "CHECK_FAILED"
              exit 0
            fi
          fi
          sudo cp -p #{live} #{backup}
          sudo mv #{live}.new #{live}
          sudo chown prometheus:prometheus #{live}
          sudo systemctl reload prometheus 2>/dev/null || sudo systemctl restart prometheus
          sleep 2
          systemctl is-active prometheus || true
        BASH
        state = out.lines.last.to_s.strip
        if state == "CHECK_FAILED"
          # Nothing was swapped: the live config and the running Prometheus are as they were
          puts out.lines.last(6).map { |l| "   #{l}" }.join
          failures << "Prometheus config rejected by promtool — live config on #{prometheus[:obs_host]} untouched (see above)"
        elsif state == "active"
          puts "   prometheus is active"
          rollback << "#{prometheus[:obs_host]}: sudo cp -p #{backup} #{live} && sudo systemctl reload prometheus"
          failures.concat(dbx_verify_targets(ctx, prometheus[:obs_host]))
        else
          puts out.lines.last(6).map { |l| "   #{l}" }.join
          failures << "Prometheus on #{prometheus[:obs_host]} is #{state} after the push — restore: sudo cp -p #{backup} #{live} && sudo systemctl restart prometheus"
        end
      end
    end

    # 10. Outcome, rollback, next step
    puts "\n#{'=' * 78}"
    puts "↩️  Rollback, if needed:"
    rollback.each { |r| puts "   #{r}" }
    if failures.any?
      puts "🔴 Not everything applied:"
      failures.each { |f| puts "   • #{f}" }
      abort ""
    end
    puts "🟢 Exporters live on #{env_name}."
    if prometheus
      grafana = env_name == "production.us" ? "https://graphana.caphive.us" : "https://graphana.caphive.com"
      puts "   Next: GRAFANA_URL=#{grafana} bundle exec rake grafana:provision:alert_rules grafana:provision:dashboards"
    end
  end
end
