# lib/tasks/aws_tls_policy.rake
#
# Pin the ALB HTTPS listener TLS policy to TLS 1.3 + TLS 1.2 (nothing older),
# for both staging and production.
#
#   bundle exec rake "aws:tls_policy[staging.in]"                # DRY RUN (default)
#   EXECUTE=1 bundle exec rake "aws:tls_policy[staging.in]"      # apply
#   EXECUTE=1 bundle exec rake "aws:tls_policy[production.in]"
#   REGIONS=ap-south-1 bundle exec rake "aws:tls_policy[production.in]"  # one region only
#   POLICY=ELBSecurityPolicy-TLS13-1-2-Res-2021-06 EXECUTE=1 rake ...    # stricter policy
#
# WHY THIS EXISTS
#   TLS terminates at the ALB (ACM certs); the app boxes only ever listen on
#   :80 — see config/deploy/templates/nginx_conf.erb. So "enable TLS 1.2/1.3 and
#   disable older versions" is a listener setting, not an nginx or OpenSSL change
#   on the instances. IRM-Infra/alb.py originally passed no ssl_policy, so AWS
#   applied its default ELBSecurityPolicy-2016-08, which negotiates down to
#   TLS 1.0. alb.py now pins the policy below; this task applies the same value
#   to listeners that are already running, so the fix lands without waiting for
#   a pulumi up (and without a prod pulumi run picking up unrelated stack drift).
#   Run this first, then let the next pulumi up be a no-op on the listener.
#
# SAFETY
#   - Dry run by default; every mutating call goes through .act, so without
#     EXECUTE=1 nothing can be modified.
#   - env_name must be one of the three known envs, and the STS account id must
#     match that env's account. staging (174852986003) and production
#     (825199636520) are separate AWS accounts, so exporting the wrong keys is
#     an easy mistake — this refuses rather than silently retargeting.
#   - modify_listener on ssl_policy is an in-place, non-disruptive update:
#     established connections are unaffected, new handshakes use the new policy.
#     It is reversible by re-running with POLICY=<old value>.
#   - Only HTTPS listeners on *application* load balancers are touched.
#
# AFTER RUNNING
#   Clients that cannot do TLS 1.2 are refused by design. The ALB has no access
#   logs configured (IRM-Infra/alb.py sets no access_logs), so there is no
#   ssl_protocol field to count old clients with beforehand — do staging first,
#   then production, and watch the ClientTLSNegotiationErrorCount metric on the
#   prod ALB for a day. Once verified, docs/marketing/gtm_prerequisites_work/
#   E2_security_questionnaire.md (D2) and E1_security_page_content.md are
#   unblocked to claim "TLS 1.2 or higher".

require "openssl"
require "socket"

