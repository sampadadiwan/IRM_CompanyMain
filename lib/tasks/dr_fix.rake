#  dr:fix:* — repair ONE component, touch nothing else
# =============================================================================
# Phase 3 of component recovery (see docs/DR_COMPONENT_RECOVERY.md).
#
# Always run rake "dr:assess[<env>]" first: it names the broken component and
# the cheapest rung that fixes it. These tasks execute one rung.
#
# The rules every task here follows, and why:
#
#  1. ISOLATION IS ENFORCED, NOT PROMISED. Pulumi steps run `pulumi preview
#     --json` against an exact URN list and ABORT if the preview contains any
#     operation beyond those URNs. Config drift sitting in the stack — a
#     refreshed app-server AMI id, say — cannot ride along on a repair.
#  2. PULUMI IS PRINT-ONLY. The exact targeted command is printed and a human
#     runs it. Nothing here mutates AWS through pulumi.
#  3. HOST-FILTERED. Capistrano steps carry HOSTS=<ip>, so a healthy app server
#     is never restarted while its neighbour is being repaired.
#  4. BRANCH FROM WHAT IS DEPLOYED. Any repair needing a deploy first checks
#     that local HEAD matches the revision the app servers are running, so an
#     incident deploy cannot carry unreleased work.
#  5. ONE COMPONENT PER RUN. Re-assess between repairs.
# =============================================================================

require_relative "aws_utils"

include AwsUtils # pulumi_stack_output / commit_dr_changes / run_cmd

# Resolve a running app server's IP to the Pulumi resources that own it: the
# EC2 instance AND its target-group attachment.
#
# Both are required. alb.py creates one TargetGroupAttachment per instance,
# named after the instance; replacing the instance alone with
# --target-dependents=false leaves the attachment pointing at the OLD instance
# id, so the new box never joins the target group and the ALB quietly serves on
# one server. Documented as finding #1 in DR_COMPONENT_RECOVERY.md.
def dr_fix_app_server_urns(resources, ip)
  # `delete: true` marks a pending-deletion leftover from an interrupted update.
  # Staging carries one, and matching it would aim the repair at a resource on
  # its way out of the stack.
  matches = resources.select do |r|
    r["type"] == "aws:ec2/instance:Instance" && !r["delete"] &&
      [r.dig("outputs", "publicIp"), r.dig("outputs", "privateIp")].include?(ip)
  end
  raise "No EC2 instance with address #{ip} in this Pulumi stack — is the IP right, and has pulumi up run?" if matches.empty?
  if matches.size > 1
    raise "#{matches.size} live instances in the state claim address #{ip} " \
          "(#{matches.map { |m| m.dig('outputs', 'id') }.join(', ')}) — reconcile the stack before repairing."
  end

  instance = matches.first

  instance_id = instance.dig("outputs", "id")
  # Match the attachment by the instance id it actually points at rather than by
  # name-mangling the URN: the attachment's own name is derived from the
  # instance's Pulumi name, but its targetId is the fact we care about.
  attachment = resources.find do |r|
    r["type"] == "aws:lb/targetGroupAttachment:TargetGroupAttachment" &&
      r.dig("outputs", "targetId") == instance_id
  end

  { instance_urn: instance["urn"], instance_id: instance_id, attachment_urn: attachment&.dig("urn") }
end

