# lib/tasks/aws_cost_audit.rake
#
# Read-only AWS cost audit & optimization advisor.
#
#   bundle exec rake aws:cost_audit                        # booted env's credentials
#   bundle exec rake "aws:cost_audit[production.in]"       # audit a specific env's AWS
#     account (staging.in / staging.us / production.in / production.us) — env
#     selection via aws:environment, same as aws:create_ami; quote for zsh brackets
#   NO_LLM=1 bundle exec rake aws:cost_audit               # skip the LLM analysis step
#   MONTHS=6 REGIONS=us-east-1 bundle exec rake "aws:cost_audit[staging.us]"
#   OUTPUT=tmp/aws_cost_report.md bundle exec rake aws:cost_audit  # extra markdown copy
#
# Output: markdown to stdout, plus an HTML report written to
# docs/costs/aws_cost_audit_<env>_<date>.html (light-styled, self-contained).
#
# Produces four things:
#   1. Cost evaluation  — Cost Explorer: monthly totals, MoM deltas, top services,
#      spend by region, current-month run rate + projection.
#   2. Reservations     — active EC2 reservation inventory, with flags for
#      unused and soon-expiring ones (rightsizing must respect these).
#   3. Findings         — concrete waste from read-only resource scans, each with
#      an estimated $/month and a remediation command.
#   4. Recommendations  — deterministic priority list, plus (unless NO_LLM=1) a
#      prioritized optimization plan from Gemini via RubyLLM (LLM_MODEL overrides
#      the default gemini-3.7-flash).
#
# SAFETY: strictly read-only — only Describe*/Get*/List* AWS calls; remediation
# commands are printed for human review, never executed.
#
# AWS credentials come from the aws:environment helper (aws.rake): the optional
# [env_name] rake arg picks .env.<env_name> + config/credentials/<env_name>.yml.enc,
# loaded into the global Aws.config. Cost Explorer calls cost $0.01 each (~4 per run).

require "json"
require "fileutils"