module AwsTlsPolicy
  module_function

  # Must match ssl_policy in IRM-Infra/alb.py — if you change one, change both,
  # or the next pulumi up silently reverts whatever this task set.
  DEFAULT_POLICY = "ELBSecurityPolicy-TLS13-1-2-2021-06".freeze

  # AWS's default when no policy is pinned. Recognised only so the output can
  # name it explicitly — it is the thing we are here to get rid of.
  AWS_DEFAULT_POLICY = "ELBSecurityPolicy-2016-08".freeze

  # env_name => the AWS account it lives in, and the regions to sweep.
  #
  # The account guards against running production.in with staging keys exported
  # (or the reverse) — staging and production are separate AWS accounts.
  #
  # The regions mirror the Pulumi stacks in IRM-Infra (Pulumi.<stack>-<region>.yaml),
  # NOT the AWS_S3_REPLICA_REGION in .env.*: staging.in replicates S3 within
  # ap-south-1, but its DR *stack* is staging-ap-south-2 and has its own ALB.
  # Sweeping the DR region matters — a failover onto an unpinned listener would
  # quietly start serving TLS 1.0 again. Regions with no ALB are a no-op, so
  # us-east-2 is listed for production.us even though only S3 lives there today.
  # staging.us is deliberately absent: that environment is decommissioned
  # (same stance as aws_ebs.rake's ENV_ACCOUNTS) — any us-east-1 leftovers in
  # the staging account are handled via REGIONS=us-east-1 under staging.in.
  ENV_TARGETS = {
    "staging.in" => { account: "174852986003", regions: %w[ap-south-1 ap-south-2] },
    "production.in" => { account: "825199636520", regions: %w[ap-south-1 ap-south-2] },
    "production.us" => { account: "825199636520", regions: %w[us-east-1 us-east-2] }
  }.freeze

  def policy = ENV.fetch("POLICY", DEFAULT_POLICY)

  def execute? = ENV["EXECUTE"].present?

  # Every mutating call funnels through here so DRY RUN can't possibly mutate.
  def act(description)
    if execute?
      yield
      puts "  ✅ #{description}"
    else
      puts "  [dry-run] would #{description}"
    end
  end

  def guard!(env_name, account)
    abort "❌ env_name is required, e.g. rake \"aws:tls_policy[staging.in]\"" if env_name.blank?
    target = ENV_TARGETS[env_name]
    abort "❌ unknown env '#{env_name}' — expected one of #{ENV_TARGETS.keys.join(', ')}" if target.nil?
    return if target[:account] == account

    abort "❌ #{env_name} lives in account #{target[:account]} but these credentials are account #{account} — " \
          "export the right env's AWS keys before re-running"
  end

  # REGIONS overrides the per-env list above, for a narrower blast radius
  # (e.g. primary only, leaving DR for a separate run).
  def regions_for(env_name)
    return ENV["REGIONS"].split(",").map(&:strip) if ENV["REGIONS"].present?

    ENV_TARGETS.fetch(env_name)[:regions]
  end

  # All HTTPS listeners on application load balancers in one region.
  # NLB "TLS" listeners are deliberately out of scope — this stack has none, and
  # they carry a different policy namespace.
  def https_listeners(elb)
    albs = elb.describe_load_balancers.load_balancers.select { |lb| lb.type == "application" }
    albs.flat_map do |lb|
      elb.describe_listeners(load_balancer_arn: lb.load_balancer_arn)
         .listeners
         .select { |l| l.protocol == "HTTPS" }
         .map { |l| [lb, l] }
    end
  end

  def apply_region(region)
    elb = Aws::ElasticLoadBalancingV2::Client.new(region: region)
    pairs = https_listeners(elb)
    if pairs.empty?
      puts "  (no application load balancers with an HTTPS listener in #{region})"
      return []
    end

    pairs.each do |lb, listener|
      current = listener.ssl_policy
      label   = current == AWS_DEFAULT_POLICY ? "#{current} — AWS default, allows TLS 1.0" : current
      puts "  #{lb.load_balancer_name} :#{listener.port} — currently #{label}"

      if current == policy
        puts "    already #{policy} — no change"
        next
      end

      act "set #{lb.load_balancer_name} :#{listener.port} to #{policy}" do
        elb.modify_listener(listener_arn: listener.listener_arn, ssl_policy: policy)
      end
    end

    pairs.map { |lb, _l| lb.dns_name }.uniq
  end

  # Protocol versions to probe. Whether each SHOULD be accepted is not
  # hardcoded — it depends on the pinned policy (a POLICY override may be
  # TLS1.3-only), so expectations are fetched from AWS per run; see
  # expected_protocols. :legacy marks versions OpenSSL 3.x refuses client-side
  # at default security level (see handshake?).
  # rubocop:disable Naming/VariableNumber -- symbols mirror OpenSSL's own
  # min_version/max_version constants (TLS1_1_VERSION etc.), not our naming.
  PROBE_VERSIONS = {
    "TLSv1.0" => { version: :TLS1, legacy: true },
    "TLSv1.1" => { version: :TLS1_1, legacy: true },
    "TLSv1.2" => { version: :TLS1_2, legacy: false },
    "TLSv1.3" => { version: :TLS1_3, legacy: false }
  }.freeze
  # rubocop:enable Naming/VariableNumber

  # The authoritative accept-list for the target policy, straight from AWS —
  # describe_ssl_policies names exactly the protocol versions it negotiates
  # (e.g. ["TLSv1.2", "TLSv1.3"]), so any POLICY override gets correct
  # expectations without a hand-maintained matrix.
  def expected_protocols(elb)
    elb.describe_ssl_policies(names: [policy]).ssl_policies.first.ssl_protocols
  rescue Aws::ElasticLoadBalancingV2::Errors::ServiceError => e
    abort "❌ could not look up policy '#{policy}': #{e.message}"
  end

  # Handshake probe against the ALB's own DNS name. The wildcard cert will not
  # match that hostname, so certificate verification is disabled on purpose —
  # this is a protocol-version test, not a trust test.
  #
  # With `expected` (EXECUTE mode, post-change): marks each version pass/fail
  # against the policy's accept-list and RETURNS the mismatches so the task can
  # fail loudly — a missed listener must not exit 0 looking like success.
  # Without it (dry run): the listener hasn't been changed, so there is nothing
  # to judge — report what the internet sees today, unmarked.
  def probe(host, expected: nil)
    puts "  probing #{host}#{' (baseline — no change applied)' if expected.nil?}"
    mismatches = []
    PROBE_VERSIONS.each do |name, spec|
      ok = handshake?(host, spec[:version], legacy: spec[:legacy])
      if expected.nil?
        puts "    #{name}: #{ok ? 'accepted' : 'refused'}"
      else
        want = expected.include?(name)
        mark = ok == want ? "✅" : "❌"
        puts "    #{mark} #{name}: #{ok ? 'accepted' : 'refused'} (policy says #{want ? 'accepted' : 'refused'})"
        mismatches << "#{host}: #{name} #{ok ? 'accepted' : 'refused'}, policy says #{want ? 'accept' : 'refuse'}" if ok != want
      end
    end
    mismatches
  end

  def handshake?(host, version, legacy: false)
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE # hostname will not match the wildcard cert
    if legacy
      # Ruby links OpenSSL 3.x, whose default security level 2 refuses TLS < 1.2
      # and SHA1 ciphers *in the client* — without this the handshake dies with
      # "no protocols available" before a packet is sent, and the probe would
      # report a clean pass against a listener that in fact still speaks TLS 1.0.
      # Dropping to level 0 makes the refusal genuinely the server's.
      ctx.security_level = 0
      ctx.ciphers = "ALL:@SECLEVEL=0"
    end
    ctx.min_version = ctx.max_version = version # pin to exactly this version
    Socket.tcp(host, 443, connect_timeout: 5) do |tcp|
      ssl = OpenSSL::SSL::SSLSocket.new(tcp, ctx)
      ssl.connect
      ssl.close
    end
    true
  rescue OpenSSL::SSL::SSLError => e
    # A local refusal is not a server refusal — say so rather than scoring a pass.
    puts "    ⚠️  client-side refusal, not the server: #{e.message}" if e.message.include?("no protocols available")
    false
  rescue Errno::ECONNRESET
    false # server dropped the connection — it does not speak this version
  rescue StandardError => e
    puts "    ⚠️  probe error (#{e.class}): #{e.message}"
    false
  end