# Run a targeted `pulumi preview` and refuse to continue if it would touch
# anything outside `urns`. This is the mechanism behind "does not impact any
# other component" — a promise the operator can see enforced rather than trust.
#
# Untargeted resources appear in a targeted preview as op "same"; anything else
# on a URN we did not ask for is unexpected drift and stops the repair.
def dr_fix_preview_guard!(pulumi_stack, urns)
  require "json"
  require "open3"

  target_args = urns.compact.map { |u| "--target '#{u}'" }.join(" ")
  cmd = "pulumi preview --json --stack #{pulumi_stack} #{target_args} --target-dependents=false"

  puts "🔎 Previewing the targeted change (read-only)..."
  puts "   #{cmd}"
  out, err, status = Open3.capture3(cmd, chdir: "../IRM-Infra")
  raise "pulumi preview failed: #{err.to_s.lines.first(3).join(' ')}" unless status.success?

  steps = JSON.parse(out)["steps"] || []
  changes = steps.reject { |s| s["op"] == "same" }
  stray = changes.reject { |s| urns.compact.include?(s["urn"]) }

  if stray.any?
    puts "\n❌ ABORT — the preview would change resources this repair did not target:"
    stray.each { |s| puts "   #{s['op'].upcase}  #{s['urn']}" }
    puts "\n   That is stack drift (often a refreshed AMI id), NOT part of this repair."
    puts "   It is left untouched deliberately. Resolve it separately, then re-run."
    abort ""
  end

  # An EMPTY change set is not success — it is the signature of stale state.
  # When an instance is terminated out-of-band (the usual reason we are here),
  # Pulumi still believes it exists until the state is refreshed, so preview
  # reports every URN as "same". Proceeding would print a pulumi command that
  # rebuilds nothing, then deploy to a box that does not exist.
  if changes.empty?
    puts "\n❌ ABORT — the preview shows NO changes for the targeted resources."
    puts "   Pulumi's state still believes this resource is healthy, which is expected when a box"
    puts "   was terminated outside Pulumi. Refresh the state for these resources first (read-only"
    puts "   against AWS, it only updates Pulumi's view), then re-run this task:"
    puts ""
    puts "     cd ../IRM-Infra && pulumi refresh --stack #{pulumi_stack} #{target_args} --yes"
    abort ""
  end

  puts "✅ Preview is clean — #{changes.size} operation(s), all on targeted resources:"
  changes.each { |s| puts "   #{s['op'].upcase}  #{s['urn']}" }
  changes
end

# Print the exact command for the operator to run and wait. Pulumi is
# print-only by design: a human stays between an incident and an AWS mutation.
def dr_fix_await_pulumi!(pulumi_stack, urns)
  target_args = urns.compact.map { |u| "--target '#{u}'" }.join(" ")
  puts "\n" + ("=" * 78)
  puts "👉 RUN THIS NOW, in another terminal, from the IRM-Infra checkout:"
  puts ""
  puts "   cd ../IRM-Infra && pulumi up --stack #{pulumi_stack} \\"
  puts "     #{target_args} --target-dependents=false --yes"
  puts ""
  puts "=" * 78
  print "Type 'done' when the pulumi run has finished (anything else aborts): "
  answer = STDIN.gets.to_s.strip.downcase
  abort "\n❌ Aborted by operator — nothing has been changed by this task." unless answer == "done"
end

# First app server that answers SSH. Both the DB boxes and the observability box
# accept SSH only from web-sg (security_groups.py), so every repair that has to
# reach them hops through one of these.
def dr_fix_live_app_host(app_ips, cap_key)
  app_ips.find do |ip|
    dr_assess_ssh(ip, cap_key, "echo up", timeout: 10) == "up"
  rescue StandardError
    nil
  end
end

# Copy a local file to a box that is only reachable via an app server, and run a
# command over it there. Base64 rather than scp-through-a-hop: the payload
# survives two levels of shell quoting untouched, and it needs no scratch file
# management on the intermediate host.
def dr_fix_push_via_app(app_host, cap_key, target_host, db_keyname, local_path, remote_command)
  require "base64"
  encoded = Base64.strict_encode64(File.read(local_path))
  dr_assess_ssh(app_host, cap_key,
                "echo #{encoded} | ssh -i ~/.ssh/#{db_keyname}.pem -o StrictHostKeyChecking=no " \
                "-o ConnectTimeout=10 ubuntu@#{target_host} 'base64 -d | #{remote_command}'",
                timeout: 60)
end

# The git revision the app servers are actually running, read from Capistrano's
# REVISION file. Used to refuse a repair that would deploy unreleased work.
def dr_fix_deployed_revision(host, key_path)
  dr_assess_ssh(host, key_path, "cat /home/ubuntu/IRM/current/REVISION 2>/dev/null").to_s.strip
end

# Point the stage file at the replacement box. A targeted substitution of the
# one address, NOT replace_ip_addresses (which rewrites every `server` line from
# a list) — this repair changes exactly one host and must leave the other line
# byte-identical. gsub rather than sub on purpose: staging_in lists the same
# address on two lines and both must move together.
def dr_fix_update_stage_host(deploy_file, old_ip, new_ip)
  content = File.read(deploy_file)
  raise "#{deploy_file} does not mention #{old_ip} — refusing to guess which line to edit" unless content.include?(old_ip)

  File.write(deploy_file, content.gsub(old_ip, new_ip))
  puts "📝 #{File.basename(deploy_file)}: #{old_ip} → #{new_ip}"
