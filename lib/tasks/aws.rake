# Rakefile
require 'dotenv'
require 'aws-sdk-ec2'
require 'net/http'
require 'uri'
require 'rake'
require_relative 'aws_utils'

include AwsUtils

namespace :aws do

  task :grow_disk do
    # Run the following system cmds
    puts "🌱 Growing disk..."
    system("df -k /")
    system("sudo lsblk")
    system("sudo growpart /dev/nvme0n1 1")
    system("sudo lsblk")
    system("sudo resize2fs /dev/nvme0n1p1")
    system("df -k /")
    puts "✅ Disk grown successfully."
  end

  # This is the task that will be called whenever we need to do a complete DR into another region
  # Full flow: pulumi config + pulumi up + rewrite credentials/env/deploy IPs + cap deploy + DB restore.
  #
  # NON-INTERACTIVE (recommended for DR): pass a branch name as the 7th arg —
  # the task auto-commits the rewritten config files to that branch, pushes, and
  # runs the entire recovery (primary+replica restore, migrations, cutover)
  # without any prompts:
  #   RAILS_ENV=production rake "aws:setup_infra[production, AppServer, DB-Redis-ES, ap-south-2, in, production.in, dr_prod_in_2026_07_08]"
  #
  # LEGACY INTERACTIVE: omit the branch — pauses for a manual DB restore and a
  # manual commit, then prompts for the branch name (previous behaviour).
  task :setup_infra, [:stack, :web_server_name, :db_server_name, :region, :env_variant, :env_name, :branch] do |t, args|
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(args[:env_name])
    args.with_defaults(region: ENV["AWS_REGION"])
    setup_infra(args[:stack], args[:web_server_name], args[:db_server_name], args[:region], args[:env_variant], args[:branch])
  end

  # Config-only subset of setup_infra: refreshes a stack's Pulumi config (latest
  # AMI ids, region, domain_name, key_name) WITHOUT running pulumi up or touching
  # servers. Referenced by the header comments in IRM-Infra/Pulumi.*.yaml.
  # For a brand-new region, set DOMAIN_NAME and AWS_KEY_NAME env vars (see
  # ensure_pulumi_stack_config in aws_utils.rb) and the stack is created fully
  # configured in one command.
  # ex: rake "aws:setup_pulumi_config[production, AppServer, DB-Redis-ES, ap-south-2, in, production.in]"
  desc "Refresh Pulumi stack config (AMIs, region, domain, key name) without deploying"
  task :setup_pulumi_config, [:stack, :web_server_name, :db_server_name, :region, :env_variant, :env_name] do |t, args|
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(args[:env_name])
    args.with_defaults(region: ENV["AWS_REGION"], web_server_name: "AppServer", db_server_name: "DB-Redis-ES")
    setup_pulumi_config(args[:stack], args[:web_server_name], args[:db_server_name], args[:region], args[:env_variant])
  end

  # Automates the "always-true readiness" checklist from docs/DR_GUIDE.md §1:
  # everything that must be true BEFORE a disaster for DR to work. Prints a
  # ✅/⚠️/❌ scorecard; exits non-zero if any hard failure — so it can run in
  # cron/CI later. Read-only: checks, never fixes.
  # ex: rake "aws:dr_readiness[production, in, ap-south-2, production.in]"
  #     rake "aws:dr_readiness"          # staging, in, $AWS_BACKUP_REGION
  desc "DR readiness scorecard: backups, AMIs, SSM, stack config, key pair, zone, drill recency"
  task :dr_readiness, [:stack, :env_variant, :region, :env_name] do |t, args|
    require 'yaml'
    require 'json'
    require 'time'
    require 'open3'

    # Load the full Rails app EXPLICITLY. A `=> :environment` prerequisite
    # inside `namespace :aws` resolves to our custom aws:environment task
    # (Rake scoping searches the current namespace first), NOT Rails'
    # top-level :environment — so app classes like DbBackupFreshnessJob were
    # never loaded. Rake::Task[...] lookup is absolute and unambiguous.
    Rake::Task["environment"].invoke

    args.with_defaults(stack: 'staging', env_variant: 'in')
    stack = args[:stack]
    env_variant = args[:env_variant]
    env_name = args[:env_name] || "#{stack}.#{env_variant}"

    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(env_name)
    region = args[:region] || ENV["AWS_BACKUP_REGION"] ||
             raise("Pass a DR region or set AWS_BACKUP_REGION (shell or .env.#{env_name})")

    puts "🩺 DR readiness for #{stack} (#{env_variant}) → DR region #{region}\n\n"

    results = [] # [status, label, detail]
    check = ->(label, status, detail = "") { results << [status, label, detail] }

    # --- 1. Backup freshness (primary + replica buckets) --------------------
    # Exact same checks the hourly alert runs — covers cadence, full-age,
    # replica presence, and bucket reachability in one shot
    begin
      failures = DbBackupFreshnessJob.new.collect_failures
      if failures.empty?
        check.("Backup freshness (primary + replica)", :ok, "within thresholds")
      else
        failures.each { |f| check.("Backup freshness", :fail, f) }
      end
    rescue NameError => e
      # Job class not loadable — almost always means the wrong git branch is
      # checked out (the class ships with the DR-hardening branch)
      check.("Backup freshness", :fail, "#{e.message} — are you on the right branch? (git branch --show-current)")
    rescue StandardError => e
      check.("Backup freshness", :fail, "check errored: #{e.message}")
    end

    # --- 2. AMIs present + recent in the DR region ---------------------------
    %w[AppServer DB-Redis-ES Observability].each do |name|
      ami = latest_ami(name, region)
      age_days = ((Time.now - Time.parse(ami.creation_date)) / 86_400).round
      status = age_days > 8 ? :warn : :ok # weekly bake → >8d means the cron missed
      check.("AMI #{name} in #{region}", status,
             "#{ami.image_id}, #{age_days}d old#{' — weekly bake overdue?' if status == :warn}")
    rescue StandardError => e
      check.("AMI #{name} in #{region}", :fail, e.message.lines.first.to_s.strip)
    end

    # --- 3. SSM backup params seeded in the DR region ------------------------
    rails_env = env_name.split(".").first
    prefix = "/irm/#{rails_env}/db_backup"
    # Per-name get-parameter (singular), deliberately: the operator IAM policy
    # grants ssm:GetParameter — get-parameters (plural) is a DIFFERENT IAM
    # action and gets AccessDenied even when every parameter exists
    missing = []
    errors = []
    %w[mysql_user mysql_password bucket bucket_region database_name].each do |key|
      _out, err, st = Open3.capture3("aws", "ssm", "get-parameter", "--name", "#{prefix}/#{key}",
                                     "--region", region, "--query", "Parameter.Name", "--output", "text")
      next if st.success?

      # AWS CLI error text starts with a blank line — strip the whole thing first
      if err.include?("ParameterNotFound")
        missing << key
      else
        errors << "#{key}: #{err.strip.lines.first.to_s.strip}"
      end
    end
    if missing.empty? && errors.empty?
      check.("SSM backup params in #{region}", :ok, "#{prefix}/* (5/5)")
    elsif errors.any?
      check.("SSM backup params in #{region}", :fail, errors.first)
    else
      check.("SSM backup params in #{region}", :fail,
             "missing #{missing.size}: #{missing.join(', ')} — run xtrabackup:seed_ssm_params[#{env_name}, #{region}]")
    end

    # --- 4. Pulumi stack config complete for the DR region -------------------
    stack_file = "../IRM-Infra/Pulumi.#{stack}-#{region}.yaml"
    stack_cfg = {}
    if File.exist?(stack_file)
      stack_cfg = YAML.load_file(stack_file)["config"] || {}
      keys = stack_cfg.keys.map { |k| k.split(":").last }
      missing = %w[web_server_ami db_server_ami observability_ami key_name region domain_name] - keys
      domain = stack_cfg["IRM-infra:domain_name"].to_s
      if missing.any?
        check.("Pulumi stack #{stack}-#{region}", :fail, "missing config keys: #{missing.join(', ')}")
      elsif !domain.start_with?("*.")
        check.("Pulumi stack #{stack}-#{region}", :fail, "domain_name '#{domain}' must start with '*.'")
      else
        check.("Pulumi stack #{stack}-#{region}", :ok, "config complete (#{domain})")
      end
    else
      check.("Pulumi stack #{stack}-#{region}", :fail, "#{stack_file} not found")
    end

    # --- 4b. Pulumi state backend reachable ----------------------------------
    # State access is a hard DR dependency: if the backend (or its login) is
    # broken, `pulumi up` is impossible for EVERY stack. Surface that on the
    # quarterly scorecard, not mid-incident. See IRM-Infra/PULUMI_STATE.md.
    begin
      out, err, st = Open3.capture3("pulumi stack ls --json", chdir: "../IRM-Infra")
      if st.success?
        names = JSON.parse(out).map { |s| s["name"] }
        # Which backend are we actually talking to? (personal cloud vs S3)
        who, = Open3.capture3("pulumi whoami --verbose", chdir: "../IRM-Infra")
        backend = who.lines.grep(/Backend URL/i).first.to_s.split(/URL:?\s*/i).last.to_s.strip
        if names.include?("#{stack}-#{region}")
          check.("Pulumi state backend", :ok, "stack #{stack}-#{region} present#{" on #{backend}" unless backend.empty?}")
        else
          # Not fatal: a brand-new DR region legitimately has no stack yet —
          # setup_infra creates it. The backend being reachable is the check.
          check.("Pulumi state backend", :warn, "reachable#{" (#{backend})" unless backend.empty?} but stack #{stack}-#{region} not found — setup_infra will create it")
        end
      else
        check.("Pulumi state backend", :fail, "pulumi stack ls failed: #{err.to_s.strip.lines.first} — check `pulumi login` (see IRM-Infra/PULUMI_STATE.md)")
      end
    rescue StandardError => e
      check.("Pulumi state backend", :fail, e.message.to_s.lines.first.to_s.strip)
    end

    # --- 5. EC2 key pair exists in the DR region -----------------------------
    key_name = stack_cfg["IRM-infra:key_name"]
    if key_name
      begin
        Aws::EC2::Client.new(region: region).describe_key_pairs(key_names: [key_name])
        check.("Key pair '#{key_name}' in #{region}", :ok)
      rescue Aws::EC2::Errors::InvalidKeyPairNotFound
        check.("Key pair '#{key_name}' in #{region}", :fail, "create/import it (EC2 → Key Pairs) — Pulumi does not create key pairs")
      rescue StandardError => e
        check.("Key pair '#{key_name}' in #{region}", :fail, e.message.lines.first.to_s.strip)
      end
    end

    # --- 6. Route53 hosted zone for the domain --------------------------------
    if (domain ||= stack_cfg["IRM-infra:domain_name"].to_s) && domain.start_with?("*.")
      base_domain = domain.sub(/\A\*\./, "")
      out, err, st = Open3.capture3("aws", "route53", "list-hosted-zones-by-name",
                                    "--dns-name", base_domain, "--max-items", "1",
                                    "--query", "HostedZones[0].Name", "--output", "text")
      if st.success? && out.strip == "#{base_domain}."
        check.("Hosted zone #{base_domain}", :ok)
      else
        check.("Hosted zone #{base_domain}", :fail, st.success? ? "zone not found (got '#{out.strip}')" : err.lines.first.to_s.strip)
      end
    end

    # --- 7. Local prerequisites ------------------------------------------------
    {
      ".env.#{stack}.#{env_variant}" => Rails.root.join(".env.#{stack}.#{env_variant}"),
      "credentials #{env_name}.yml.enc" => Rails.root.join("config/credentials/#{env_name}.yml.enc"),
      "credentials #{env_name}.key" => Rails.root.join("config/credentials/#{env_name}.key"),
      "sibling ../IRM-Infra checkout" => Rails.root.join("../IRM-Infra")
    }.each do |label, path|
      check.("Local: #{label}", File.exist?(path) ? :ok : :fail, File.exist?(path) ? "" : "missing: #{path}")
    end

    # --- 8. Drill recency -------------------------------------------------------
    drill_log = Rails.root.join("docs/dr_drills.md")
    last_pass = nil
    if File.exist?(drill_log)
      File.readlines(drill_log).each do |line|
        # | Date | Stack | Variant | Region | Result | RTO | Branch |
        cols = line.split("|").map(&:strip).reject(&:empty?)
        next unless cols.size == 7 # skips the title line, header row, and separator row

        row_date, row_stack, row_variant, _region, row_result, = cols
        next unless row_result == "PASSED" && row_stack == stack && row_variant == env_variant

        last_pass = [last_pass, Time.parse(row_date)].compact.max rescue last_pass
      end
    end
    if last_pass.nil?
      check.("DR drill recency (#{env_variant})", :warn, "no PASSED drill on record — run TEARDOWN=true rake \"aws:dr_drill[#{env_variant}]\"")
    else
      days = ((Time.now - last_pass) / 86_400).round
      check.("DR drill recency (#{env_variant})", days > 100 ? :warn : :ok,
             "last passed #{days}d ago#{' — quarterly cadence overdue' if days > 100}")
    end

    # --- Scorecard ---------------------------------------------------------------
    icons = { ok: "✅", warn: "⚠️ ", fail: "❌" }
    puts ""
    results.each { |s, l, d| puts "#{icons[s]} #{l}#{d.to_s.empty? ? '' : " — #{d}"}" }
    fails = results.count { |s, _, _| s == :fail }
    warns = results.count { |s, _, _| s == :warn }
    puts "\n#{fails.zero? ? '🟢' : '🔴'} #{results.size} checks: #{results.size - fails - warns} ok, #{warns} warnings, #{fails} failures"
    abort "❌ NOT DR-ready — fix the failures above (see docs/DR_GUIDE.md §1)" if fails.positive?
  end

  # Quarterly DR drill: proves the WHOLE recovery chain (AMIs present, Pulumi
  # stack deployable, S3 backups restorable, deploy + migrations + cutover)
  # by rebuilding a stack in the DR region, unattended, and measuring the time.
  # An untested DR plan is a hypothesis — this turns it into a measurement.
  #
  #   rake "aws:dr_drill[in]"                      # staging IN → AWS_BACKUP_REGION
  #   rake "aws:dr_drill[in, ap-south-2]"          # explicit region
  #   TEARDOWN=true rake "aws:dr_drill[in]"        # pulumi destroy after the drill
  #
  #   # production — same non-interactive sequence, real prod backups/creds:
  #   CONFIRM_PRODUCTION=true TEARDOWN=true \
  #     rake "aws:dr_drill[in, ap-south-2, production.in, production]"
  #
  # Notes:
  # - Commits only to a dr_drill_* branch; main is never touched. The task
  #   returns your working tree to the original branch afterwards.
  # - Without TEARDOWN=true the drill infra keeps running (and costing) —
  #   the teardown command is printed at the end.
  # - `stack` (4th arg) defaults to 'staging'. Passing 'production' rebuilds
  #   the REAL production Pulumi stack (production-<region>) in the DR region
  #   using live production backups and credentials — this is a genuine DR
  #   exercise against the production account, not a scaled-up staging test.
  #   It refuses to run unless CONFIRM_PRODUCTION=true is ALSO set, so a
  #   staging command copy-pasted with the extra arg can't silently fire
  #   against production.
  desc "Run an unattended DR drill (staging by default; production requires CONFIRM_PRODUCTION=true) and report RTO"
  task :dr_drill, [:env_variant, :region, :env_name, :stack] do |t, args|
    args.with_defaults(env_variant: 'in', stack: 'staging')
    env_variant = args[:env_variant]
    stack = args[:stack]

    if stack == 'production' && ENV['CONFIRM_PRODUCTION'] != 'true'
      abort "❌ Refusing to drill stack 'production' without CONFIRM_PRODUCTION=true set. " \
            "This rebuilds the real production Pulumi stack in the DR region using live " \
            "production backups and credentials — set the env var deliberately if that's " \
            "what you intend; it is not a typo-guard to silence casually."
    end

    env_name = args[:env_name] || "#{stack}.#{env_variant}"

    # Load .env.<env_name> + credentials BEFORE resolving the region, so an
    # AWS_BACKUP_REGION defined in the env file (not just the shell) is seen
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(env_name)

    region = args[:region] || ENV["AWS_BACKUP_REGION"] || raise("Pass a region or set AWS_BACKUP_REGION (shell or .env.#{env_name})")

    original_branch = `git rev-parse --abbrev-ref HEAD`.strip
    branch_prefix = stack == 'staging' ? "dr_drill_#{env_variant}" : "dr_drill_#{stack}_#{env_variant}"
    drill_branch = "#{branch_prefix}_#{Time.now.strftime('%Y_%m_%d_%H%M')}"
    started_at = Time.now
    result = "FAILED"

    puts "🚨 DR DRILL: rebuilding #{stack} (#{env_variant}) in #{region} on branch #{drill_branch}"
    # Capture the whole run — including the ensure block's summary and report
    # line — to docs/dr_runs/<branch>.log, so the transcript exists without the
    # operator having to pipe through tee.
    with_dr_transcript(drill_branch) do
    begin
      # setup_infra writes the evidence report itself for a REAL recovery; for a
      # drill we defer it to the ensure block below so a FAILED drill produces a
      # report too — "we tried and it broke here" is itself audit-relevant.
      @dr_report_deferred = true
      # The full non-interactive DR sequence — the same code path a real
      # production DR uses, which is the point of the drill
      setup_infra(stack, "AppServer", "DB-Redis-ES", region, env_variant, drill_branch)
      result = "PASSED"
    ensure
      duration_min = ((Time.now - started_at) / 60).round(1)

      # Return the operator's working tree to where it was
      run_cmd("git checkout #{original_branch}") unless original_branch.empty?

      # Append to the drill log — the audit trail that DR is tested, not assumed
      log_file = Rails.root.join("docs", "dr_drills.md")
      unless File.exist?(log_file)
        File.write(log_file, <<~HEADER)
          # DR Drill Log

          > **Rebuild (min)** is the time from the start of the recovery command to the
          > stack passing `recovery:verify`. It is *not* end-to-end RTO: it excludes
          > incident detection, the decision to declare a disaster, and DNS cutover plus
          > TTL propagation. Per-run evidence reports are in `docs/dr_runs/`.

          | Date | Stack | Variant | Region | Result | Rebuild (min) | Branch |
          |---|---|---|---|---|---|---|
        HEADER
      end
      File.open(log_file, "a") do |f|
        f.puts "| #{started_at.strftime('%Y-%m-%d %H:%M')} | #{stack} | #{env_variant} | #{region} | #{result} | #{duration_min} | #{drill_branch} |"
      end

      # Evidence report for every outcome, pass or fail
      write_dr_report(stack: stack, region: region, env_variant: env_variant,
                      branch: drill_branch, result: result, started_at: started_at, drill: true)

      puts "\n#{result == 'PASSED' ? '✅' : '❌'} DR DRILL #{result} — measured rebuild time: #{duration_min} minutes (logged to docs/dr_drills.md)"
      puts "   NOTE: that figure excludes detection, disaster declaration, and DNS cutover/TTL —"
      puts "         it is rebuild time, not end-to-end RTO. See the report for the full scope."

      if result == "PASSED"
        if ENV["TEARDOWN"] == "true"
          puts "🧹 TEARDOWN=true — destroying drill infra..."
          run_cmd("pulumi destroy --stack #{stack}-#{region} --yes --color=always", "../IRM-Infra")
        else
          puts "⚠️  Drill infra is still RUNNING (and costing money) in #{region}."
          puts "   Tear down with: cd ../IRM-Infra && pulumi destroy --stack #{stack}-#{region} --yes"
        end
      end
    end
    end
  end

  # MANUAL-ONLY by design: DNS cutover is the moment a rebuilt region becomes
  # live — it must be an explicit human decision, so this task is never called
  # by aws:setup_infra or aws:dr_drill (drills have no DNS name to flip).
  # It shows the current record and asks for confirmation before the UPSERT.
  # Prerequisite: a `pulumi up` on the target stack (output.json must carry
  # the ALB endpoint).
  # ex: rake "aws:dns_cutover[production, ap-south-2, in]"           # -> app.caphive.com
  #     rake "aws:dns_cutover[production, ap-south-2, in, custom.caphive.com]"
  desc "MANUAL: point the app DNS record at a stack's ALB (Route53 alias, asks confirmation)"
  task :dns_cutover, [:stack, :region, :env_variant, :record_name] do |t, args|
    require 'yaml'
    require 'json'
    require 'open3'

    stack = args[:stack] or raise "stack required (production|staging)"
    region = args[:region] or raise "region required, e.g. ap-south-2"
    args[:env_variant] or raise "env_variant required (in|us)"

    # Domain from the target stack's Pulumi config — single source of truth
    stack_file = "../IRM-Infra/Pulumi.#{stack}-#{region}.yaml"
    raise "#{stack_file} not found" unless File.exist?(stack_file)

    domain = YAML.load_file(stack_file).dig("config", "IRM-infra:domain_name") or
      raise "domain_name missing in #{stack_file}"
    base_domain = domain.sub(/\A\*\./, "")
    # Same host convention as ses_bounce_tracking.derive_webhook_host:
    # production -> app.<domain>, staging -> dev.<domain>
    record_name = args[:record_name] || "#{stack == 'production' ? 'app' : 'dev'}.#{base_domain}"

    # ALB endpoint straight from the stack's own outputs (never a stale file)
    pulumi_output = pulumi_stack_output("#{stack}-#{region}")
    alb = pulumi_output["alb"] or
      raise "Stack #{stack}-#{region} has no 'alb' output — run pulumi up on it first (needs the updated outputs.py)"

    # Hosted zone for the base domain
    zone_id, err, status = Open3.capture3(
      "aws", "route53", "list-hosted-zones-by-name",
      "--dns-name", base_domain, "--max-items", "1",
      "--query", "HostedZones[0].Id", "--output", "text"
    )
    zone_id = zone_id.strip.sub("/hostedzone/", "")
    raise "Could not find hosted zone for #{base_domain}: #{err}" if !status.success? || zone_id.empty? || zone_id == "None"

    # Show where the record points today, so the operator sees the change
    current, _err, _status = Open3.capture3(
      "aws", "route53", "list-resource-record-sets",
      "--hosted-zone-id", zone_id,
      "--query", "ResourceRecordSets[?Name=='#{record_name}.']",
      "--output", "json"
    )
    puts "🔎 Current record for #{record_name}:"
    puts current.strip.empty? ? "  (none)" : current
    puts "\n➡️  Will UPSERT alias: #{record_name} -> #{alb['dns_name']} (ALB zone #{alb['zone_id']})"
    puts "Type 'yes' to proceed with the DNS cutover, anything else aborts:"
    raise "Aborted by operator." unless STDIN.gets.to_s.strip.downcase == "yes"

    change_batch = {
      "Comment" => "DR/landing-zone cutover to #{stack}-#{region} via rake aws:dns_cutover",
      "Changes" => [{
        "Action" => "UPSERT",
        "ResourceRecordSet" => {
          "Name" => record_name,
          "Type" => "A",
          "AliasTarget" => {
            "DNSName" => alb["dns_name"],
            "HostedZoneId" => alb["zone_id"],
            "EvaluateTargetHealth" => false
          }
        }
      }]
    }
    _out, err, status = Open3.capture3(
      "aws", "route53", "change-resource-record-sets",
      "--hosted-zone-id", zone_id,
      "--change-batch", change_batch.to_json
    )
    raise "DNS cutover failed: #{err}" unless status.success?

    puts "✅ #{record_name} now aliases the #{stack}-#{region} ALB. Propagation is TTL-bound; verify with: dig #{record_name}"
  end

  # Pre-cutover EDGE check: hits the recovered stack's ALB directly (no DNS
  # involved) with the real Host header — proving ALB → target group → nginx →
  # puma → MySQL end-to-end BEFORE aws:dns_cutover points customers at it.
  # Complements `cap <stage> recovery:verify`, which checks from INSIDE the
  # servers; this is the only check that exercises the load balancer itself.
  #   rake "aws:dr_verify_edge[staging, ap-south-2]"
  desc "Curl the recovered stack's ALB directly (run before aws:dns_cutover)"
  task :dr_verify_edge, [:stack, :region] do |t, args|
    require 'yaml'
    require 'json'
    require 'open3'

    stack = args[:stack] or raise "stack required (production|staging)"
    region = args[:region] or raise "region required, e.g. ap-south-2"

    # Same conventions as dns_cutover: domain from the target stack's Pulumi
    # config, host record app.<domain> (production) / dev.<domain> (staging)
    stack_file = "../IRM-Infra/Pulumi.#{stack}-#{region}.yaml"
    raise "#{stack_file} not found" unless File.exist?(stack_file)

    domain = YAML.load_file(stack_file).dig("config", "IRM-infra:domain_name") or
      raise "domain_name missing in #{stack_file}"
    host = "#{stack == 'production' ? 'app' : 'dev'}.#{domain.sub(/\A\*\./, '')}"

    # ALB endpoint straight from the stack's own outputs (never a stale file)
    alb = pulumi_stack_output("#{stack}-#{region}")["alb"] or
      raise "Stack #{stack}-#{region} has no 'alb' output — run pulumi up on it first"

    # -k: the ALB cert is issued for <host>, but we're dialing the raw ALB DNS
    # name — SNI mismatch is expected pre-DNS and not a failure
    url = "https://#{alb['dns_name']}/health_check/db_check.json"
    puts "→ GET #{url} (Host: #{host})"
    code = `curl -sk -o /dev/null -w "%{http_code}" --max-time 60 -H "Host: #{host}" #{url}`.strip
    if code == "200"
      puts "✅ Edge OK — ALB → app → DB round-trip returned 200. Safe to run aws:dns_cutover."
    else
      abort "❌ Edge check FAILED — HTTP #{code} from #{url}. " \
            "Check ALB target-group health and run `cap <stage> recovery:verify` before any cutover."
    end
  end

  task :get_latest_ami, [:name_tag, :region, :env_name] do |t, args|
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(args[:env_name])
    args.with_defaults(region: ENV["AWS_REGION"])
    latest_ami = latest_ami(args[:name_tag], args[:region])
  end

  desc "Copy an AMI to a different region"
  task :copy_ami, [:ami_id, :destination_region, :env_name] do |t, args|
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(args[:env_name])
    # Prioritize ami_id from args, then from environment variable
    ami_id = args[:ami_id] || ENV["ami_id"]
    destination_region = args[:destination_region] || ENV["AWS_BACKUP_REGION"] # Default destination region

    # Ensure ami_id is present
    unless ami_id
      raise "AMI ID is missing. Please provide it as an argument (e.g., rake aws:copy_ami[ami-xxxxxxxxxxxxxxxxx]) or as an environment variable (e.g., ami_id=ami-xxxxxxxxxxxxxxxxx rake aws:copy_ami)."
    end

    copy_ami(ami_id, destination_region)
  end

  desc "Create an AMI and copy it to another region"
  task :create_and_copy_ami, [:instance_name, :destination_region, :env_name] do |t, args|
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(args[:env_name])
    args.with_defaults(destination_region: ENV["AWS_BACKUP_REGION"])

    # Create an AMI from the instance name
    puts "📦 Creating and copying AMI: #{args}"
    ami_id = create_ami_from_snapshot(args)
    # Copy the AMI to the destination region
    copy_ami(ami_id, args[:destination_region])
    # Clean up old AMIs
    cleanup_amis(args[:instance_name], Aws.config[:region])
    cleanup_amis(args[:instance_name], args[:destination_region])
  end


  desc "Delete old AMIs with the same name pattern"
  task :delete_old_amis, [:name_tag, :region, :env_name] do |t, args|
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(args[:env_name])
    args.with_defaults(region: ENV["AWS_REGION"])
    cleanup_amis(args[:name_tag], args[:region])
  end

  desc "Create an AMI from a named EC2 instance"
  task :create_ami, [:instance_name, :env_name] do |t, args|
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(args[:env_name])
    create_ami_from_snapshot(args)
  end

    task :environment, [:env_name] do |t, args|
    env_name = args[:env_name]

    if env_name
      env_file = ".env.#{env_name}"
      if File.exist?(env_file)
        Dotenv.overload(env_file)
        puts "✅ Overloaded environment variables from #{env_file}"
      else
        puts "⚠️  Environment file not found: #{env_file}"
      end
    end

    credentials = if env_name
                    key_path = Rails.root.join("config", "credentials", "#{env_name}.key")
                    unless File.exist?(key_path)
                      raise "Key file not found for environment '#{env_name}' at #{key_path}"
                    end
                    Rails.application.encrypted(
                      Rails.root.join("config", "credentials", "#{env_name}.yml.enc"),
                      key_path: key_path
                    )
                  else
                    Rails.application.credentials
                  end

    puts "🔑 Configuring AWS SDK for region #{ENV['AWS_REGION']}"
    Aws.config.update({
      region: ENV["AWS_REGION"],
      access_key_id: credentials[:AWS_ACCESS_KEY_ID],
      secret_access_key: credentials[:AWS_SECRET_ACCESS_KEY],
    })
  end


  desc "Provision and replicate S3 buckets"
  task :provision_s3_buckets, [:env_name] do |t, args|
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(args[:env_name])
    require "aws-sdk-s3"

    source_bucket  = ENV.fetch("AWS_S3_BUCKET")
    db_backup_xtra_bucket = "#{source_bucket}-backup-xtra"
    replica_bucket = ENV.fetch("AWS_S3_BUCKET_REPLICA")
    # AWS_S3_BUCKET_REPLICA_XTRA overrides the conventional name for envs whose
    # replica backup bucket was created off-convention (e.g. IN production's
    # "docs.caphive.com.production-backup-xtra-ap-south2"). Must stay in sync
    # with DbBackupFreshnessJob, which monitors the same bucket.
    replica_db_backup_xtra_bucket = ENV.fetch("AWS_S3_BUCKET_REPLICA_XTRA", "#{replica_bucket}-backup-xtra")

    # Allow source & replica to live in different regions
    source_region  = ENV.fetch("AWS_S3_REGION")                            # e.g., "us-east-1"
    replica_region = ENV.fetch("AWS_S3_REPLICA_REGION", source_region)     # e.g., "us-east-1"


    # Build per-region clients
    s3 = {
      source:  Aws::S3::Client.new(region: source_region),
      replica: Aws::S3::Client.new(region: replica_region),
      db_backup_xtra: Aws::S3::Client.new(region: source_region),
      replica_db_backup_xtra: Aws::S3::Client.new(region: replica_region)
    }

    def ensure_bucket!(client:, bucket:, region:)
      begin
        client.head_bucket(bucket: bucket)
        puts "✅ Bucket '#{bucket}' already exists in (client) region #{region}."
      rescue Aws::S3::Errors::NotFound, Aws::S3::Errors::NoSuchBucket
        # Create with correct us-east-1 handling
        if region == "us-east-1"
          client.create_bucket(bucket: bucket)
        else
          client.create_bucket(
            bucket: bucket,
            create_bucket_configuration: { location_constraint: region }
          )
        end
        puts "🪣 Created bucket '#{bucket}' in #{region}."
      rescue Aws::S3::Errors::Http301Error => e
        # Existing bucket but different region than client; show the actual region to fix envs
        actual = e.context.http_response.headers["x-amz-bucket-region"] rescue nil
        raise "Bucket '#{bucket}' exists in region '#{actual}'. Use a client in that region."
      end

      # Versioning is required for replication
      client.put_bucket_versioning(
        bucket: bucket,
        versioning_configuration: { status: "Enabled" }
      )
      puts "📜 Enabled versioning on '#{bucket}'."
    end

    # Ensure both buckets exist + versioning on
    ensure_bucket!(client: s3[:source],  bucket: source_bucket,  region: source_region)
    ensure_bucket!(client: s3[:replica], bucket: replica_bucket, region: replica_region)
    ensure_bucket!(client: s3[:db_backup_xtra], bucket: db_backup_xtra_bucket, region: source_region)
    ensure_bucket!(client: s3[:replica_db_backup_xtra], bucket: replica_db_backup_xtra_bucket, region: replica_region)

    # --- Replication IAM role (idempotent) -----------------------------------
    # One role per env, allowed to read both source buckets and write both
    # replica buckets. create_role is guarded; put_role_policy is an upsert.
    def ensure_replication_role!(iam:, role_name:, source_buckets:, dest_buckets:)
      trust_policy = {
        Version: "2012-10-17",
        Statement: [{ Effect: "Allow", Principal: { Service: "s3.amazonaws.com" }, Action: "sts:AssumeRole" }]
      }
      begin
        iam.create_role(role_name: role_name, assume_role_policy_document: trust_policy.to_json)
        puts "🔐 Created S3 replication role '#{role_name}'."
      rescue Aws::IAM::Errors::EntityAlreadyExists
        puts "✅ Replication role '#{role_name}' already exists."
      end

      # Standard minimal permission set for S3 replication (source read side +
      # destination replicate side)
      permission_policy = {
        Version: "2012-10-17",
        Statement: [
          { Effect: "Allow",
            Action: ["s3:GetReplicationConfiguration", "s3:ListBucket"],
            Resource: source_buckets.map { |b| "arn:aws:s3:::#{b}" } },
          { Effect: "Allow",
            Action: ["s3:GetObjectVersionForReplication", "s3:GetObjectVersionAcl", "s3:GetObjectVersionTagging"],
            Resource: source_buckets.map { |b| "arn:aws:s3:::#{b}/*" } },
          { Effect: "Allow",
            Action: ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"],
            Resource: dest_buckets.map { |b| "arn:aws:s3:::#{b}/*" } }
        ]
      }
      iam.put_role_policy(role_name: role_name, policy_name: "s3-replication", policy_document: permission_policy.to_json)
      iam.get_role(role_name: role_name).role.arn
    end

    # --- Replication config (idempotent, never clobbers) ---------------------
    # If the source bucket already replicates to the expected destination we
    # leave the existing (possibly hand-tuned) config untouched. If it
    # replicates somewhere ELSE we warn and skip rather than overwrite —
    # already-configured regions are never silently changed.
    def ensure_replication!(client:, source_bucket:, dest_bucket:, role_arn:)
      # Some envs (e.g. staging) set AWS_S3_BUCKET_REPLICA equal to the source
      # bucket — S3 rejects self-replication. Skip loudly instead of aborting:
      # the env needs a real replica bucket configured for DR to mean anything.
      if source_bucket == dest_bucket
        puts "⚠️  Skipping replication for '#{source_bucket}': AWS_S3_BUCKET_REPLICA equals AWS_S3_BUCKET."
        puts "   Set a distinct replica bucket (+ AWS_S3_REPLICA_REGION) in the env to enable cross-region DR copies."
        return
      end

      dest_arn = "arn:aws:s3:::#{dest_bucket}"
      begin
        existing = client.get_bucket_replication(bucket: source_bucket).replication_configuration
        existing_dests = existing.rules.map { |r| r.destination.bucket }
        if existing_dests.include?(dest_arn)
          puts "✅ Replication #{source_bucket} → #{dest_bucket} already configured — leaving as-is."
        else
          puts "⚠️  #{source_bucket} already replicates to #{existing_dests.join(', ')} but not to #{dest_bucket}."
          puts "   Not overwriting an existing replication config — reconcile manually if this is unexpected."
        end
        return
      rescue Aws::S3::Errors::ReplicationConfigurationNotFoundError
        # No config yet — fall through and create it
      end

      client.put_bucket_replication(
        bucket: source_bucket,
        replication_configuration: {
          role: role_arn,
          rules: [{
            id: "irm-replicate-all",
            status: "Enabled",
            priority: 1,
            # Deletes are deliberately NOT replicated: a bad delete (or ransomware)
            # on the source must not propagate to the DR copy
            delete_marker_replication: { status: "Disabled" },
            filter: {}, # whole bucket
            destination: { bucket: dest_arn }
          }]
        }
      )
      puts "🔁 Replication configured: #{source_bucket} → #{dest_bucket}."
      puts "   ℹ️  Replication covers NEW objects only — backfill existing ones with"
      puts "   aws s3 sync s3://#{source_bucket} s3://#{dest_bucket} (or S3 Batch Replication)."
    end

    # --- CORS (idempotent, never clobbers) ------------------------------------
    # Existing CORS (possibly hand-tuned in already-live regions) is left alone;
    # only buckets with no CORS at all get the default rules.
    def ensure_cors!(client:, bucket:, origins:)
      begin
        client.get_bucket_cors(bucket: bucket)
        puts "✅ CORS already configured on '#{bucket}' — leaving as-is."
        return
      rescue Aws::S3::Errors::NoSuchCORSConfiguration
        # No CORS yet — apply the default below
      end

      client.put_bucket_cors(
        bucket: bucket,
        cors_configuration: {
          cors_rules: [{
            allowed_methods: %w[GET PUT POST HEAD],
            allowed_origins: origins,
            allowed_headers: ["*"],
            expose_headers: ["ETag"],
            max_age_seconds: 3000
          }]
        }
      )
      puts "🌐 CORS applied to '#{bucket}' (origins: #{origins.join(', ')})."
    end

    # Role + both replication pairs (app assets and xtrabackup DB backups —
    # the latter is what makes DB backups survive a region loss)
    require "aws-sdk-iam"
    iam = Aws::IAM::Client.new
    # IAM role names are capped at 64 chars — truncate defensively
    role_arn = ensure_replication_role!(
      iam: iam,
      role_name: "irm-s3-replication-#{source_bucket}"[0, 64],
      source_buckets: [source_bucket, db_backup_xtra_bucket],
      dest_buckets: [replica_bucket, replica_db_backup_xtra_bucket]
    )
    ensure_replication!(client: s3[:source], source_bucket: source_bucket, dest_bucket: replica_bucket, role_arn: role_arn)
    ensure_replication!(client: s3[:db_backup_xtra], source_bucket: db_backup_xtra_bucket, dest_bucket: replica_db_backup_xtra_bucket, role_arn: role_arn)

    # CORS on the app-assets buckets only (browser uploads/downloads); backup
    # buckets are never touched by browsers. Origins: S3_CORS_ORIGINS (comma-
    # separated) wins, else derived from BASE_DOMAIN, else "*" with a warning.
    cors_origins =
      if ENV["S3_CORS_ORIGINS"].to_s.strip != ""
        ENV["S3_CORS_ORIGINS"].split(",").map(&:strip)
      elsif ENV["BASE_DOMAIN"].to_s.strip != ""
        ["https://*.#{ENV['BASE_DOMAIN']}", "https://#{ENV['BASE_DOMAIN']}"]
      else
        puts "⚠️  Neither S3_CORS_ORIGINS nor BASE_DOMAIN set — defaulting CORS origins to '*'."
        ["*"]
      end
    ensure_cors!(client: s3[:source],  bucket: source_bucket,  origins: cors_origins)
    ensure_cors!(client: s3[:replica], bucket: replica_bucket, origins: cors_origins)

    # --- Retention lifecycle on the BACKUP buckets (idempotent, never clobbers)
    # Replaces the unimplemented ">30 days cleanup" TODO in db_backup_xtra.sh:
    # lifecycle rules run inside S3, so retention cannot silently stop when a
    # server is rebuilt or a cron dies. Applied to both backup buckets — S3 does
    # NOT replicate lifecycle actions, so the replica needs its own copy.
    # App-asset buckets are deliberately excluded (assets are kept forever).
    def ensure_lifecycle!(client:, bucket:, days:)
      begin
        client.get_bucket_lifecycle_configuration(bucket: bucket)
        puts "✅ Lifecycle already configured on '#{bucket}' — leaving as-is."
        return
      rescue Aws::S3::Errors::NoSuchLifecycleConfiguration
        # No lifecycle yet — apply the retention rule below
      end

      client.put_bucket_lifecycle_configuration(
        bucket: bucket,
        lifecycle_configuration: {
          rules: [{
            id: "irm-backup-retention-#{days}d",
            status: "Enabled",
            filter: {}, # whole bucket
            # Current backups expire after the retention window. A nightly full
            # means ~#{days} restore points are always available.
            expiration: { days: days },
            # The buckets are versioned (required for replication), so expired/
            # deleted objects linger as noncurrent versions and keep costing
            # money — purge those 30 days after they become noncurrent.
            noncurrent_version_expiration: { noncurrent_days: 30 },
            # xbcloud uploads via multipart; failed uploads leave invisible,
            # billed parts behind — abort them after a week.
            abort_incomplete_multipart_upload: { days_after_initiation: 7 }
          }]
        }
      )
      puts "🗓️  Lifecycle applied to '#{bucket}': expire after #{days}d, purge noncurrent versions after 30d."
    end

    retention_days = ENV.fetch("DB_BACKUP_RETENTION_DAYS", "90").to_i
    ensure_lifecycle!(client: s3[:db_backup_xtra], bucket: db_backup_xtra_bucket, days: retention_days)
    ensure_lifecycle!(client: s3[:replica_db_backup_xtra], bucket: replica_db_backup_xtra_bucket, days: retention_days)

    # --- Default encryption at rest (idempotent, never clobbers) --------------
    # Buckets created after Jan 2023 get SSE-S3 automatically, but older ones
    # may have nothing — and the DB backups (full plaintext dumps of the
    # database) must never sit unencrypted. Any existing encryption config
    # (SSE-S3 or a hand-configured SSE-KMS) is left untouched; only buckets
    # with NO encryption get AES256. SSE-S3 over SSE-KMS deliberately: zero
    # key management, no extra KMS grants needed for replication, and the
    # instance-role IAM stays as scoped as Point 5 left it.
    # NOTE: applies to newly written objects only — pre-existing objects stay
    # as they were (they age out via the 90d lifecycle anyway).
    def ensure_encryption!(client:, bucket:)
      begin
        client.get_bucket_encryption(bucket: bucket)
        puts "✅ Encryption already configured on '#{bucket}' — leaving as-is."
        return
      rescue Aws::S3::Errors::ServerSideEncryptionConfigurationNotFoundError
        # No encryption at all (pre-2023 bucket) — apply SSE-S3 below
      end

      client.put_bucket_encryption(
        bucket: bucket,
        server_side_encryption_configuration: {
          rules: [{ apply_server_side_encryption_by_default: { sse_algorithm: "AES256" } }]
        }
      )
      puts "🔒 Default SSE-S3 encryption applied to '#{bucket}'."
    end

    # All four buckets: assets + DB backups, source + replica
    ensure_encryption!(client: s3[:source],  bucket: source_bucket)
    ensure_encryption!(client: s3[:replica], bucket: replica_bucket)
    ensure_encryption!(client: s3[:db_backup_xtra], bucket: db_backup_xtra_bucket)
    ensure_encryption!(client: s3[:replica_db_backup_xtra], bucket: replica_db_backup_xtra_bucket)

    puts "✅ Buckets provisioned: versioning, cross-region replication, CORS and backup retention are all codified."
    puts "   Safe to re-run anytime — existing configs in live regions are never overwritten."
  end
  desc "Generate Prometheus configuration (prometheus.yml) with EC2 instance IPs"
  task :generate_prometheus_yml, [:env_name] do |t, args|
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(args[:env_name])
    require "yaml"

    ec2 = Aws::EC2::Client.new

    def fetch_instance_ips(ec2, filters)
      resp = ec2.describe_instances(filters: filters)
      resp.reservations.flat_map do |res|
        res.instances.map(&:private_ip_address).compact
      end
    end

    app_ips = fetch_instance_ips(ec2, [{ name: "tag:Name", values: ["AppServer"] }])
    db_ips  = fetch_instance_ips(ec2, [{ name: "tag:Name", values: ["DB-Redis-ES"] }])

    puts "📝 Generating Prometheus config with the following IPs:"
    puts "📦 App Server IPs: #{app_ips.join(", ")}"
    puts "📦 DB Server IPs: #{db_ips.join(", ")}"

    prometheus_config = {
      "global" => { "scrape_interval" => "15s" },
      "scrape_configs" => [
        {
          "job_name" => "rails_app",
          "static_configs" => [
            { "targets" => app_ips.map { |ip| "#{ip}:9394" } }
          ]
        },
        {
          "job_name" => "node",
          "static_configs" => [
            { "targets" => (app_ips + db_ips).uniq.map { |ip| "#{ip}:9100" } }
          ]
        },
        {
          "job_name" => "db_server",
          "static_configs" => [
            { "targets" => db_ips.flat_map { |ip| ["#{ip}:9104", "#{ip}:9114", "#{ip}:9121"] } }
          ]
        }
      ]
    }

    output_path = "config/initializers/observability/prometheus.yml"
    FileUtils.mkdir_p(File.dirname(output_path))
    require "yaml"

    # Building formatted YAML content manually for clarity and conventions
    yaml_lines = []
    yaml_lines << "global:"
    yaml_lines << "  scrape_interval: 15s  # How frequently to scrape targets (default is every 15s)"
    yaml_lines << ""
    yaml_lines << "scrape_configs:"

    rails_app_targets = app_ips.map { |ip| "'#{ip}:9394'" }.join(', ')
    node_targets = (app_ips + db_ips).uniq.map { |ip| "'#{ip}:9100'" }.join(', ')
    db_server_targets = db_ips.flat_map { |ip| ["'#{ip}:9104'", "'#{ip}:9114'", "'#{ip}:9121'"] }.join(', ')

    yaml_lines << "  - job_name: 'rails_app'"
    yaml_lines << "    static_configs:"
    yaml_lines << "      - targets: [#{rails_app_targets}]"
    yaml_lines << ""
    yaml_lines << "  - job_name: 'node'"
    yaml_lines << "    static_configs:"
    yaml_lines << "      - targets: [#{node_targets}]"
    yaml_lines << ""
    yaml_lines << "  - job_name: 'db_server'"
    yaml_lines << "    static_configs:"
    yaml_lines << "      - targets: [#{db_server_targets}]"

    formatted_yaml = yaml_lines.join("\n") + "\n"

    File.open(output_path, "w") do |f|
      f.puts "# Prometheus Configuration File"
      f.puts "# Generated automatically via rake aws:generate_prometheus_yml"
      f.puts "#"
      f.puts "# Port Reference:"
      f.puts "# 9394  - Rails Prometheus Exporter"
      f.puts "# 9100  - Node Exporter"
      f.puts "# 9104  - MySQL Exporter"
      f.puts "# 9114  - Elasticsearch Exporter"
      f.puts "# 9121  - Redis Exporter"
      f.puts "#"
      f.puts "# EC2 Instance Mapping:"
      f.puts "# AppServer IPs: #{app_ips.join(', ')}"
      f.puts "# DB_Redis_ES IPs: #{db_ips.join(', ')}"
      f.puts ""
      f.puts formatted_yaml
    end

    puts "✅ Generated annotated Prometheus config file at #{output_path}"
  end

  desc "Find and optionally delete unused security groups"
  task :cleanup_unused_security_groups, [:env_name] do |t, args|
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(args[:env_name])
    ec2 = Aws::EC2::Client.new(region: Aws.config[:region])
    puts "🔍 Fetching all security groups..."
    all_groups = ec2.describe_security_groups.security_groups

    used_group_ids = []
    puts "🔍 Collecting in-use security groups from network interfaces..."
    ec2.describe_network_interfaces.network_interfaces.each do |ni|
      used_group_ids.concat(ni.groups.map(&:group_id))
    end

    used_group_ids.uniq!
    unused = all_groups.reject do |sg|
      used_group_ids.include?(sg.group_id) || sg.group_name == "default"
    end

    if unused.empty?
      puts "✅ No unused security groups found."
      next
    end

    puts "⚠️  Found the following unused security groups:"
    unused.each do |sg|
      puts "- #{sg.group_id} (#{sg.group_name})"
    end

    print "❓ Do you want to delete these security groups? (y/N): "
    confirm = $stdin.gets.chomp
    if confirm.downcase == "y"
      unused.each do |sg|
        begin
          ec2.delete_security_group(group_id: sg.group_id)
          puts "🗑️  Deleted #{sg.group_id} (#{sg.group_name})"
        rescue Aws::EC2::Errors::DependencyViolation => e
          puts "⚠️  Could not delete #{sg.group_id} (in use or dependency violation)"
        end
      end
      puts "✅ Cleanup complete."
    else
      puts "❎ Cleanup aborted by user."
    end
  end

  desc "Find and optionally delete unused VPCs and subnets"
  task :cleanup_unused_vpcs_and_subnets, [:env_name] do |t, args|
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(args[:env_name])
    ec2 = Aws::EC2::Client.new(region: Aws.config[:region])

    # --- Find Unused Subnets ---
    puts "🔍 Fetching all subnets and network interfaces..."
    all_subnets = ec2.describe_subnets.subnets
    all_network_interfaces = ec2.describe_network_interfaces.network_interfaces
    used_subnet_ids = all_network_interfaces.map(&:subnet_id).uniq
    unused_subnets = all_subnets.reject { |s| used_subnet_ids.include?(s.subnet_id) }

    # --- Find Unused VPCs ---
    puts "🔍 Fetching all VPCs..."
    all_vpcs = ec2.describe_vpcs.vpcs.reject(&:is_default)
    # A VPC is considered in use if it has any network interfaces associated with it.
    # This is a strong indicator of active resources (instances, LBs, etc.).
    used_vpc_ids = all_network_interfaces.map(&:vpc_id).uniq
    unused_vpcs = all_vpcs.reject { |v| used_vpc_ids.include?(v.vpc_id) }

    if unused_subnets.empty? && unused_vpcs.empty?
      puts "✅ No unused subnets or VPCs found."
      next
    end

    puts "⚠️  Found the following unused resources:"
    unused_subnets.each do |s|
      subnet_name = s.tags.find { |t| t.key == "Name" }&.value || "N/A"
      puts "- Subnet: #{s.subnet_id} (Name: #{subnet_name}, VPC: #{s.vpc_id}, CIDR: #{s.cidr_block})"
    end
    unused_vpcs.each do |v|
      vpc_name = v.tags.find { |t| t.key == "Name" }&.value || "N/A"
      puts "- VPC: #{v.vpc_id} (Name: #{vpc_name}, CIDR: #{v.cidr_block})"
    end

    print "❓ Do you want to delete these resources? (y/N): "
    confirm = $stdin.gets.chomp
    if confirm.downcase == "y"
      # Delete subnets first
      unused_subnets.each do |s|
        begin
          ec2.delete_subnet(subnet_id: s.subnet_id)
          puts "🗑️  Deleted Subnet #{s.subnet_id}"
        rescue => e
          puts "⚠️  Could not delete Subnet #{s.subnet_id}: #{e.message}"
        end
      end

      # Then delete VPCs
      unused_vpcs.each do |v|
        begin
          ec2.delete_vpc(vpc_id: v.vpc_id)
          puts "🗑️  Deleted VPC #{v.vpc_id}"
        rescue Aws::EC2::Errors::DependencyViolation => e
          puts "⚠️  Could not delete VPC #{v.vpc_id}. It may still have dependencies (like Internet Gateways or Route Tables) that must be removed manually."
        rescue => e
          puts "⚠️  Could not delete VPC #{v.vpc_id}: #{e.message}"
        end
      end
      puts "✅ Cleanup complete."
    else
      puts "❎ Cleanup aborted by user."
    end
  end
  def find_groups_with_open_port(ec2_client, port)
    open_groups = []
    ec2_client.describe_security_groups.security_groups.each do |sg|
      sg.ip_permissions.each do |perm|
        next unless perm.from_port == port && perm.to_port == port && perm.ip_protocol == "tcp"

        if perm.ip_ranges.any? { |range| range.cidr_ip == "0.0.0.0/0" }
          open_groups << { id: sg.group_id, name: sg.group_name }
          break
        end
      end
    end
    open_groups
  end

  desc "Manage SSH access (port 22). Actions: list, suspend, resume. Use force=true for non-interactive mode. ex: bundle exec rake 'aws:manage_ssh[suspend,staging.in,true]'"
  task :manage_ssh, [:action, :env_name, :force] do |t, args|
    # Manually invoke the environment task with the provided env_name
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(args[:env_name])

    action = args[:action] || "list"
    puts "🔑 Managing SSH access with action: #{action} for region #{ENV['AWS_REGION']}"
    ec2 = Aws::EC2::Client.new()

    case action
    when "list"
      puts "🔍 Finding security groups with SSH (port 22) open to 0.0.0.0/0..."
      open_groups = find_groups_with_open_port(ec2, 22)

      if open_groups.empty?
        puts "✅ No security groups with unrestricted SSH access found."
      else
        puts "⚠️  Found the following security groups with open SSH access:"
        open_groups.each do |sg|
          puts "- #{sg[:id]} (#{sg[:name]})"
        end
      end

    when "suspend"
      puts "🔍 Finding security groups with SSH open to suspend..."
      open_groups = find_groups_with_open_port(ec2, 22)

      if open_groups.empty?
        puts "✅ No security groups with unrestricted SSH access to suspend."
        next
      end

      puts "⚠️  The following security groups have SSH open to the world:"
      open_groups.each { |sg| puts "- #{sg[:id]} (#{sg[:name]})" }

      force = args[:force].to_s.downcase == 'true'
      confirmed = if force
                    true
                  else
                    print "❓ Do you want to suspend SSH access (move to port 22222) for these groups? (y/N): "
                    $stdin.gets.chomp.downcase == "y"
                  end

      if confirmed
        open_groups.each do |sg|
          begin
            ec2.revoke_security_group_ingress(group_id: sg[:id], ip_permissions: [{ ip_protocol: "tcp", from_port: 22, to_port: 22, ip_ranges: [{ cidr_ip: "0.0.0.0/0" }] }])
            ec2.authorize_security_group_ingress(group_id: sg[:id], ip_permissions: [{ ip_protocol: "tcp", from_port: 22222, to_port: 22222, ip_ranges: [{ cidr_ip: "0.0.0.0/0" }] }])
            puts "🔒 Suspended SSH for #{sg[:id]} (#{sg[:name]})"
          rescue => e
            puts "❌ Failed to suspend SSH for #{sg[:id]}: #{e.message}"
          end
        end
        puts "✅ SSH suspension complete."
      else
        puts "❎ Aborted by user."
      end

    when "resume"
      puts "🔍 Finding security groups with suspended SSH to resume..."
      suspended_groups = find_groups_with_open_port(ec2, 22222)

      if suspended_groups.empty?
        puts "✅ No security groups with suspended SSH access found."
        next
      end

      puts "⚠️  The following security groups have suspended SSH access (on port 22222):"
      suspended_groups.each { |sg| puts "- #{sg[:id]} (#{sg[:name]})" }

      force = args[:force].to_s.downcase == 'true'
      confirmed = if force
                    true
                  else
                    print "❓ Do you want to resume SSH access (move back to port 22) for these groups? (y/N): "
                    $stdin.gets.chomp.downcase == "y"
                  end

      if confirmed
        suspended_groups.each do |sg|
          begin
            ec2.revoke_security_group_ingress(group_id: sg[:id], ip_permissions: [{ ip_protocol: "tcp", from_port: 22222, to_port: 22222, ip_ranges: [{ cidr_ip: "0.0.0.0/0" }] }])
            ec2.authorize_security_group_ingress(group_id: sg[:id], ip_permissions: [{ ip_protocol: "tcp", from_port: 22, to_port: 22, ip_ranges: [{ cidr_ip: "0.0.0.0/0" }] }])
            puts "🔓 Resumed SSH for #{sg[:id]} (#{sg[:name]})"
          rescue => e
            puts "❌ Failed to resume SSH for #{sg[:id]}: #{e.message}"
          end
        end
        puts "✅ SSH resumption complete."
      else
        puts "❎ Aborted by user."
      end
    else
      puts "❌ Invalid action '#{action}'. Available actions: list, suspend, resume."
    end
  end
end