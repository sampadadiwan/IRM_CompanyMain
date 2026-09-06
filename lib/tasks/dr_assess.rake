#  dr:assess — component-level incident triage (Phase 1 of component recovery)
# =============================================================================
# The three DR tools answer three different questions:
#
#   aws:dr_readiness  — BEFORE a disaster: "could we recover if we had to?"
#   dr:assess         — DURING an incident: "which component is actually broken,
#                       and what is the smallest thing that fixes it?"   <-- this
#   dr:verify         — AFTER a recovery:  "is the stack serving again?"
#
# Full DR (aws:setup_infra) rebuilds EVERYTHING in another region. Most real
# incidents are one component: a dead app server, a stopped container, a lost DB
# box. Rebuilding the world for those is slower and riskier than repairing the
# one broken thing, so this task walks every component and recommends the
# cheapest rung of the repair ladder that fits the evidence.
#
# READ-ONLY, with one deliberate exception: the "trivial rung" is auto-fixed —
# a dead ES/Redis container or a stopped sidekiq on an otherwise HEALTHY host is
# restarted in place. That mirrors dr:verify, which already starts a downed
# prometheus_exporter rather than merely reporting it. Nothing else is touched:
# no pulumi, no deploy, no restore, no MySQL, no nginx config. Set
# ASSESS_READ_ONLY=true to suppress even that.
#
#   rake "dr:assess[production.in]"
#   ASSESS_READ_ONLY=true rake "dr:assess[staging.in]"
#
# Exits non-zero if any component is DOWN, so it can gate a script.
# =============================================================================

require_relative "aws_utils"

include AwsUtils # latest_ami / pulumi_stack_output / update_* helpers

# Environments this tool supports. staging.us is deliberately absent — that
# environment does not exist despite having files in the repo.
#
# `account` is the AWS account that owns the environment: production and staging
# are SEPARATE AWS accounts (see docs/security/security_event_review_methodology.md).
# Both production variants (in/us) live in the same production account and are
# separated by region, not by account.
DR_ASSESS_ENVIRONMENTS = {
  "production.in" => { stack: "production", variant: "in", account: "825199636520" },
  "production.us" => { stack: "production", variant: "us", account: "825199636520" },
  "staging.in" => { stack: "staging", variant: "in", account: "174852986003" }
}.freeze

# Components are reported in serving order — edge first, then the boxes that
# serve, then the data they serve from, then the plumbing under all of it.
# Nothing depends on this order; it exists so the scorecard reads top-down.
DR_ASSESS_ICONS = { ok: "✅", warn: "⚠️ ", fail: "❌", fixed: "🔧" }.freeze