end

# Poll the ALB until the repaired instance reports healthy. A deploy that
# finished is not the same as a box that is serving.
def dr_fix_await_target_health(region, instance_id, attempts: 30, interval: 10)
  require "json"
  puts "⏳ Waiting for #{instance_id} to report healthy in its ALB target group..."
  attempts.times do |i|
    tgs, tg_err = dr_assess_aws("elbv2", "describe-target-groups", "--region", region, "--output", "json")
    # A failed CLI call returns nil, which would otherwise be coerced to "no
    # target groups" and burn every attempt reporting a health timeout instead
    # of the real AWS error (expired credentials, most often).
    if tgs.nil?
      puts "⚠️  describe-target-groups failed: #{tg_err} — cannot confirm ALB health from here."
      return false
    end

    JSON.parse(tgs)["TargetGroups"].each do |tg|
      health, health_err = dr_assess_aws("elbv2", "describe-target-health", "--target-group-arn", tg["TargetGroupArn"],
                                         "--region", region, "--output", "json")
      if health.nil?
        puts "⚠️  describe-target-health failed for #{tg['TargetGroupName']}: #{health_err}"
        next
      end

      target = JSON.parse(health)["TargetHealthDescriptions"]
               .find { |t| t.dig("Target", "Id") == instance_id }
      next unless target

      state = target.dig("TargetHealth", "State")
      if state == "healthy"
        puts "✅ #{instance_id} is healthy in #{tg['TargetGroupName']}."
        return true
      end
      puts "   #{state} (#{i + 1}/#{attempts})"
    end
    sleep interval if i < attempts - 1
  end
  puts "⚠️  #{instance_id} did not report healthy in time — check the target group and nginx/puma on the box."
  false
end