# Helpers live in a top-level module (not inside the namespace block — defining
# constants in a block trips Lint/ConstantDefinitionInBlock and leaks scope).
module AwsCostAudit
  module_function

  # -----------------------------------------------------------------------
  # Rough on-demand price constants (USD/month, us-east-1) used ONLY to rank
  # findings — order-of-magnitude estimates, not billing-grade numbers.
  # -----------------------------------------------------------------------
  PRICE_GB_MONTH_GP2      = 0.10   # gp2 EBS per GB-month
  PRICE_GB_MONTH_GP3      = 0.08   # gp3 EBS per GB-month (20% cheaper)
  PRICE_GB_MONTH_SNAPSHOT = 0.05   # EBS snapshot per GB-month (upper bound)
  PRICE_EIP_MONTH         = 3.65   # idle public IPv4 ($0.005/hr)
  PRICE_LB_MONTH          = 16.43  # ALB/NLB base ($0.0225/hr), excl. LCUs
  PRICE_NAT_GW_MONTH      = 32.85  # NAT gateway base ($0.045/hr), excl. data
  PRICE_LOGS_GB_MONTH     = 0.03   # CloudWatch Logs storage per GB-month

  # Families old enough that a same-size modern replacement is cheaper/faster.
  PREVIOUS_GEN_PREFIXES = %w[t1. t2. m1. m3. m4. c1. c3. c4. r3. r4. i2. d2.].freeze

  IDLE_CPU_THRESHOLD_PCT = 5.0   # running EC2 below this 14d avg CPU = idle candidate
  OLD_SNAPSHOT_DAYS      = 180   # snapshots older than this get surfaced

  # ---- clients ----------------------------------------------------------

  # Credentials are NOT resolved here: the task delegates to aws:environment
  # (aws.rake), which loads .env.<env_name> + that env's encrypted credentials
  # into the global Aws.config — every client below inherits them. Only the
  # region is set per client.
  def aws_client_opts(region)
    { region: region }
  end

  # aws:environment overloads AWS_S3_REGION / AWS_REGION from .env.<env_name>.
  def default_region
    ENV["AWS_S3_REGION"] || ENV["AWS_REGION"] || "us-east-1"
  end

  # A missing IAM permission or unavailable service must produce a note, not
  # abort the whole audit — every AWS call goes through this.
  def safe(label)
    yield
  rescue Aws::Errors::ServiceError => e
    warn "  ! skipped #{label}: #{e.class.name.demodulize}"
    nil
  end

  def add_finding(findings, category, region, resource, detail, est_monthly, action)
    findings << {
      category: category, region: region, resource: resource, detail: detail,
      est_monthly_usd: est_monthly&.round(2), recommended_action: action
    }
  end

  # 14-day average of a CloudWatch metric, or nil when there are no datapoints.
  def avg_metric(cloudwatch, namespace, metric, dimensions)
    resp = safe("cloudwatch:#{metric}") do
      cloudwatch.get_metric_statistics(
        namespace: namespace, metric_name: metric, dimensions: dimensions,
        start_time: Time.now.utc - (14 * 86_400), end_time: Time.now.utc,
        period: 86_400, statistics: ["Average"]
      )
    end
    points = resp&.datapoints
    return nil if points.blank?

    points.sum(&:average) / points.size
  end

  # ---- Part 1: cost evaluation (Cost Explorer) --------------------------

  def cost_evaluation(months_back)
    # Cost Explorer only exists in us-east-1.
    ce    = Aws::CostExplorer::Client.new(aws_client_opts("us-east-1"))
    today = Time.zone.today
    start = (today << (months_back - 1)).beginning_of_month
    period = { start: start.iso8601, end: (today + 1).iso8601 }

    evaluation = { months: [], by_service: Hash.new { |h, k| h[k] = {} },
                   by_region: Hash.new(0.0), monthly_totals: {}, daily_run_rate: nil }

    # Monthly spend grouped by service — "where does the money go".
    resp = safe("ce:GetCostAndUsage(service)") do
      ce.get_cost_and_usage(time_period: period, granularity: "MONTHLY",
                            metrics: ["UnblendedCost"],
                            group_by: [{ type: "DIMENSION", key: "SERVICE" }])
    end
    return nil unless resp # no CE access -> no evaluation to build

    resp.results_by_time.each do |slice|
      month = slice.time_period.start[0, 7] # YYYY-MM
      evaluation[:months] << month unless evaluation[:months].include?(month)
      total = 0.0
      slice.groups.each do |group|
        amount = group.metrics["UnblendedCost"].amount.to_f
        evaluation[:by_service][group.keys.first][month] = amount
        total += amount
      end
      evaluation[:monthly_totals][month] = total
    end

    # Spend grouped by region — used to scope the resource scans below.
    resp = safe("ce:GetCostAndUsage(region)") do
      ce.get_cost_and_usage(time_period: period, granularity: "MONTHLY",
                            metrics: ["UnblendedCost"],
                            group_by: [{ type: "DIMENSION", key: "REGION" }])
    end
    resp&.results_by_time&.each do |slice|
      slice.groups.each do |group|
        evaluation[:by_region][group.keys.first] += group.metrics["UnblendedCost"].amount.to_f
      end
    end

    # Current-month daily costs -> run rate + straight-line projection.
    first_of_month = today.beginning_of_month
    if today > first_of_month
      resp = safe("ce:GetCostAndUsage(daily)") do
        ce.get_cost_and_usage(time_period: { start: first_of_month.iso8601, end: today.iso8601 },
                              granularity: "DAILY", metrics: ["UnblendedCost"])
      end
      if resp&.results_by_time.present?
        days    = resp.results_by_time
        spend   = days.sum { |d| d.total["UnblendedCost"].amount.to_f }
        per_day = spend / days.size
        evaluation[:daily_run_rate] = {
          elapsed_days: days.size, month_to_date: spend.round(2),
          per_day: per_day.round(2), projected_month: (per_day * 30).round(2)
        }
      end
    end

    evaluation
  end

  # ---- Part 2: per-region resource scans --------------------------------

  def scan_region(region, findings, reservations)
    warn "Scanning region #{region} ..."
    ec2        = Aws::EC2::Client.new(aws_client_opts(region))
    cloudwatch = Aws::CloudWatch::Client.new(aws_client_opts(region))

    # Tally of running instance types feeds the reservation-matching check.
    running_types = scan_ec2_instances(ec2, cloudwatch, region, findings)
    scan_ec2_reservations(ec2, region, findings, reservations, running_types)
    scan_ebs(ec2, region, findings)
    scan_snapshots(ec2, region, findings)
    scan_eips(ec2, region, findings)
    scan_nat_gateways(ec2, region, findings)
    scan_load_balancers(region, findings)
    scan_log_groups(region, findings)
  end

  # Returns a tally of running instance types, e.g. {"t3.large" => 2}.
  def scan_ec2_instances(ec2, cloudwatch, region, findings)
    running_types = Hash.new(0)
    resp = safe("ec2:DescribeInstances") { ec2.describe_instances }
    resp&.reservations&.each do |reservation|
      reservation.instances.each do |inst|
        name  = inst.tags.find { |t| t.key == "Name" }&.value
        label = "#{inst.instance_id} (#{name || 'unnamed'}, #{inst.instance_type})"
        case inst.state.name
        when "running"
          running_types[inst.instance_type] += 1
          cpu = avg_metric(cloudwatch, "AWS/EC2", "CPUUtilization",
                           [{ name: "InstanceId", value: inst.instance_id }])
          if cpu && cpu < IDLE_CPU_THRESHOLD_PCT
            add_finding(findings, "idle_ec2", region, label,
                        "14-day avg CPU #{cpu.round(1)}% — likely idle or oversized",
                        nil, # instance pricing varies too much to estimate blind
                        "Stop/terminate if unused, or downsize one size class")
          end
          if inst.instance_type.start_with?(*PREVIOUS_GEN_PREFIXES)
            add_finding(findings, "previous_gen_ec2", region, label,
                        "Previous-generation instance family", nil,
                        "Migrate to current generation (e.g. t2->t3a, m4->m6i) for ~10-20% savings")
          end
        when "stopped"
          # A stopped instance is free, but its EBS volumes still bill
          # (their storage shows up in the volume findings below).
          add_finding(findings, "stopped_ec2", region, label,
                      "Stopped instance — attached EBS volumes still accrue storage cost", nil,
                      "Terminate + snapshot (AMI) if not needed soon; snapshots are ~50% cheaper than volumes")
        end
      end
    end
    running_types
  end

  # Reserved Instances: inventory + two waste signals — reservations nothing
  # matches (paying for capacity that isn't running) and ones expiring soon
  # (on-demand price shock if not renewed). A downsize/terminate recommendation
  # elsewhere in the report should be cross-checked against this inventory.
  def scan_ec2_reservations(ec2, region, findings, reservations, running_types)
    resp = safe("ec2:DescribeReservedInstances") do
      ec2.describe_reserved_instances(filters: [{ name: "state", values: ["active"] }])
    end
    resp&.reserved_instances&.each do |ri|
      matched = running_types.fetch(ri.instance_type, 0)
      reservations << {
        service: "EC2", region: region, type: ri.instance_type, count: ri.instance_count,
        offering: ri.offering_type, end_date: ri.end&.to_date&.iso8601,
        running_matches: matched
      }
      if matched.zero?
        add_finding(findings, "unused_reservation", region,
                    "#{ri.reserved_instances_id} (#{ri.instance_count}x #{ri.instance_type})",
                    "Active EC2 reservation but no running instance of this type — paying for idle capacity",
                    nil,
                    "Modify the RI to a type you actually run (same family) or sell it on the RI Marketplace")
      elsif ri.end && ri.end < Time.zone.now + (60 * 86_400)
        add_finding(findings, "expiring_reservation", region,
                    "#{ri.reserved_instances_id} (#{ri.instance_count}x #{ri.instance_type})",
                    "Reservation expires #{ri.end.to_date.iso8601} — covered instances revert to on-demand pricing",
                    nil,
                    "Renew the RI / buy a Savings Plan before expiry, or plan to rightsize at that point")
      end
    end
  end

  def scan_ebs(ec2, region, findings)
    resp = safe("ec2:DescribeVolumes") { ec2.describe_volumes }
    resp&.volumes&.each do |vol|
      if vol.attachments.empty?
        # The whole volume cost is recoverable if it's truly orphaned.
        add_finding(findings, "unattached_ebs", region,
                    "#{vol.volume_id} (#{vol.size} GB #{vol.volume_type})",
                    "Volume not attached to any instance",
                    vol.size * PRICE_GB_MONTH_GP2,
                    "Snapshot then delete, or delete outright if confirmed orphaned")
      elsif vol.volume_type == "gp2"
        # gp3 is a drop-in, ~20% cheaper, modifiable live with no downtime.
        add_finding(findings, "gp2_volume", region, "#{vol.volume_id} (#{vol.size} GB)",
                    "gp2 volume — gp3 gives same baseline perf at 20% lower cost",
                    vol.size * (PRICE_GB_MONTH_GP2 - PRICE_GB_MONTH_GP3),
                    "aws ec2 modify-volume --volume-id #{vol.volume_id} --volume-type gp3 (live, no downtime)")
      end
    end
  end

  def scan_snapshots(ec2, region, findings)
    resp = safe("ec2:DescribeSnapshots") { ec2.describe_snapshots(owner_ids: ["self"]) }
    old = (resp&.snapshots || []).select { |s| s.start_time < Time.zone.now - (OLD_SNAPSHOT_DAYS * 86_400) }
    return if old.empty?

    total_gb = old.sum(&:volume_size)
    add_finding(findings, "old_snapshots", region,
                "#{old.size} snapshots > #{OLD_SNAPSHOT_DAYS}d old (#{total_gb} GB referenced)",
                "Aged snapshots accumulate silently; verify none are needed for compliance/DR chains",
                total_gb * PRICE_GB_MONTH_SNAPSHOT * 0.3, # incremental storage ~30% of referenced size
                "Review and delete unneeded ones; add a Data Lifecycle Manager policy for the rest")
  end

  def scan_eips(ec2, region, findings)
    resp = safe("ec2:DescribeAddresses") { ec2.describe_addresses }
    resp&.addresses&.each do |addr|
      next if addr.association_id # associated = in use

      add_finding(findings, "unused_eip", region, addr.public_ip,
                  "Elastic IP not associated with anything — billed hourly while idle",
                  PRICE_EIP_MONTH,
                  "aws ec2 release-address --allocation-id #{addr.allocation_id}")
    end
  end

  def scan_nat_gateways(ec2, region, findings)
    resp = safe("ec2:DescribeNatGateways") do
      ec2.describe_nat_gateways(filter: [{ name: "state", values: ["available"] }])
    end
    resp&.nat_gateways&.each do |nat|
      add_finding(findings, "nat_gateway", region, nat.nat_gateway_id,
                  "NAT gateway: ~$33/mo base + $0.045/GB processed", PRICE_NAT_GW_MONTH,
                  "If only used by low-traffic private subnets, consider VPC endpoints for S3/DynamoDB " \
                  "or a NAT instance; consolidate multiple NATs if HA isn't required")
    end
  end

  def scan_load_balancers(region, findings)
    elb  = Aws::ElasticLoadBalancingV2::Client.new(aws_client_opts(region))
    resp = safe("elbv2:DescribeLoadBalancers") { elb.describe_load_balancers }
    resp&.load_balancers&.each do |lb|
      groups = safe("elbv2:DescribeTargetGroups") do
        elb.describe_target_groups(load_balancer_arn: lb.load_balancer_arn)
      end
      # An LB whose every target group is empty serves nothing but still bills.
      has_targets = (groups&.target_groups || []).any? do |tg|
        health = safe("elbv2:DescribeTargetHealth") do
          elb.describe_target_health(target_group_arn: tg.target_group_arn)
        end
        health&.target_health_descriptions.present?
      end
      next if has_targets

      add_finding(findings, "empty_load_balancer", region, "#{lb.load_balancer_name} (#{lb.type})",
                  "Load balancer has zero registered targets", PRICE_LB_MONTH,
                  "aws elbv2 delete-load-balancer --load-balancer-arn #{lb.load_balancer_arn}")
    end
  end

  def scan_log_groups(region, findings)
    logs   = Aws::CloudWatchLogs::Client.new(aws_client_opts(region))
    groups = []
    token  = nil
    # Follow pagination so big accounts aren't under-reported.
    loop do
      args = { limit: 50 }
      args[:next_token] = token if token # SDK rejects an explicit nil token
      resp = safe("logs:DescribeLogGroups") { logs.describe_log_groups(args) }
      break unless resp

      groups.concat(resp.log_groups)
      token = resp.next_token
      break unless token
    end
    no_retention = groups.reject(&:retention_in_days)
    return if no_retention.empty?

    stored_gb = no_retention.sum { |g| g.stored_bytes.to_i } / 1e9
    add_finding(findings, "logs_no_retention", region,
                "#{no_retention.size} log groups with retention=Never (#{stored_gb.round(1)} GB stored)",
                "Log groups without a retention policy grow forever",
                stored_gb * PRICE_LOGS_GB_MONTH,
                "aws logs put-retention-policy --log-group-name <name> --retention-in-days 90")
  end

  # S3 is global — one pass over all buckets checking for lifecycle rules.
  def scan_s3(findings)
    warn "Scanning S3 buckets ..."
    s3      = Aws::S3::Client.new(aws_client_opts(default_region))
    clients = { default_region => s3 } # per-region client cache for redirects
    resp    = safe("s3:ListBuckets") { s3.list_buckets }
    resp&.buckets&.each do |bucket|
      # Lifecycle must be queried in the bucket's own region, otherwise the
      # SDK raises PermanentRedirect and we'd misreport "no lifecycle".
      region = safe("s3:GetBucketLocation #{bucket.name}") do
        loc = s3.get_bucket_location(bucket: bucket.name).location_constraint
        loc.presence || "us-east-1" # empty constraint means us-east-1
      end
      next unless region # couldn't determine region -> can't check, skip quietly

      client = clients[region] ||= Aws::S3::Client.new(aws_client_opts(region))
      begin
        client.get_bucket_lifecycle_configuration(bucket: bucket.name)
        next # lifecycle exists — nothing to report
      rescue Aws::S3::Errors::NoSuchLifecycleConfiguration
        # Expected signal: bucket genuinely has no lifecycle — fall through.
      rescue Aws::Errors::ServiceError => e
        warn "  ! skipped s3:lifecycle #{bucket.name}: #{e.class.name.demodulize}"
        next # couldn't check — don't fabricate a finding
      end

      add_finding(findings, "s3_no_lifecycle", region, bucket.name,
                  "Bucket has no lifecycle configuration — old versions, incomplete multipart " \
                  "uploads and cold data are never expired or tiered", nil,
                  "Add lifecycle rules: abort incomplete multipart uploads after 7d, transition " \
                  "cold data to STANDARD_IA/Glacier, expire old noncurrent versions")
    end
  end

  # ---- Part 3: report rendering -----------------------------------------

  def render_report(account, evaluation, findings, regions, reservations)
    out = []
    out << "# AWS Cost Audit — account #{account}"
    out << "_Generated #{Time.zone.today.iso8601} · regions scanned: #{regions.join(', ').presence || 'none'}_\n"

    out << "## 1. Cost evaluation"
    if evaluation
      out << "\n### Monthly totals\n"
      out << "| Month | Total (USD) | Δ vs prior |"
      out << "|---|---:|---:|"
      prev = nil
      evaluation[:months].each do |month|
        total = evaluation[:monthly_totals][month] || 0.0
        delta = prev ? format("%+.2f", total - prev) : "—"
        out << format("| %s | %.2f | %s |", month, total, delta)
        prev = total
      end
      if (rr = evaluation[:daily_run_rate])
        out << format("\nCurrent month: **$%.2f** over %d days ($%.2f/day, projecting ~**$%.2f**).",
                      rr[:month_to_date], rr[:elapsed_days], rr[:per_day], rr[:projected_month])
      end

      # Top services by latest-month spend.
      latest = evaluation[:months].last
      prior  = evaluation[:months][-2]
      if latest
        out << "\n### Top services (#{latest})\n"
        out << "| Service | This month | Prior month |"
        out << "|---|---:|---:|"
        ranked = evaluation[:by_service].sort_by { |_s, series| -(series[latest] || 0.0) }
        ranked.first(15).each do |service, series|
          current = series[latest] || 0.0
          next if current < 0.01 # hide sub-cent noise services

          out << format("| %s | %.2f | %s |", service, current,
                        prior ? format("%.2f", series[prior] || 0.0) : "—")
        end
      end

      active = evaluation[:by_region].sort_by { |_r, v| -v }
                                     .select { |_r, v| v > 1.0 }
                                     .map { |r, v| format("%s ($%.2f)", r, v) }
      out << "\nSpend by region over the period: #{active.join(', ').presence || 'n/a'}."
    else
      out << "\n_Cost Explorer data unavailable (missing `ce:GetCostAndUsage` permission?)._"
    end

    # Reservation inventory — context every rightsizing decision must respect:
    # terminating/downsizing a reserved instance type strands the reservation.
    out << "\n## 2. Active reservations\n"
    if reservations.any?
      out << "| Service | Region | Type | Count | Offering | Ends | Running matches |"
      out << "|---|---|---|---:|---|---|---:|"
      reservations.each do |ri|
        out << "| #{ri[:service]} | #{ri[:region]} | #{ri[:type]} | #{ri[:count]} | " \
               "#{ri[:offering]} | #{ri[:end_date] || '—'} | #{ri[:running_matches]} |"
      end
      out << "\n_Rightsize/terminate recommendations below should keep reserved types in use " \
             "until their end date — a stranded reservation still bills._"
    else
      out << "No active EC2 reservations — everything runs at on-demand rates. " \
             "If the workload is steady, a 1-year Savings Plan or RI is typically a 30-40% cut."
    end

    out << "\n## 3. Findings (specific waste detected)\n"
    if findings.any?
      estimable = findings.sum { |f| f[:est_monthly_usd] || 0.0 }
      out << format("%d findings; estimable waste ≈ **$%.2f/month** (items without an estimate " \
                    "excluded — actual savings likely higher).\n", findings.size, estimable)
      out << "| Category | Region | Resource | Detail | Est. $/mo | Recommended action |"
      out << "|---|---|---|---|---:|---|"
      # Biggest estimated savings first — the table doubles as a priority list.
      findings.sort_by { |f| -(f[:est_monthly_usd] || 0.0) }.each do |f|
        est = f[:est_monthly_usd] ? format("%.2f", f[:est_monthly_usd]) : "—"
        out << "| #{f[:category]} | #{f[:region]} | #{f[:resource]} | #{f[:detail]} | #{est} | #{f[:recommended_action]} |"
      end
    else
      out << "No waste findings — resource hygiene looks good."
    end

    out << "\n## 4. Recommendations (deterministic)\n"
    findings.group_by { |f| f[:category] }
            .sort_by { |_c, items| -items.sum { |i| i[:est_monthly_usd] || 0.0 } }
            .each do |category, items|
      total = items.sum { |i| i[:est_monthly_usd] || 0.0 }
      est   = total.positive? ? format(" (~$%.2f/mo)", total) : ""
      out << "- **#{category}** × #{items.size}#{est}: #{items.first[:recommended_action]}"
    end
    out << "\n> ⚠️ Nothing above was executed. Review each action before running it — " \
           "especially deletions of volumes, snapshots, and databases."
    out.join("\n")
  end

  # Markdown -> standalone HTML document (light styling, no external assets),
  # written to docs/costs/. Redcarpet is already a Gemfile dependency; the
  # `tables` extension is required for the findings/reservations tables.
  def render_html(markdown, account, env_label)
    require "redcarpet"
    body = Redcarpet::Markdown.new(
      Redcarpet::Render::HTML.new(with_toc_data: true),
      tables: true, fenced_code_blocks: true, autolink: true, no_intra_emphasis: true
    ).render(markdown)
    <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <title>AWS Cost Audit — #{env_label} (#{account})</title>
        <style>
          body { font-family: -apple-system, "Segoe UI", Roboto, sans-serif; color: #1f2933; background: #fff; max-width: 1100px; margin: 2rem auto; padding: 0 1.5rem; line-height: 1.55; }
          h1, h2, h3 { color: #102a43; }
          h2 { border-bottom: 2px solid #d9e2ec; padding-bottom: .3rem; margin-top: 2.2rem; }
          table { border-collapse: collapse; width: 100%; margin: 1rem 0; font-size: .95rem; }
          th, td { border: 1px solid #d9e2ec; padding: .45rem .6rem; text-align: left; vertical-align: top; }
          th { background: #f0f4f8; }
          tr:nth-child(even) td { background: #f8fafc; }
          code, pre { background: #f0f4f8; border-radius: 4px; }
          pre { padding: .8rem; overflow-x: auto; }
          code { padding: .1rem .3rem; }
          blockquote { border-left: 4px solid #f0b429; background: #fffbea; margin: 1rem 0; padding: .6rem 1rem; }
        </style>
      </head>
      <body>
      #{body}
      </body>
      </html>
    HTML
  end

  # ---- Part 4: LLM optimization plan (RubyLLM -> Gemini) ----------------

  def llm_plan(account, evaluation, findings, reservations)
    # Compact the evidence to keep the prompt focused even on large accounts.
    evidence = {
      account: account,
      monthly_totals: evaluation&.dig(:monthly_totals) || {},
      daily_run_rate: evaluation&.dig(:daily_run_rate),
      top_services: (evaluation&.dig(:by_service) || {})
                    .sort_by { |_s, series| -series.values.sum }.first(20).to_h,
      active_reservations: reservations,
      findings: findings.first(150)
    }

    prompt = <<~PROMPT
      You are a senior AWS cost-optimization consultant (FinOps). Below is billing
      data and read-only audit findings for one AWS account. Produce a markdown
      report with:
      1. A short executive evaluation of the spend profile and any anomalous
         month-over-month movements.
      2. A prioritized, numbered optimization plan — each item with the concrete
         resources involved, the exact CLI command or console steps, estimated
         monthly savings, effort (low/med/high), and risk.
      Prioritize by savings/effort ratio. Only recommend actions supported by the
      evidence; never invent resource IDs. Respect active_reservations: never
      recommend terminating or downsizing capacity that would strand an active
      reservation before its end date. Flag anything needing human verification
      before deletion. Output markdown only, no code fences around the whole reply.

      Audit evidence (JSON):
      #{JSON.pretty_generate(evidence)}
    PROMPT

    # Same RubyLLM invocation style as weekly_email.rake; LLM_MODEL overrides.
    model = ENV.fetch("LLM_MODEL", "gemini-3.7-flash")
    chat  = RubyLLM.chat(model: model, provider: :gemini, assume_model_exists: true)
    chat.ask(prompt).content
  rescue StandardError => e
    # The deterministic report is the floor — an LLM failure only loses the plan.
    warn "LLM analysis skipped: #{e.class}: #{e.message}"
    nil
  end
end

namespace :aws do
  desc "Read-only cost audit of an env's AWS account (ENV: MONTHS, REGIONS, NO_LLM, LLM_MODEL, OUTPUT)"
  # rubocop:disable Rails/RakeEnvironment -- the cop's fix (`task cost_audit: :environment`)
  # resolves to aws:environment from aws.rake inside this namespace, skipping Rails
  # initializers; we invoke the top-level environment task in the body instead.
  task :cost_audit, [:env_name] do |_t, args|
    # Rails initializers must run first (RubyLLM config for the Gemini step) —
    # aws:environment alone doesn't run them. NOT a `: :environment` prerequisite:
    # inside `namespace :aws` that resolves to aws:environment, not the Rails task.
    Rake::Task["environment"].invoke
    # Same env-selection convention as aws:create_ami / aws:provision_s3_buckets:
    # aws:environment loads .env.<env_name> + that env's encrypted credentials
    # into Aws.config (no env_name -> the booted env's own credentials).
    Rake::Task["aws:environment"].reenable
    Rake::Task["aws:environment"].invoke(args[:env_name])
    # require: false in the Gemfile, so load the SDKs explicitly here.
    %w[aws-sdk-costexplorer aws-sdk-ec2 aws-sdk-cloudwatch aws-sdk-cloudwatchlogs
       aws-sdk-elasticloadbalancingv2 aws-sdk-s3].each { |g| require g }

    # Identify the account up front so the report is unambiguous about scope.
    sts   = Aws::STS::Client.new(AwsCostAudit.aws_client_opts(AwsCostAudit.default_region))
    ident = sts.get_caller_identity
    warn "Auditing account #{ident.account} as #{ident.arn}"

    warn "Fetching Cost Explorer data ..."
    evaluation = AwsCostAudit.cost_evaluation(Integer(ENV.fetch("MONTHS", "3")))

    # Scope scans to regions that actually carry spend unless pinned via REGIONS.
    regions =
      if ENV["REGIONS"].present?
        ENV["REGIONS"].split(",").map(&:strip)
      elsif evaluation
        evaluation[:by_region].select { |r, v| v > 1.0 && %w[NoRegion global].exclude?(r) }
                              .keys.sort
      else
        [AwsCostAudit.default_region]
      end
    warn "Regions to scan: #{regions.join(', ')}"

    findings     = []
    reservations = [] # active EC2 reservations — context for rightsizing
    regions.each { |region| AwsCostAudit.scan_region(region, findings, reservations) }
    AwsCostAudit.scan_s3(findings)

    report = AwsCostAudit.render_report(ident.account, evaluation, findings, regions, reservations)

    if ENV["NO_LLM"].blank?
      warn "Requesting optimization plan from Gemini ..."
      plan = AwsCostAudit.llm_plan(ident.account, evaluation, findings, reservations)
      report += "\n\n## 5. Optimization plan (LLM analysis)\n\n#{plan}" if plan
    end

    puts report

    # HTML report — always written to docs/costs/, one file per env per day.
    env_label = args[:env_name] || Rails.env.to_s
    html_dir  = Rails.root.join("docs/costs")
    FileUtils.mkdir_p(html_dir)
    html_path = html_dir.join("aws_cost_audit_#{env_label}_#{Time.zone.today.iso8601}.html")
    File.write(html_path, AwsCostAudit.render_html(report, ident.account, env_label))
    warn "HTML report written to #{html_path}"

    # OUTPUT keeps the raw markdown too, when requested.
    if ENV["OUTPUT"].present?
      File.write(ENV["OUTPUT"], "#{report}\n")
      warn "Markdown report written to #{ENV['OUTPUT']}"
    end
  end
  # rubocop:enable Rails/RakeEnvironment
end