end

namespace :aws do
  desc "Pin ALB HTTPS listeners to TLS 1.2/1.3 (ENV: EXECUTE, REGIONS, POLICY)"
  # rubocop:disable Rails/RakeEnvironment -- as in aws:cost_cleanup: a bare
  # :environment prerequisite resolves to aws:environment inside this namespace.
  task :tls_policy, [:env_name] do |_t, args|
    Rake::Task["environment"].invoke
    Rake::Task["aws:environment"].reenable
    Rake::Task["aws:environment"].invoke(args[:env_name])
    require "aws-sdk-elasticloadbalancingv2"

    ident = Aws::STS::Client.new(region: "us-east-1").get_caller_identity
    AwsTlsPolicy.guard!(args[:env_name], ident.account)

    mode = AwsTlsPolicy.execute? ? "EXECUTE" : "DRY RUN"
    puts "== aws:tls_policy [#{args[:env_name]}] account #{ident.account} — #{mode} =="
    puts "   target policy: #{AwsTlsPolicy.policy}"

    hosts = AwsTlsPolicy.regions_for(args[:env_name]).flat_map do |region|
      puts "\n-- #{region} --"
      AwsTlsPolicy.apply_region(region)
    end

    # EXECUTE: verify against the policy's own protocol list and FAIL on any
    # mismatch — a listener still accepting TLS 1.0 must not exit 0.
    # Dry run: probe as an unmarked "what does the internet see today" baseline.
    puts "\n-- verification --"
    expected = if AwsTlsPolicy.execute?
                 region = AwsTlsPolicy.regions_for(args[:env_name]).first
                 AwsTlsPolicy.expected_protocols(Aws::ElasticLoadBalancingV2::Client.new(region: region))
               end
    mismatches = hosts.flat_map { |host| AwsTlsPolicy.probe(host, expected: expected) }

    abort "\n❌ verification FAILED:\n#{mismatches.map { |m| "  - #{m}" }.join("\n")}" if mismatches.any?
    puts(AwsTlsPolicy.execute? ? "\n== done ==" : "\n== dry run complete — re-run with EXECUTE=1 to apply ==")
  end
  # rubocop:enable Rails/RakeEnvironment
end