namespace :dr do
  namespace :fix do
    desc "Repair ONE app server: restart its services, or rebuild the box from AMI. Other hosts untouched."
    task :app_server, %i[env_name host] => :environment do |_t, args|
      env_name = args[:env_name] or raise "Usage: rake \"dr:fix:app_server[production.in, 35.154.185.236]\""
      target_ip = args[:host]

      env = dr_assess_resolve_env(env_name)
      dr_account_guard!(env) # wrong-account guard, before anything reads or writes
      cap_key = dr_assess_cap_key(env[:deploy_file])

      puts ""
      puts "=" * 78
      puts "🔧 DR FIX · app server · #{env_name} · #{env[:region]}"
      puts "=" * 78

      # State, not stack outputs: no live stack exports an ALB and staging's
      # outputs disagree with its own state (see dr_stack_inventory).
      inventory = dr_stack_inventory(env[:pulumi_stack])
      app_ips = inventory[:app_servers].filter_map { |i| i[:public_ip] }

      unless target_ip
        puts "\nApp servers in #{env[:pulumi_stack]}:"
        app_ips.each { |ip| puts "   • #{ip}" }
        abort "\n❌ Pass the host to repair: rake \"dr:fix:app_server[#{env_name}, #{app_ips.first}]\""
      end
      unless app_ips.include?(target_ip)
        abort "❌ #{target_ip} is not an app server in #{env[:pulumi_stack]} (have: #{app_ips.join(', ')})"
      end

      others = app_ips - [target_ip]

      # -------------------------------------------------------------------
      # 1. Is the box reachable? That single fact chooses the rung.
      # -------------------------------------------------------------------
      puts "\n🔎 Probing #{target_ip}..."
      reachable = begin
        dr_assess_ssh(target_ip, cap_key, "echo up", timeout: 10) == "up"
      rescue StandardError => e
        puts "   no SSH: #{e.class} — #{e.message.to_s.lines.first.to_s.strip}"
        false
      end

      # -------------------------------------------------------------------
      # 2a. CHEAP RUNG — the box is alive, only services are down.
      # -------------------------------------------------------------------
      if reachable
        puts "✅ #{target_ip} is reachable — repairing services in place (no pulumi, no rebuild)."

        nginx = dr_assess_ssh(target_ip, cap_key, "systemctl is-active nginx")
        if nginx != "active"
          puts "🔧 nginx is #{nginx} — validating config before starting it..."
          # Never start nginx blind: a bad config is a different failure that a
          # restart would only obscure.
          test_out = dr_assess_ssh(target_ip, cap_key, "sudo nginx -t 2>&1; echo EXIT:$?")
          if test_out.include?("EXIT:0")
            dr_assess_ssh(target_ip, cap_key, "sudo systemctl start nginx")
            puts "   nginx started."
          else
            puts "❌ nginx config is invalid on #{target_ip} — NOT starting it:"
            puts test_out.lines.map { |l| "   #{l}" }.join
            abort "   Fix the config (or redeploy) before continuing."
          end
        end

        puts "🔧 Restarting the application services on #{target_ip} only (HOSTS filter)..."
        # Host-filtered so the healthy app server keeps serving untouched.
        %w[puma:restart sidekiq:ensure_clean_restart IRM:start_boot_services].each do |task|
          ok = system("LB=true HOSTS=#{target_ip} bundle exec cap #{env[:cap_stage]} #{task}")
          puts "   #{ok ? '✅' : '❌'} cap #{task}"
        end

        code = dr_assess_ssh(target_ip, cap_key,
                             "curl -s -o /dev/null -w '%{http_code}' --max-time 30 " \
                             "-H 'Host: #{env[:app_host_header]}' http://localhost/health_check/disk_check.json")
        if code == "200"
          puts "\n🟢 #{target_ip} is serving again (HTTP 200 through nginx→puma→rails)."
          puts "   Re-assess to confirm the whole stack: rake \"dr:assess[#{env_name}]\""
        else
          puts "\n🔴 #{target_ip} still returns HTTP #{code} after restarting services."
          puts "   Next rung is a redeploy of this host:"
          puts "     LB=true HOSTS=#{target_ip} bundle exec cap #{env[:cap_stage]} deploy"
          puts "   If that fails too, rebuild it by re-running this task once the box is unreachable,"
          puts "   or terminate the instance first so the rebuild path is chosen."
          abort ""
        end
        next # done — never falls through to the rebuild path
      end

      # -------------------------------------------------------------------
      # 2b. REBUILD RUNG — the box is gone.
      # -------------------------------------------------------------------
      puts "\n🔴 #{target_ip} is unreachable — rebuilding it from the AMI."

      # Outage warning. On staging.in the deploy file lists a single distinct
      # host, so there is nothing left serving during the repair.
      healthy_other = others.find do |ip|
        dr_assess_ssh(ip, cap_key, "echo up", timeout: 10) == "up"
      rescue StandardError
        nil
      end

      if healthy_other
        puts "✅ #{healthy_other} is healthy and will keep serving — this is a rolling repair."
      else
        puts "⚠️  NO other app server is reachable. Rebuilding this one means a FULL OUTAGE,"
        puts "    and if BOTH boxes are gone this is a region-level event — see docs/DR_GUIDE.md."
        unless ENV["CONFIRM_OUTAGE"] == "true"
          abort "\n❌ Refusing to proceed without CONFIRM_OUTAGE=true (set it deliberately)."
        end
      end

      # --- resolve exactly what may change -------------------------------
      puts "\n🔎 Resolving the Pulumi resources that own #{target_ip}..."
      resources = dr_fix_stack_resources(env[:pulumi_stack])
      urns = dr_fix_app_server_urns(resources, target_ip)
      puts "   instance   #{urns[:instance_urn]}"
      if urns[:attachment_urn]
        puts "   attachment #{urns[:attachment_urn]}"
      else
        # Not fatal, but the operator must know: without it the replacement box
        # will not join the target group and the ALB will serve on one server.
        puts "⚠️  No target-group attachment found for #{urns[:instance_id]} — after the rebuild the new"
        puts "    instance may NOT join the ALB target group. See finding #1 in DR_COMPONENT_RECOVERY.md."
      end

      target_urns = [urns[:instance_urn], urns[:attachment_urn]]
      dr_fix_preview_guard!(env[:pulumi_stack], target_urns)
      dr_fix_await_pulumi!(env[:pulumi_stack], target_urns)

      # --- did the address change? ---------------------------------------
      puts "\n🔎 Reading the new address from the stack..."
      new_inventory = dr_stack_inventory(env[:pulumi_stack])
      new_ips = new_inventory[:app_servers].filter_map { |i| i[:public_ip] }
      # Exactly one address must be left once the untouched siblings are removed.
      # Zero means the stack lost a server; more than one means the output is
      # stale and still lists the dead address beside the replacement — and
      # picking arbitrarily there could deploy against the box that just died.
      candidates = new_ips - others
      if candidates.size != 1
        raise "Ambiguous replacement address: stack reports #{new_ips.join(', ')}, untouched siblings are " \
              "#{others.join(', ')} — #{candidates.size} candidate(s): #{candidates.join(', ')}. " \
              "Re-run `pulumi stack export --stack #{env[:pulumi_stack]}` and confirm the stack is settled."
      end
      new_ip = candidates.first

      # Reuse the inventory just read rather than exporting the state twice.
      new_instance_id = new_inventory[:app_servers].find { |i| i[:public_ip] == new_ip }&.dig(:id)

      # What cap should deploy. NEVER `git rev-parse --abbrev-ref HEAD`: the
      # revision guard below tells the operator to `git checkout <sha>`, which
      # leaves a DETACHED head whose abbrev-ref is the literal string "HEAD" —
      # `branch=HEAD cap deploy` then asks origin for a ref that does not exist.
      # Detached is the normal case here, so deploy the SHA (which is on origin
      # by definition — it is what the surviving server is running); when a
      # commit is made below, deploy the branch commit_dr_changes pushed.
      deploy_ref = `git rev-parse HEAD`.strip

      if new_ip == target_ip
        # Common in these small subnets — the replacement lands on the same
        # address, so no config change and no deploy of the stage file is needed.
        puts "✅ The replacement reused #{target_ip} — no config change, no commit needed."
      else
        puts "📌 New address: #{target_ip} → #{new_ip}"

        # --- deployed-revision guard -------------------------------------
        # commit_dr_changes branches from local HEAD, so HEAD must be what the
        # surviving servers are running or the repair deploys unreleased work.
        if healthy_other
          deployed = dr_fix_deployed_revision(healthy_other, cap_key)
          local_head = `git rev-parse HEAD`.strip
          if deployed.empty?
            puts "⚠️  Could not read REVISION from #{healthy_other} — cannot confirm HEAD matches production."
          elsif deployed != local_head
            abort "\n❌ ABORT: #{healthy_other} is running #{deployed[0, 12]} but your HEAD is #{local_head[0, 12]}.\n" \
                  "   Check out the deployed revision before repairing, so this deploy carries nothing new:\n" \
                  "     git checkout #{deployed}\n" \
                  "   (then re-run this task)"
          else
            puts "✅ Local HEAD matches the revision #{healthy_other} is running (#{deployed[0, 12]})."
          end
        end

        dr_fix_update_stage_host(env[:deploy_file], target_ip, new_ip)
        # Reuses the tested DR commit helper: it commits ONLY the credentials,
        # .env and deploy files (never `git add -A`) and pushes the branch,
        # because Capistrano deploys by cloning from origin.
        fix_branch = "dr_fix_app_#{Time.now.strftime('%Y_%m_%d_%H%M')}"
        commit_dr_changes(env[:stack], env[:variant], env[:region], fix_branch)
        deploy_ref = fix_branch # now a real branch on origin, so deploy that
      end

      # --- bring the replacement into service ----------------------------
      puts "\n🚀 Setting up and deploying ONLY #{new_ip} (ref #{deploy_ref})..."
      # A box from a fresh AMI has never been set up: IRM:setup installs the
      # nginx/monit/systemd units, IRM:install_ruby brings RVM's default up to
      # the repo's .ruby-version (the AMI bakes Ruby at Packer build time via
      # `rvm install` — see appserver.ami.pkr.hcl — so a rebuild from an AMI
      # older than the last Ruby bump would otherwise run deploy's bundler
      # install under the wrong Ruby; idempotent no-op once already current),
      # then deploy puts the app on it, then start_boot_services starts what
      # the @reboot crontab would have (it was installed after this box's
      # first boot, so it has not fired).
      # SKIP_MIGRATE: this repair must not touch the schema — the DB is healthy.
      [
        "IRM:setup",
        "IRM:install_ruby",
        "deploy",
        "IRM:start_boot_services"
      ].each do |task|
        ok = system("branch=#{deploy_ref} LB=true HOSTS=#{new_ip} SKIP_NOTIFICATION=true SKIP_MIGRATE=true " \
                    "bundle exec cap #{env[:cap_stage]} #{task}")
        abort "\n❌ cap #{task} failed on #{new_ip} — stopping here so the state is inspectable." unless ok
        puts "   ✅ cap #{task}"
      end

      # --- prove it serves ------------------------------------------------
      puts "\n🔎 Verifying the repaired host..."
      dr_fix_await_target_health(env[:region], new_instance_id) if new_instance_id
      # recovery:verify runs dr:verify on the host; it aborts non-zero on any
      # failed check, so a false "repaired" is not possible here.
      verified = system("LB=true HOSTS=#{new_ip} bundle exec cap #{env[:cap_stage]} recovery:verify")

      puts ""
      puts "=" * 78
      if verified
        puts "🟢 App server repaired: #{target_ip} → #{new_ip}, verified serving."
      else
        puts "🔴 #{new_ip} was rebuilt and deployed but recovery:verify FAILED — see the scorecard above."
      end
      puts "=" * 78
      puts "\n📋 Follow-ups this repair does NOT do:"
      puts "   • Prometheus still targets the OLD address. Regenerate and copy the config:"
      puts "       rake \"aws:generate_prometheus_yml[#{env_name}]\"   (writes LOCALLY only — copy it to the"
      puts "       observability box and reload Prometheus; see finding #4 in DR_COMPONENT_RECOVERY.md)"
      puts "   • Re-assess the whole stack: rake \"dr:assess[#{env_name}]\""
      abort "" unless verified
    end

    # -------------------------------------------------------------------
    # Prometheus config — the follow-up every box replacement needs
    # -------------------------------------------------------------------
    desc "Regenerate the Prometheus config from live instance IPs and push it to the observability box"
    task :prometheus_config, [:env_name] => :environment do |_t, args|
      env_name = args[:env_name] or raise "Usage: rake \"dr:fix:prometheus_config[production.in]\""
      env = dr_assess_resolve_env(env_name)
      dr_account_guard!(env)
      cap_key = dr_assess_cap_key(env[:deploy_file])

      puts "\n🔧 DR FIX · prometheus config · #{env_name}"

      # aws:generate_prometheus_yml rebuilds the file from the CURRENT instance
      # IPs, which is exactly what a replaced box needs. It writes locally only —
      # nothing in the existing tooling ships it to the box (finding #4), which
      # is the gap this task closes without modifying that tested task.
      Rake::Task["aws:generate_prometheus_yml"].reenable
      Rake::Task["aws:generate_prometheus_yml"].invoke(env_name)

      local_path = Rails.root.join("config/initializers/observability/prometheus.yml")
      raise "#{local_path} was not generated" unless File.exist?(local_path)

      # From STATE: production-ap-south-1 and staging export no
      # OBSERVABILITY_HOST at all, so the outputs cannot be relied on here.
      inventory = dr_stack_inventory(env[:pulumi_stack])
      obs_host = inventory.dig(:observability, :private_ip)
      raise "No observability instance in the Pulumi state for #{env[:pulumi_stack]}" if obs_host.to_s.empty?

      app_ips = inventory[:app_servers].filter_map { |i| i[:public_ip] }
      app_host = dr_fix_live_app_host(app_ips, cap_key)
      # The observability box allows SSH only from web-sg, so without a live app
      # server there is no route to it at all.
      raise "No app server is reachable — cannot hop to the observability box" unless app_host

      puts "📤 Pushing #{File.basename(local_path)} to #{obs_host} via #{app_host}..."
      # Path, owner and service name all come from the observability Packer
      # template (observability.ami.pkr.hcl): /etc/prometheus/prometheus.yml,
      # owned by prometheus:prometheus, served by the `prometheus` unit.
      out = dr_fix_push_via_app(
        app_host, cap_key, obs_host, env[:db_keyname], local_path,
        "sudo tee /etc/prometheus/prometheus.yml >/dev/null && " \
        "sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml && " \
        "sudo systemctl reload prometheus 2>/dev/null || sudo systemctl restart prometheus; " \
        "systemctl is-active prometheus"
      )
      state = out.to_s.lines.last.to_s.strip
      puts "#{state == 'active' ? '✅' : '❌'} prometheus on #{obs_host} is #{state}"

      puts "\n📋 #{local_path.relative_path_from(Rails.root)} is a tracked file and has changed locally."
      puts "   Review and commit it when the incident is over (nothing is committed automatically)."
      abort "" unless state == "active"
    end

    # -------------------------------------------------------------------
    # Observability box — never customer-facing, never blocks another repair
    # -------------------------------------------------------------------
    desc "Repair the observability box: restart Grafana/Prometheus, or rebuild it from AMI"
    task :observability, [:env_name] => :environment do |_t, args|
      env_name = args[:env_name] or raise "Usage: rake \"dr:fix:observability[production.in]\""
      env = dr_assess_resolve_env(env_name)
      dr_account_guard!(env)
      cap_key = dr_assess_cap_key(env[:deploy_file])

      puts ""
      puts "=" * 78
      puts "🔧 DR FIX · observability · #{env_name} · #{env[:region]}"
      puts "   Nothing here is customer-facing: Grafana and Prometheus being down"
      puts "   costs visibility, not service. Repair it AFTER anything that serves."
      puts "=" * 78

      inventory = dr_stack_inventory(env[:pulumi_stack])
      obs_host = inventory.dig(:observability, :private_ip)
      abort "❌ No observability instance in the Pulumi state for #{env[:pulumi_stack]}." if obs_host.to_s.empty?
      app_ips = inventory[:app_servers].filter_map { |i| i[:public_ip] }
      app_host = dr_fix_live_app_host(app_ips, cap_key)
      abort "❌ No app server is reachable — repair one first (the obs box is only reachable through them)." unless app_host

      reachable = begin
        dr_assess_ssh_via_app(app_host, cap_key, obs_host, env[:db_keyname], "echo up").include?("up")
      rescue StandardError => e
        puts "   no SSH to #{obs_host}: #{e.message.to_s.lines.first.to_s.strip}"
        false
      end

      # --- cheap rung: the box lives, the services died ------------------
      if reachable
        puts "✅ #{obs_host} is reachable — restarting services in place (no pulumi, no rebuild)."
        %w[prometheus grafana-server].each do |service|
          state = dr_assess_ssh_via_app(app_host, cap_key, obs_host, env[:db_keyname], "systemctl is-active #{service}")
          if state == "active"
            puts "   ✅ #{service} already active"
          else
            puts "   🔧 #{service} is #{state} — restarting..."
            dr_assess_ssh_via_app(app_host, cap_key, obs_host, env[:db_keyname], "sudo systemctl restart #{service}")
            state = dr_assess_ssh_via_app(app_host, cap_key, obs_host, env[:db_keyname], "systemctl is-active #{service}")
            puts "   #{state == 'active' ? '✅' : '❌'} #{service} is now #{state}"
          end
        end
        puts "\n🟢 Observability services restarted. Re-assess: rake \"dr:assess[#{env_name}]\""
        next
      end

      # --- rebuild rung ---------------------------------------------------
      puts "\n🔴 #{obs_host} is unreachable — rebuilding it from the AMI."
      # dr_stack_inventory already skipped pending-deletion leftovers, so this
      # is the URN of the box that is actually in service.
      obs_urn = inventory.dig(:observability, :urn)
      raise "Could not find the observability instance (#{obs_host}) in the Pulumi stack" unless obs_urn

      # Only the instance: unlike an app server there is NO target-group
      # attachment to carry along, because nothing in alb.py ever registers this
      # instance with target_group_obs (finding #2 in DR_COMPONENT_RECOVERY.md).
      puts "⚠️  Grafana routing note: the Pulumi code never attaches this instance to its ALB target"
      puts "    group, so if Grafana is reachable today it was registered outside Pulumi — a rebuild"
      puts "    will lose that. Re-register it by hand afterwards if you rely on it."

      dr_fix_preview_guard!(env[:pulumi_stack], [obs_urn])
      dr_fix_await_pulumi!(env[:pulumi_stack], [obs_urn])

      puts "\n✅ Rebuilt. Pushing a freshly generated Prometheus config to the new box..."
      Rake::Task["dr:fix:prometheus_config"].reenable
      Rake::Task["dr:fix:prometheus_config"].invoke(env_name)

      puts "\n📋 Follow-up: re-provision the Grafana dashboards on the new box"
      puts "   (see lib/tasks/grafana_provision.rake), then re-assess: rake \"dr:assess[#{env_name}]\""
    end

    # -------------------------------------------------------------------
    # NAT gateway — silent, and it takes the backups down with it
    # -------------------------------------------------------------------
    desc "Diagnose and repair the NAT gateway that the private-subnet DB boxes depend on"
    task :nat, [:env_name] => :environment do |_t, args|
      env_name = args[:env_name] or raise "Usage: rake \"dr:fix:nat[production.in]\""
      env = dr_assess_resolve_env(env_name)
      dr_account_guard!(env)
      cap_key = dr_assess_cap_key(env[:deploy_file])

      puts ""
      puts "=" * 78
      puts "🔧 DR FIX · NAT gateway · #{env_name} · #{env[:region]}"
      puts "   The DB boxes have NO S3 or SSM VPC endpoints, so backups AND the baked"
      puts "   restore script's config both travel through the NAT gateway. A dead NAT"
      puts "   stops backups with no user-visible symptom (finding #3)."
      puts "=" * 78

      ec2 = Aws::EC2::Client.new(region: env[:region])
      nats = ec2.describe_nat_gateways(filter: [{ name: "state", values: %w[available pending] }]).nat_gateways
      nats.each { |n| puts "   • #{n.nat_gateway_id} #{n.state} in #{n.subnet_id}" }

      # Prove the path from where it actually matters rather than trusting the
      # gateway's own state — a NAT can be "available" with a broken route.
      inventory = dr_stack_inventory(env[:pulumi_stack])
      db_host = inventory.dig(:db_primary, :private_ip)
      app_ips = inventory[:app_servers].filter_map { |i| i[:public_ip] }
      app_host = dr_fix_live_app_host(app_ips, cap_key)

      # Whether the probe RAN is tracked separately from what it found. Without
      # that distinction "could not test" collapses into "broken", and this task
      # would offer to delete and recreate a healthy gateway on no evidence.
      probe_ran = false
      reachable = false
      if app_host && db_host
        puts "\n🔎 Testing outbound reachability from the DB box #{db_host}..."
        code = dr_assess_ssh_via_app(app_host, cap_key, db_host, env[:db_keyname],
                                     "curl -s -o /dev/null -w %{http_code} --max-time 15 " \
                                     "https://s3.#{env[:region]}.amazonaws.com")
        probe_ran = true
        reachable = code.to_s.start_with?("2", "3", "4")
        puts "   #{reachable ? '✅' : '❌'} s3.#{env[:region]}.amazonaws.com → #{code.to_s.empty? ? 'no response' : "HTTP #{code}"}"
      end

      unless probe_ran
        abort "\n❌ Could not test the NAT path — no reachable app server to hop through, or no DB_HOST " \
              "in the stack output.\n   Recreating the gateway on no evidence would delete a possibly " \
              "healthy one and take a new EIP.\n   Repair an app server first, then re-run: " \
              "rake \"dr:fix:nat[#{env_name}]\""
      end

      if reachable && nats.any?
        puts "\n🟢 NAT is healthy — the DB boxes can reach S3 and SSM. Nothing to repair."
        next
      end

      puts "\n🔴 The NAT path is broken."
      puts "   aws:nat:create deletes any stale gateway, creates a new one with a fresh EIP,"
      puts "   and repoints the private route table. It CHANGES AWS resources."
      print "Type 'yes' to run it now, anything else aborts: "
      abort "\n❌ Aborted — nothing changed. Inspect with: rake \"aws:nat:status[#{env_name}]\"" unless
        STDIN.gets.to_s.strip.casecmp("yes").zero?

      Rake::Task["aws:nat:create"].reenable
      Rake::Task["aws:nat:create"].invoke(env_name)

      if app_host && db_host
        puts "\n🔎 Re-testing outbound reachability from #{db_host}..."
        sleep 15 # a new gateway takes a moment to become usable
        code = dr_assess_ssh_via_app(app_host, cap_key, db_host, env[:db_keyname],
                                     "curl -s -o /dev/null -w %{http_code} --max-time 15 " \
                                     "https://s3.#{env[:region]}.amazonaws.com")
        ok = code.to_s.start_with?("2", "3", "4")
        puts "#{ok ? '🟢' : '🔴'} s3.#{env[:region]}.amazonaws.com → #{code}"
        puts "\n📋 Backups resume on the next cron tick. Confirm with:"
        puts "   rake \"s3:check_backup_freshness[#{env_name}]\""
        abort "" unless ok
      end
    end
  end
end