# Resolve an env_name ("production.in") into everything the rest of the task
# needs. Deriving all of it from ONE argument is deliberate: the existing DR
# tasks take [stack, variant, region, env_name] positionally, and a mismatched
# stack/region pair is exactly the kind of typo an incident produces.
def dr_assess_resolve_env(env_name)
  cfg = DR_ASSESS_ENVIRONMENTS[env_name]
  unless cfg
    raise "Unknown environment '#{env_name}'. Supported: #{DR_ASSESS_ENVIRONMENTS.keys.join(', ')}"
  end

  # .env.<env_name> + credentials must be loaded BEFORE anything reads AWS_REGION
  Rake::Task["aws:environment"].reenable
  Rake::Task["aws:environment"].invoke(env_name)

  region = ENV["AWS_REGION"].to_s
  raise "AWS_REGION not set in .env.#{env_name}" if region.empty?

  # Confirm we will read this env's state, not another env's, and make the
  # passphrase available before anything shells out to pulumi. See
  # ensure_pulumi_backend! in aws_utils.rb.
  ensure_pulumi_backend!(env_name)

  cfg.merge(
    env_name: env_name,
    region: region,
    # Pulumi stack naming is <stack>-<region>; the variant never appears in it
    # (the region already implies the variant). See setup_pulumi_config.
    pulumi_stack: "#{cfg[:stack]}-#{region}",
    cap_stage: "#{cfg[:stack]}_#{cfg[:variant]}",
    deploy_file: Rails.root.join("config", "deploy", "#{cfg[:stack]}_#{cfg[:variant]}.rb"),
    # KEYNAME is the key the APP SERVERS use to reach the DB boxes; the cap key
    # below is the one THIS machine uses to reach the app servers. They are
    # frequently different (production.in: caphive vs caphive2) — that is not a
    # misconfiguration, it is two different SSH hops.
    db_keyname: ENV["KEYNAME"].to_s,
    app_host_header: ENV["HOST"].to_s.sub(%r{\Ahttps?://}, "").split("/").first.to_s,
    website_hosts: ENV["WEBSITE_HOSTS"].to_s.split(",").map(&:strip).reject(&:empty?),
    app_bucket: ENV["AWS_S3_BUCKET"].to_s
  )
end

# The pem this machine uses to reach the app servers, read from the stage file
# so there is exactly one source of truth (cap and this task cannot disagree).
def dr_assess_cap_key(deploy_file)
  content = File.read(deploy_file)
  # Matches both spellings used in the stage files:
  #   set :ssh_options, keys: "~/.ssh/x.pem", ...
  #   set :ssh_options, { keys: ['~/.ssh/x.pem'], ... }
  match = content.match(/keys:\s*\[?\s*['"]([^'"]+\.pem)['"]/)
  raise "Could not find an ssh key in #{deploy_file}" unless match

  File.expand_path(match[1])
end

# Hosts Capistrano would actually deploy to, parsed from the stage file.
# Returns [{ip:, roles:, lb_only:}] — lb_only marks `... if ENV["LB"]` lines,
# which are invisible to cap unless LB=true is set.
def dr_assess_stage_hosts(deploy_file)
  File.readlines(deploy_file).filter_map do |line|
    next if line.strip.start_with?("#") # commented-out spares are not hosts

    match = line.match(/^server\s+["']([^"']+)["'].*roles:\s*%w\[([^\]]+)\]/)
    next unless match

    { ip: match[1], roles: match[2].split, lb_only: line.include?('ENV["LB"]') }
  end
end

# Run a command on a remote host over SSH and return its stdout, trimmed.
# Raises on connection failure — callers decide whether that means DOWN.
# verify_host_key: :never matches the stage files' own ssh_options; replaced
# boxes routinely reuse an IP with a fresh host key.
def dr_assess_ssh(host, key_path, command, timeout: 15)
  require "net/ssh"
  Net::SSH.start(host, "ubuntu", keys: [key_path], timeout: timeout, verify_host_key: :never) do |ssh|
    return ssh.exec!(command).to_s.strip
  end
end

# Reach a DB box, which accepts SSH only from the app servers, by hopping
# through one. This is why assess needs at least one healthy app server before
# it can say anything about the data tier — the same constraint that makes
# db:restore_all_remote run from an app server rather than a laptop.
def dr_assess_ssh_via_app(app_host, app_key, db_host, db_keyname, command)
  inner = command.gsub("'", %q('"'"')) # survive one level of single-quoting
  dr_assess_ssh(app_host, app_key,
                "ssh -i ~/.ssh/#{db_keyname}.pem -o StrictHostKeyChecking=no " \
                "-o ConnectTimeout=10 ubuntu@#{db_host} '#{inner}'")
end

# The AWS CLI, not the SDK, for services whose gem this app does not bundle
# (elbv2, ssm, sts, route53 — see Gemfile: only ec2/s3/iam/sns/wafv2 are here).
# It also reads the SHELL's credentials rather than the credentials file, which
# is exactly what the account guard below cross-checks.
def dr_assess_aws(*args)
  require "open3"
  out, err, status = Open3.capture3("aws", *args.map(&:to_s))
  [status.success? ? out.strip : nil, err.to_s.strip.lines.first.to_s.strip]
end

# Every resource in a Pulumi stack's state, as plain hashes. `pulumi stack
# export` carries the URNs a targeted update needs and the live attribute values.
def dr_fix_stack_resources(pulumi_stack)
  require "json"
  require "open3"
  out, err, status = Open3.capture3("pulumi stack export --stack #{pulumi_stack}", chdir: "../IRM-Infra")
  raise "pulumi stack export failed for #{pulumi_stack}: #{err.to_s.lines.first}" unless status.success?

  JSON.parse(out).dig("deployment", "resources") || []
end

# Live inventory of a stack, built from Pulumi STATE rather than its exported
# outputs.
#
# WHY NOT THE OUTPUTS: a stack's outputs are whatever the version of outputs.py
# that ran at its last `pulumi up` chose to export. No live stack has been upped
# since `alb` (and OBSERVABILITY_HOST, and security_groups) were added to
# create_output, so NONE of them exports an ALB — reading the ALB from there
# reports "no ALB" for an environment whose ALB is serving traffic. Worse,
# staging-ap-south-1's outputs disagree with its own state about how many app
# servers exist. State always describes the resources Pulumi currently manages.
#
# Resources flagged `delete: true` are pending-deletion leftovers from an
# interrupted update (staging carries a stopped observability box in exactly
# that state) and are skipped everywhere: targeting one would aim a repair at a
# resource that is on its way out of the stack.
def dr_stack_inventory(pulumi_stack)
  resources = dr_fix_stack_resources(pulumi_stack)

  live_instances = resources.select do |r|
    r["type"] == "aws:ec2/instance:Instance" && !r["delete"]
  end

  # Resource names come from compute.py: web-server-<region>-<stack>-<tag>-<i>,
  # db-<region>-<stack>, db-replica-<region>-<stack>, observability-<region>-<stack>.
  # The db primary pattern must exclude db-replica-*, which also starts "db-".
  by_name = lambda do |pattern|
    live_instances.select { |r| r["urn"].to_s.split("::").last.to_s.match?(pattern) }
  end

  describe = lambda do |r|
    next nil unless r

    {
      urn: r["urn"],
      id: r.dig("outputs", "id"),
      public_ip: r.dig("outputs", "publicIp"),
      private_ip: r.dig("outputs", "privateIp"),
      state: r.dig("outputs", "instanceState")
    }
  end

  alb = resources.find { |r| r["type"] == "aws:lb/loadBalancer:LoadBalancer" && !r["delete"] }

  {
    app_servers: by_name.call(/\Aweb-server-/).map { |r| describe.call(r) },
    db_primary: describe.call(by_name.call(/\Adb-(?!replica-)/).first),
    db_replica: describe.call(by_name.call(/\Adb-replica-/).first),
    observability: describe.call(by_name.call(/\Aobservability-/).first),
    alb: alb && {
      urn: alb["urn"],
      arn: alb.dig("outputs", "arn"),
      dns_name: alb.dig("outputs", "dnsName"),
      zone_id: alb.dig("outputs", "zoneId")
    },
    # Kept so callers can report state-vs-output disagreement rather than
    # silently preferring one — the disagreement is itself a finding.
    pending_delete: resources.count { |r| r["delete"] }
  }
end

# Abort unless BOTH credential paths point at the account that owns this
# environment. Extracted so every dr:fix task can call it before touching
# anything — the most dangerous multi-environment mistake is repairing with the
# wrong account's keys exported, and it is invisible in the terminal.
#
# The two paths are genuinely independent: the SDK uses AWS_ACCESS_KEY_ID from
# the encrypted credentials file (loaded by aws:environment), while every `aws`
# CLI subprocess and pulumi use whatever is exported in the operator's shell.
# Returns [cli_account, cli_error, sdk_account] for the caller to report.
def dr_account_guard!(env)
  expected = ENV["EXPECTED_AWS_ACCOUNT"] || env[:account]

  cli_account, cli_err = dr_assess_aws("sts", "get-caller-identity", "--query", "Account", "--output", "text")
  # describe_vpcs' owner_id is the cheapest way to learn the account behind the
  # SDK credentials without bundling aws-sdk-sts just for this.
  sdk_account = begin
    Aws::EC2::Client.new(region: env[:region]).describe_vpcs(max_results: 5).vpcs.first&.owner_id
  rescue StandardError
    nil
  end

  if cli_account && cli_account != expected
    abort "\n❌ ABORT: your shell's AWS credentials are account #{cli_account}, but #{env[:env_name]} " \
          "lives in #{expected}.\n   Export the right account's keys before assessing or repairing " \
          "#{env[:env_name]}.\n   (Override intentionally with EXPECTED_AWS_ACCOUNT=#{cli_account}.)"
  end

  if sdk_account && sdk_account != expected
    abort "\n❌ ABORT: the credentials in config/credentials/#{env[:env_name]}.yml.enc belong to account " \
          "#{sdk_account}, but #{env[:env_name]} lives in #{expected}."
  end

  [cli_account, cli_err, sdk_account]
end

namespace :dr do
  desc "Assess every component of a live environment and recommend the smallest repair (auto-fixes trivial rungs)"
  task :assess, [:env_name] => :environment do |_t, args|
    require "json"
    require "resolv"

    env_name = args[:env_name] or
      raise "Usage: rake \"dr:assess[production.in]\" — supported: #{DR_ASSESS_ENVIRONMENTS.keys.join(', ')}"

    env = dr_assess_resolve_env(env_name)
    auto_fix = ENV["ASSESS_READ_ONLY"] != "true"

    results = [] # [{component:, host:, status:, detail:, fix:}]

    # Record + print one check. `fix` is the command the operator should run —
    # collected and re-printed as a ranked plan at the end, so the recommendation
    # survives a long scrollback.
    check = lambda do |component, status, detail = nil, host: nil, fix: nil|
      results << { component: component, host: host, status: status, detail: detail, fix: fix }
      label = host ? "#{component} (#{host})" : component
      puts "#{DR_ASSESS_ICONS[status]} #{label}#{detail.to_s.empty? ? '' : " — #{detail}"}"
    end

    # One crashed check must not cost us the rest of the scorecard: mid-incident
    # the full picture matters more than a clean stack trace.
    guarded = lambda do |component, host: nil, &body|
      body.call
    rescue StandardError => e
      check.call(component, :fail, "#{e.class}: #{e.message.to_s.lines.first.to_s.strip}", host: host)
    end

    puts ""
    puts "=" * 78
    puts "🩺  DR ASSESS · #{env_name} · #{env[:stack]}/#{env[:variant]} · #{env[:region]}"
    puts "    Pulumi stack: #{env[:pulumi_stack]}   ·   cap stage: #{env[:cap_stage]}"
    puts "    Mode: #{auto_fix ? 'assess + auto-fix trivial rung' : 'READ-ONLY (ASSESS_READ_ONLY=true)'}"
    puts "=" * 78
    puts ""

    # ---------------------------------------------------------------------
    # 0. Preflight — local files, then the account guard
    # ---------------------------------------------------------------------
    puts "🔎 Preflight"

    # Kept in its OWN guarded block: dr_assess_cap_key raises when the stage
    # file is missing or has no `keys:` line, and a raise inside the file-
    # existence loop below would abort it before a single check was recorded —
    # turning "your credentials key is missing" into one opaque failure.
    cap_key = nil
    guarded.call("Local: cap ssh key") do
      cap_key = dr_assess_cap_key(env[:deploy_file])
      check.call("Local: cap ssh key #{File.basename(cap_key)}", File.exist?(cap_key) ? :ok : :fail,
                 File.exist?(cap_key) ? nil : "missing: #{cap_key}")
    end

    guarded.call("Local prerequisites") do
      {
        ".env.#{env_name}" => Rails.root.join(".env.#{env_name}"),
        "credentials #{env_name}.yml.enc" => Rails.root.join("config/credentials/#{env_name}.yml.enc"),
        "credentials #{env_name}.key" => Rails.root.join("config/credentials/#{env_name}.key"),
        "sibling ../IRM-Infra checkout" => Rails.root.join("../IRM-Infra")
      }.each do |label, path|
        check.call("Local: #{label}", File.exist?(path) ? :ok : :fail, File.exist?(path) ? nil : "missing: #{path}")
      end
    end

    # Aborts outright on a wrong-account mismatch (see dr_account_guard!); the
    # reporting below only covers the cases it lets through.
    guarded.call("AWS account guard") do
      cli_account, cli_err, sdk_account = dr_account_guard!(env)

      check.call("AWS account (shell/CLI)", cli_account ? :ok : :fail,
                 cli_account || "sts get-caller-identity failed: #{cli_err} — are the env's keys exported?")
      check.call("AWS account (credentials file)", sdk_account ? :ok : :warn,
                 sdk_account || "could not determine — EC2 describe_vpcs failed")
    end

    # ---------------------------------------------------------------------
    # 1. Inventory — what Pulumi owns vs what Capistrano deploys to
    # ---------------------------------------------------------------------
    puts "\n🔎 Inventory"

    inventory = nil
    app_ips = []
    db_host = nil
    db_replica = nil
    obs_host = nil
    alb_dns = nil
    alb_arn = nil

    # Read from STATE, not the stack's exported outputs — see dr_stack_inventory
    # for why (no live stack exports an ALB, and staging's outputs contradict its
    # own state).
    guarded.call("Pulumi inventory") do
      inventory = dr_stack_inventory(env[:pulumi_stack])
      app_ips = inventory[:app_servers].filter_map { |i| i[:public_ip] }
      db_host = inventory.dig(:db_primary, :private_ip)
      db_replica = inventory.dig(:db_replica, :private_ip)
      obs_host = inventory.dig(:observability, :private_ip)
      alb_dns = inventory.dig(:alb, :dns_name)
      alb_arn = inventory.dig(:alb, :arn)
      check.call("Pulumi stack #{env[:pulumi_stack]}", :ok,
                 "#{app_ips.size} app server(s), DB #{db_host || 'none'}, replica #{db_replica || 'none'} (from state)")

      # Pending-deletion leftovers are skipped by every lookup, but their
      # presence means an update was interrupted and is worth knowing about.
      if inventory[:pending_delete].positive?
        check.call("Pulumi state cleanliness", :warn,
                   "#{inventory[:pending_delete]} resource(s) flagged for deletion are still in the state — " \
                   "leftovers from an interrupted update; they are ignored here but should be reconciled")
      end
    end

    # The exported outputs are read ONLY to report disagreement with the state.
    # Nothing depends on them: they are stale on every stack today, and the
    # disagreement is itself a finding worth surfacing during an incident.
    guarded.call("Pulumi outputs ↔ state") do
      output = begin
        pulumi_stack_output(env[:pulumi_stack])
      rescue StandardError
        nil
      end

      if output.nil?
        check.call("Pulumi outputs ↔ state", :warn,
                   "stack exports no usable outputs — aws:dns_cutover and aws:dr_verify_edge read " \
                   "output['alb'] and would FAIL on this stack until the next pulumi up")
      else
        output_ips = Array(output.dig("public_ips", "AppServers")).flatten.compact
        notes = []
        notes << "outputs list #{output_ips.size} app server(s), state has #{app_ips.size}" if output_ips.sort != app_ips.sort
        notes << "outputs carry no 'alb' (aws:dns_cutover / aws:dr_verify_edge read it and would fail)" unless output.key?("alb")
        notes << "outputs carry no OBSERVABILITY_HOST" unless output.dig("private_ips", "OBSERVABILITY_HOST")
        if notes.empty?
          check.call("Pulumi outputs ↔ state", :ok, "outputs agree with state")
        else
          check.call("Pulumi outputs ↔ state", :warn,
                     "#{notes.join('; ')} — the outputs predate the current outputs.py; " \
                     "this assessment uses STATE and is unaffected")
        end
      end
    end

    # A repair aimed at a box Capistrano never deploys to would look successful
    # and change nothing, so surface the disagreement rather than picking one.
    guarded.call("Pulumi ↔ deploy file agreement") do
      stage_hosts = dr_assess_stage_hosts(env[:deploy_file])
      stage_ips = stage_hosts.map { |h| h[:ip] }.uniq
      lb_only = stage_hosts.select { |h| h[:lb_only] }.map { |h| h[:ip] }.uniq
      detail = "pulumi #{app_ips.size} · #{File.basename(env[:deploy_file])} #{stage_ips.size} distinct"
      detail += " (#{lb_only.size} only under LB=true)" if lb_only.any?

      if app_ips.sort == stage_ips.sort
        check.call("Pulumi ↔ deploy file agreement", :ok, detail)
      else
        check.call("Pulumi ↔ deploy file agreement", :warn,
                   "#{detail} — pulumi: #{app_ips.join(', ')} · stage file: #{stage_ips.join(', ')}. " \
                   "A rebuild of a host cap does not deploy to will appear to succeed and change nothing.")
      end

      if stage_ips.size < 2
        check.call("Serving redundancy", :warn,
                   "only #{stage_ips.size} app server in the deploy file — repairing it means a FULL OUTAGE, " \
                   "not a rolling repair")
      else
        check.call("Serving redundancy", :ok, "#{stage_ips.size} app servers — one can be repaired while the other serves")
      end
    end

    # ---------------------------------------------------------------------
    # 2. Edge — ALB, listener, target health
    # ---------------------------------------------------------------------
    puts "\n🔎 Edge (ALB)"

    guarded.call("ALB") do
      if alb_arn.to_s.empty? && alb_dns.to_s.empty?
        # No ALB in the STATE means Pulumi genuinely does not manage one for this
        # stack — a real finding, unlike the missing 'alb' stack OUTPUT, which
        # every live stack has and which says nothing about the ALB itself.
        check.call("ALB", :fail, "no load balancer in the Pulumi state for #{env[:pulumi_stack]}")
      else
        lbs, err = dr_assess_aws("elbv2", "describe-load-balancers", "--region", env[:region], "--output", "json")
        raise "describe-load-balancers failed: #{err}" if lbs.nil?

        # Match on ARN when the state has one (exact), falling back to DNS name.
        lb = JSON.parse(lbs)["LoadBalancers"].find do |l|
          (alb_arn && l["LoadBalancerArn"] == alb_arn) || (alb_dns && l["DNSName"] == alb_dns)
        end
        if lb.nil?
          check.call("ALB #{alb_dns}", :fail, "not found in #{env[:region]} — rebuilt ALB gets a NEW dns name and needs aws:dns_cutover",
                     fix: "rake \"aws:dns_cutover[#{env[:stack]}, #{env[:region]}, #{env[:variant]}]\"")
        else
          state = lb.dig("State", "Code")
          check.call("ALB #{lb['DNSName']}", state == "active" ? :ok : :fail, state)

          tgs, = dr_assess_aws("elbv2", "describe-target-groups", "--load-balancer-arn", lb["LoadBalancerArn"],
                               "--region", env[:region], "--output", "json")
          JSON.parse(tgs.to_s.empty? ? '{"TargetGroups":[]}' : tgs)["TargetGroups"].each do |tg|
            health, = dr_assess_aws("elbv2", "describe-target-health", "--target-group-arn", tg["TargetGroupArn"],
                                    "--region", env[:region], "--output", "json")
            targets = JSON.parse(health.to_s.empty? ? '{"TargetHealthDescriptions":[]}' : health)["TargetHealthDescriptions"]
            healthy = targets.count { |t| t.dig("TargetHealth", "State") == "healthy" }
            name = tg["TargetGroupName"]

            if targets.empty?
              # Expected for the Grafana target group: nothing in alb.py ever
              # attaches the observability instance to it (documented finding).
              check.call("Target group #{name}", :warn, "no targets registered")
            elsif healthy == targets.size
              check.call("Target group #{name}", :ok, "#{healthy}/#{targets.size} healthy")
            else
              unhealthy = targets.reject { |t| t.dig("TargetHealth", "State") == "healthy" }
                                 .map { |t| "#{t.dig('Target', 'Id')}=#{t.dig('TargetHealth', 'State')}" }
              check.call("Target group #{name}", :fail, "#{healthy}/#{targets.size} healthy — #{unhealthy.join(', ')}")
            end
          end
        end
      end
    end

    # ---------------------------------------------------------------------
    # 3. App servers — one component per host, checked independently
    # ---------------------------------------------------------------------
    puts "\n🔎 App servers"

    live_app_host = nil # the hop used later to reach the DB boxes

    app_ips.each do |ip|
      guarded.call("App server", host: ip) do
        # Reachability first: everything below is meaningless without it, and
        # "no SSH" is the signal that separates a rebuild from a restart.
        reachable = begin
          dr_assess_ssh(ip, cap_key, "echo up", timeout: 10) == "up"
        rescue StandardError => e
          check.call("App server", :fail, "unreachable over SSH (#{e.class}) — box gone or network-isolated", host: ip,
                     fix: "rake \"dr:fix:app_server[#{env_name}, #{ip}]\"")
          false
        end
        next unless reachable

        live_app_host ||= ip

        nginx = dr_assess_ssh(ip, cap_key, "systemctl is-active nginx")
        check.call("nginx", nginx == "active" ? :ok : :fail, nginx, host: ip,
                   fix: nginx == "active" ? nil : "ssh #{ip} 'sudo systemctl start nginx' (check `nginx -t` first)")

        # Bracketed patterns ([p]uma) so the wrapping `bash -c` this command
        # runs inside does not match its own cmdline and report a phantom
        # process — pgrep -f matches the whole command line.
        puma = dr_assess_ssh(ip, cap_key, "pgrep -fc '[p]uma'").to_i
        check.call("puma", puma.positive? ? :ok : :fail, "#{puma} process(es)", host: ip,
                   fix: puma.positive? ? nil : "LB=true bundle exec cap #{env[:cap_stage]} puma:restart")

        # disk_check is the serving-chain probe on purpose: every other
        # /health_check endpoint depends on the DB, Redis or ES, so using one of
        # those would blame the app server for a data-tier outage.
        code = dr_assess_ssh(ip, cap_key,
                             "curl -s -o /dev/null -w '%{http_code}' --max-time 30 " \
                             "-H 'Host: #{env[:app_host_header]}' http://localhost/health_check/disk_check.json")
        check.call("serving chain (nginx→puma→rails)", code == "200" ? :ok : :fail, "HTTP #{code}", host: ip,
                   fix: code == "200" ? nil : "LB=true bundle exec cap #{env[:cap_stage]} nginx:switch_app")

        # --- trivial rung: sidekiq ---------------------------------------
        sidekiq = dr_assess_ssh(ip, cap_key, "pgrep -fc '[s]idekiq'").to_i
        if sidekiq.positive?
          check.call("sidekiq", :ok, "#{sidekiq} process(es)", host: ip)
        elsif auto_fix
          puts "🔧 sidekiq is down on #{ip} — restarting it via the existing cap task..."
          # Reuses the tested restart path (deploy.rb sidekiq:ensure_clean_restart)
          # rather than inventing a start command, and is host-filtered so the
          # healthy app server is not touched.
          # Keep the exit status: a cap run that never STARTED (bundler error,
          # wrong stage) looks identical to a restart that didn't take unless
          # the two are reported apart.
          started = system("LB=true HOSTS=#{ip} bundle exec cap #{env[:cap_stage]} sidekiq:ensure_clean_restart")
          sidekiq = dr_assess_ssh(ip, cap_key, "pgrep -fc '[s]idekiq'").to_i
          check.call("sidekiq", sidekiq.positive? ? :fixed : :fail,
                     if sidekiq.positive?
                       "was down — restarted, #{sidekiq} process(es)"
                     else
                       started ? "restart ran but no process appeared" : "cap sidekiq:ensure_clean_restart exited non-zero"
                     end, host: ip)
        else
          check.call("sidekiq", :fail, "not running (read-only mode — not restarted)", host: ip,
                     fix: "LB=true HOSTS=#{ip} bundle exec cap #{env[:cap_stage]} sidekiq:ensure_clean_restart")
        end

        # --- trivial rung: xirr_py container ------------------------------
        xirr = dr_assess_ssh(ip, cap_key, "sudo docker ps --format '{{.Names}}' | grep -cx xirr_py").to_i
        if xirr.positive?
          check.call("xirr_py container", :ok, "running", host: ip)
        elsif auto_fix
          puts "🔧 xirr_py is not running on #{ip} — starting it (fund IRR calculations fail without it)..."
          started = system("LB=true HOSTS=#{ip} bundle exec cap #{env[:cap_stage]} IRM:start_boot_services")
          xirr = dr_assess_ssh(ip, cap_key, "sudo docker ps --format '{{.Names}}' | grep -cx xirr_py").to_i
          check.call("xirr_py container", xirr.positive? ? :fixed : :fail,
                     if xirr.positive?
                       "was down — started it"
                     else
                       started ? "start ran but the container is not up" : "cap IRM:start_boot_services exited non-zero"
                     end, host: ip)
        else
          check.call("xirr_py container", :fail, "not running (read-only mode)", host: ip,
                     fix: "LB=true HOSTS=#{ip} bundle exec cap #{env[:cap_stage]} IRM:start_boot_services")
        end

        disk = dr_assess_ssh(ip, cap_key, "df -h / | awk 'NR==2 {print $5}'").to_s.delete("%").to_i
        check.call("root disk", disk > 90 ? :fail : (disk > 80 ? :warn : :ok), "#{disk}% used", host: ip)
      end
    end

    # ---------------------------------------------------------------------
    # 4. Data tier — MySQL primary/replica, and the ES/Redis containers that
    #    share the primary box (tag DB-Redis-ES: it is not "just MySQL")
    # ---------------------------------------------------------------------
    puts "\n🔎 Data tier"

    if live_app_host.nil?
      check.call("Data tier", :fail,
                 "skipped — DB boxes accept SSH only from app servers and none is reachable. " \
                 "Repair an app server first, then re-run assess.")
    else
      puts "   (reaching the DB boxes through app server #{live_app_host})"

      # --- primary -------------------------------------------------------
      guarded.call("MySQL primary", host: db_host) do
        state = dr_assess_ssh_via_app(live_app_host, cap_key, db_host, env[:db_keyname], "systemctl is-active mysql")
        check.call("MySQL primary", state == "active" ? :ok : :fail, state, host: db_host,
                   fix: state == "active" ? nil : "rake \"dr:fix:promote_replica[#{env_name}]\"  (replica healthy, RPO~0) " \
                       "OR rake \"dr:fix:db_primary[#{env_name}]\"  (replica unusable, loses up to ~1h)")

        names = dr_assess_ssh_via_app(live_app_host, cap_key, db_host, env[:db_keyname],
                                      "docker ps --format {{.Names}} 2>/dev/null || sudo docker ps --format {{.Names}}")
        %w[elasticsearch redis-stack-server].each do |container|
          if names.include?(container)
            check.call("container #{container}", :ok, "running", host: db_host)
          elsif auto_fix
            # The cheapest repair in the whole tool: the box is fine, a process
            # died. Restarting a container is not a DB event and must never
            # escalate into one.
            puts "🔧 #{container} is not running on #{db_host} — running the baked start_data_containers.sh..."
            dr_assess_ssh_via_app(live_app_host, cap_key, db_host, env[:db_keyname],
                                  "sudo /usr/local/bin/start_data_containers.sh")
            sleep 5 # give the daemon time to report the container as up
            names = dr_assess_ssh_via_app(live_app_host, cap_key, db_host, env[:db_keyname],
                                          "docker ps --format {{.Names}} 2>/dev/null || sudo docker ps --format {{.Names}}")
            check.call("container #{container}", names.include?(container) ? :fixed : :fail,
                       names.include?(container) ? "was down — restarted it" : "did not come up — check the box",
                       host: db_host)
          else
            check.call("container #{container}", :fail, "not running (read-only mode)", host: db_host,
                       fix: "ssh via #{live_app_host}: sudo /usr/local/bin/start_data_containers.sh")
          end
        end

        # Backups are armed by a marker file, and arming is a SIDE EFFECT of
        # restore_primary — an environment that never restored takes no backups
        # at all, silently. That is the failure this check exists for.
        armed = dr_assess_ssh_via_app(live_app_host, cap_key, db_host, env[:db_keyname],
                                      "test -f /etc/db_backup_enabled && echo yes")
        check.call("backup cron armed", armed == "yes" ? :ok : :fail,
                   armed == "yes" ? "/etc/db_backup_enabled present" : "MARKER MISSING — no backups are being taken",
                   host: db_host,
                   fix: armed == "yes" ? nil : "ssh via #{live_app_host}: sudo touch /etc/db_backup_enabled")
      end

      # --- replica -------------------------------------------------------
      if db_replica.to_s.empty? || db_replica == db_host
        check.call("MySQL replica", :warn, "no separate replica configured for this stack")
      else
        guarded.call("MySQL replica", host: db_replica) do
          state = dr_assess_ssh_via_app(live_app_host, cap_key, db_replica, env[:db_keyname], "systemctl is-active mysql")
          check.call("MySQL replica", state == "active" ? :ok : :fail, state, host: db_replica,
                     fix: state == "active" ? nil : "rake \"dr:fix:db_replica[#{env_name}]\"")

          # Replication state without secrets: root@localhost authenticates over
          # the unix socket, so `sudo mysql` needs no password. If a box is set
          # up differently this degrades to a warning rather than a false alarm.
          status_out = dr_assess_ssh_via_app(live_app_host, cap_key, db_replica, env[:db_keyname],
                                             "sudo mysql -N -e \"SHOW REPLICA STATUS\\G\" 2>&1 | " \
                                             "grep -E 'Replica_(IO|SQL)_Running:|Seconds_Behind_Source:|Last_Error:'")
          if status_out.to_s.empty? || status_out.include?("ERROR")
            check.call("replication", :warn, "could not read SHOW REPLICA STATUS (#{status_out.to_s.lines.first.to_s.strip})",
                       host: db_replica)
          else
            running = status_out.scan(/Replica_(?:IO|SQL)_Running:\s*(\w+)/).flatten
            lag = status_out[/Seconds_Behind_Source:\s*(\d+)/, 1]
            error = status_out[/Last_Error:\s*(.+)/, 1].to_s.strip
            if running.size == 2 && running.all? { |r| r.casecmp("yes").zero? }
              check.call("replication", lag.to_i > 300 ? :warn : :ok, "both threads running, #{lag}s behind", host: db_replica)
            else
              check.call("replication", :fail, "threads #{running.join('/')}#{" — #{error}" unless error.empty?}",
                         host: db_replica,
                         fix: "rake \"dr:fix:db_replica[#{env_name}]\"  (resets replication in place when the box is healthy)")
            end
          end

          # Single writer per backup chain: a replica that is armed will corrupt
          # the restore lineage by writing into the same bucket as the primary.
          armed = dr_assess_ssh_via_app(live_app_host, cap_key, db_replica, env[:db_keyname],
                                        "test -f /etc/db_backup_enabled && echo yes")
          check.call("replica backup cron disarmed", armed == "yes" ? :fail : :ok,
                     armed == "yes" ? "ARMED — two writers will corrupt the backup chain" : nil, host: db_replica,
                     fix: armed == "yes" ? "ssh via #{live_app_host}: sudo rm -f /etc/db_backup_enabled" : nil)
        end
      end
    end

    # ---------------------------------------------------------------------
    # 5. Plumbing — NAT, S3, SSM
    # ---------------------------------------------------------------------
    puts "\n🔎 Plumbing"

    # The DB boxes sit in private subnets with NO S3 or SSM VPC endpoints, so
    # BOTH the backup uploads and the baked restore script's SSM config travel
    # through the NAT gateway. A dead NAT stops backups with no user-visible
    # symptom — which is why this is checked here rather than assumed.
    guarded.call("NAT gateway") do
      ec2 = Aws::EC2::Client.new(region: env[:region])
      nats = ec2.describe_nat_gateways(filter: [{ name: "state", values: %w[available pending] }]).nat_gateways
      if nats.empty?
        check.call("NAT gateway", :fail, "no available NAT gateway in #{env[:region]} — DB boxes cannot reach S3 or SSM",
                   fix: "rake \"aws:nat:create[#{env_name}]\"   # existing task, lib/tasks/nat_gateway.rake")
      else
        check.call("NAT gateway", :ok, nats.map { |n| "#{n.nat_gateway_id} #{n.state}" }.join(", "))
      end
    end

    # Proves the NAT path end-to-end from where it actually matters, rather than
    # inferring reachability from the gateway's own state.
    if live_app_host && db_host
      guarded.call("DB box outbound (S3/SSM via NAT)") do
        code = dr_assess_ssh_via_app(live_app_host, cap_key, db_host, env[:db_keyname],
                                     "curl -s -o /dev/null -w %{http_code} --max-time 15 https://s3.#{env[:region]}.amazonaws.com")
        check.call("DB box outbound (S3/SSM via NAT)", code.to_s.start_with?("2", "3", "4") ? :ok : :fail,
                   code.to_s.empty? ? "no response — NAT path is down" : "HTTP #{code} from s3.#{env[:region]}.amazonaws.com")
      end
    end

    guarded.call("S3 app bucket") do
      Aws::S3::Client.new(region: env[:region]).head_bucket(bucket: env[:app_bucket])
      check.call("S3 app bucket", :ok, env[:app_bucket])
    end

    # Reuses the hourly alert's own logic, so assess and the alert can never
    # disagree about what "stale" means.
    guarded.call("Backup freshness") do
      failures = DbBackupFreshnessJob.new.collect_failures
      if failures.empty?
        check.call("Backup freshness", :ok, "primary + replica buckets within thresholds")
      else
        failures.each { |f| check.call("Backup freshness", :fail, f) }
      end
    end

    # The baked restore script reads its config from SSM in the INSTANCE's own
    # region; missing params mean a restore cannot start.
    guarded.call("SSM backup params") do
      prefix = "/irm/#{env[:stack]}/db_backup"
      missing = []
      denied = []
      %w[mysql_user mysql_password bucket bucket_region database_name].each do |key|
        # get-parameter (singular) deliberately: the operator IAM policy grants
        # ssm:GetParameter, and get-parameters (plural) is a different action
        # that gets AccessDenied even when every parameter exists.
        out, err = dr_assess_aws("ssm", "get-parameter", "--name", "#{prefix}/#{key}",
                                 "--region", env[:region], "--query", "Parameter.Name", "--output", "text")
        next if out

        # "not seeded" and "your keys cannot read it" need completely different
        # responses, and they are indistinguishable unless the error is read:
        # seeding over a parameter that already exists would overwrite a good
        # value with whatever the local credentials happen to hold.
        if err.to_s.include?("ParameterNotFound")
          missing << key
        else
          denied << "#{key}: #{err}"
        end
      end

      if missing.empty? && denied.empty?
        check.call("SSM backup params", :ok, "#{prefix}/* (5/5) in #{env[:region]}")
      elsif denied.any?
        check.call("SSM backup params", :warn,
                   "could not read #{prefix}/* in #{env[:region]} — #{denied.first}. " \
                   "This is an IAM/credential problem on YOUR machine, not necessarily a missing parameter. " \
                   "The DB boxes read these through their instance role, so backups may be fine. " \
                   "Confirm before seeding: aws ssm get-parameter --name #{prefix}/bucket --region #{env[:region]}")
      else
        check.call("SSM backup params", :fail,
                   "#{missing.size}/5 not present in #{env[:region]}: #{missing.join(', ')} — " \
                   "the baked restore script cannot read its config, so db:restore_*_remote will fall back " \
                   "to an uploaded script or fail",
                   fix: "rake \"xtrabackup:seed_ssm_params[#{env_name}, #{env[:region]}]\"")
      end
    end

    # ---------------------------------------------------------------------
    # 6. Observability — never blocks anything, always reported
    # ---------------------------------------------------------------------
    puts "\n🔎 Observability"

    guarded.call("Observability instance") do
      ec2 = Aws::EC2::Client.new(region: env[:region])
      tagged = ec2.describe_instances(filters: [{ name: "tag:Name", values: ["Observability"] },
                                                { name: "instance-state-name", values: %w[running pending stopping stopped] }])
                  .reservations.flat_map(&:instances)
      # Prefer a RUNNING instance: staging carries a second, stopped
      # Observability box left behind by an interrupted update, and reporting on
      # that one would call a healthy environment broken.
      obs = tagged.find { |i| i.state.name == "running" } || tagged.first

      if obs.nil?
        check.call("Observability instance", :fail, "no instance tagged Observability in #{env[:region]}",
                   fix: "rake \"dr:fix:observability[#{env_name}]\"")
      else
        detail = "#{obs.instance_id} #{obs.state.name}"
        detail += " (#{tagged.size} tagged Observability — extras are leftovers)" if tagged.size > 1
        check.call("Observability instance", obs.state.name == "running" ? :ok : :fail, detail)
      end
    end

    # Any box replaced by a repair keeps its OLD ip in the generated prometheus
    # config until someone regenerates and copies it — aws:generate_prometheus_yml
    # only writes the file locally, it does not push it. Documented finding.
    if results.any? { |r| [:fixed, :fail].include?(r[:status]) }
      check.call("Prometheus targets", :warn,
                 "if any box is replaced, regenerate and copy the config — " \
                 "rake \"aws:generate_prometheus_yml[#{env_name}]\" writes it LOCALLY only")
    end

    # ---------------------------------------------------------------------
    # 7. DNS + public website
    # ---------------------------------------------------------------------
    puts "\n🔎 DNS and website"

    guarded.call("DNS #{env[:app_host_header]}") do
      resolved = Resolv::DNS.new.getaddresses(env[:app_host_header]).map(&:to_s)
      check.call("DNS #{env[:app_host_header]}", resolved.any? ? :ok : :fail,
                 resolved.any? ? "resolves to #{resolved.join(', ')}" : "does not resolve")
    end

    if env[:website_hosts].empty?
      # staging.us has no WEBSITE_HOSTS; a check that did not run must never be
      # counted as one that passed.
      check.call("Public website", :warn, "not configured for this environment (no WEBSITE_HOSTS)")
    elsif live_app_host
      canonical, *aliases = env[:website_hosts]
      guarded.call("Website apex (#{canonical})") do
        code = dr_assess_ssh(live_app_host, cap_key,
                             "curl -s -o /dev/null -w '%{http_code}' --max-time 20 -H 'Host: #{canonical}' http://localhost/")
        check.call("Website apex (#{canonical})", code == "200" ? :ok : :fail, "HTTP #{code}",
                   fix: code == "200" ? nil : "rake website:build && LB=true bundle exec cap #{env[:cap_stage]} deploy")
      end
      aliases.each do |host|
        guarded.call("Website alias (#{host})") do
          code = dr_assess_ssh(live_app_host, cap_key,
                               "curl -s -o /dev/null -w '%{http_code}' --max-time 20 -H 'Host: #{host}' http://localhost/")
          check.call("Website alias (#{host})", %w[301 308].include?(code) ? :ok : :fail,
                     %w[301 308].include?(code) ? "redirects to #{canonical}" : "HTTP #{code} — expected 301")
        end
      end
    end

    # ---------------------------------------------------------------------
    # 8. Scorecard and the ranked repair plan
    # ---------------------------------------------------------------------
    fails = results.count { |r| r[:status] == :fail }
    warns = results.count { |r| r[:status] == :warn }
    fixed = results.count { |r| r[:status] == :fixed }
    oks = results.size - fails - warns - fixed

    puts ""
    puts "=" * 78
    puts "📋 #{results.size} checks: #{oks} ok, #{fixed} auto-fixed, #{warns} warnings, #{fails} failures"
    puts "=" * 78

    if fixed.positive?
      puts "\n🔧 Auto-fixed (trivial rung — process restarts only):"
      results.select { |r| r[:status] == :fixed }.each do |r|
        puts "   • #{r[:component]}#{r[:host] ? " on #{r[:host]}" : ''} — #{r[:detail]}"
      end
    end

    plan = results.select { |r| r[:fix] }.uniq { |r| r[:fix] }
    if plan.any?
      puts "\n🧭 Recommended repairs, cheapest first — run ONE, then re-assess:"
      plan.each_with_index do |r, i|
        puts "   #{i + 1}. #{r[:component]}#{r[:host] ? " (#{r[:host]})" : ''}"
        puts "      #{r[:fix]}"
      end
      puts "\n   Every dr:fix task repairs ONE component and refuses to touch anything else."
    end

    if fails.zero?
      puts "\n🟢 No component is DOWN#{fixed.positive? ? ' (after the auto-fixes above)' : ''}."
    else
      puts "\n🔴 #{fails} component check(s) FAILED — see the plan above."
      abort ""
    end
  end
end
