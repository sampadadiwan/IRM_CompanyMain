# lib/tasks/aws_cost_cleanup.rake
#
# STAGING-ONLY remediation for the waste found by aws:cost_audit.
#
#   bundle exec rake "aws:cost_cleanup[staging.in]"              # DRY RUN (default)
#   EXECUTE=1 bundle exec rake "aws:cost_cleanup[staging.in]"    # apply safe actions
#   EXECUTE=1 DELETE_NAT=1 bundle exec rake "aws:cost_cleanup[staging.in]"
#   EXECUTE=1 TERMINATE_IDS=i-abc,i-def bundle exec rake "aws:cost_cleanup[staging.in]"
#
# What it does (in EXECUTE mode; otherwise it only prints the plan):
#   1. Snapshots  — deletes snapshots older than SNAPSHOT_DAYS (default 180) that
#      do NOT back any registered AMI (AMI-backed ones are always kept).
#   2. Elastic IPs — releases addresses not associated with anything.
#   3. S3 lifecycle — adds a conservative lifecycle to buckets that have none:
#      abort incomplete multipart uploads after 7d, expire noncurrent versions
#      after 30d, clean up expired delete markers. No transitions, and current
#      versions are never expired — document data is untouched.
#   4. NAT gateways — only with DELETE_NAT=1, and only gateways with ~zero
#      traffic over 14 days. NOTE: instances routed through a deleted NAT lose
#      outbound internet (OS package updates included) until aws:nat:create
#      re-creates one — see lib/tasks/nat_gateway.rake.
#   5. Stopped instances — never touched automatically. Pass TERMINATE_IDS to
#      terminate specific ones; each gets an AMI backup created first.
#
# SAFETY RAILS (all three must pass, or the task aborts before any AWS call):
#   - the [env_name] arg must start with "staging"
#   - the STS account id must be in STAGING_ACCOUNT_IDS
#   - Rails.env must not be production

require "fileutils"

module AwsCostCleanup
  module_function

  # Both staging.in and staging.us live in this account. Production accounts
  # (e.g. 825199636520) must never appear here.
  STAGING_ACCOUNT_IDS = %w[174852986003].freeze

  SNAPSHOT_DAYS   = Integer(ENV.fetch("SNAPSHOT_DAYS", "180"))
  NAT_IDLE_GB_14D = 0.05 # NATs that moved less than this in 14 days count as idle

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
    abort "❌ env_name is required, e.g. rake \"aws:cost_cleanup[staging.in]\"" if env_name.blank?
    abort "❌ #{env_name} is not a staging env — this task only runs against staging" unless env_name.start_with?("staging")
    abort "❌ account #{account} is not a whitelisted staging account (#{STAGING_ACCOUNT_IDS.join(', ')})" unless STAGING_ACCOUNT_IDS.include?(account)
    abort "❌ refusing to run in the production Rails env" if Rails.env.production?
  end

  # ---- 1. aged snapshots not backing any AMI ------------------------------
  def cleanup_snapshots(ec2)
    # Snapshot ids referenced by any registered AMI — deleting these breaks the
    # AMI (DR bakes live here), so they are unconditionally kept.
    ami_snap_ids = ec2.describe_images(owners: ["self"]).images.flat_map do |img|
      img.block_device_mappings.filter_map { |bd| bd.ebs&.snapshot_id }
    end.to_set

    cutoff = Time.zone.now - (SNAPSHOT_DAYS * 86_400)
    old = ec2.describe_snapshots(owner_ids: ["self"]).snapshots.select { |s| s.start_time < cutoff }
    candidates, kept = old.partition { |s| ami_snap_ids.exclude?(s.snapshot_id) }
    puts "Snapshots > #{SNAPSHOT_DAYS}d: #{old.size} (keeping #{kept.size} AMI-backed, " \
         "deleting #{candidates.size} / #{candidates.sum(&:volume_size)} GB referenced)"
    candidates.each do |snap|
      act "delete #{snap.snapshot_id} (#{snap.volume_size} GB, #{snap.start_time.to_date}, #{snap.description.to_s[0, 50].inspect})" do
        ec2.delete_snapshot(snapshot_id: snap.snapshot_id)
      rescue Aws::EC2::Errors::InvalidSnapshotInUse
        puts "  ⚠️  #{snap.snapshot_id} is in use (AMI registered since scan?) — skipped"
      end
    end
  end

  # ---- 2. unassociated Elastic IPs ---------------------------------------
  def cleanup_eips(ec2)
    ec2.describe_addresses.addresses.reject(&:association_id).each do |addr|
      act "release EIP #{addr.public_ip} (#{addr.allocation_id})" do
        ec2.release_address(allocation_id: addr.allocation_id)
      end
    end
  end

  # ---- 3. conservative lifecycle for buckets that have none ---------------
  def cleanup_s3_lifecycle(key_opts, home_region)
    s3      = Aws::S3::Client.new(region: home_region, **key_opts)
    clients = { home_region => s3 }
    s3.list_buckets.buckets.each do |bucket|
      # The staging account hosts at least one PRODUCTION DR replica bucket
      # (replica.docs.caphive.com.production.us-east-2). Expiring noncurrent
      # versions there would gut its point-in-time recovery — never touch
      # production-named buckets from this task.
      if bucket.name.include?("production")
        puts "  ⚠️  #{bucket.name}: production-named bucket — skipped, handle deliberately"
        next
      end
      # Query lifecycle in the bucket's own region to avoid PermanentRedirect.
      region = s3.get_bucket_location(bucket: bucket.name).location_constraint.presence || "us-east-1"
      client = clients[region] ||= Aws::S3::Client.new(region: region, **key_opts)
      begin
        client.get_bucket_lifecycle_configuration(bucket: bucket.name)
        next # has lifecycle (e.g. the xtrabackup chain-safe rules) — leave it alone
      rescue Aws::S3::Errors::NoSuchLifecycleConfiguration
        # fall through: this bucket is the target
      end
      act "add conservative lifecycle to #{bucket.name} (abort MPU 7d, expire noncurrent 30d)" do
        client.put_bucket_lifecycle_configuration(
          bucket: bucket.name,
          lifecycle_configuration: { rules: [{
            id: "cost-cleanup-conservative", status: "Enabled",
            filter: {}, # whole bucket
            abort_incomplete_multipart_upload: { days_after_initiation: 7 },
            noncurrent_version_expiration: { noncurrent_days: 30 },
            expiration: { expired_object_delete_marker: true }
          }] }
        )
      end
    end
  end

  # ---- 4. idle NAT gateways (double opt-in) -------------------------------
  def cleanup_nat_gateways(ec2, cloudwatch)
    nats = ec2.describe_nat_gateways(filter: [{ name: "state", values: ["available"] }]).nat_gateways
    nats.each do |nat|
      resp = cloudwatch.get_metric_statistics(
        namespace: "AWS/NATGateway", metric_name: "BytesOutToDestination",
        dimensions: [{ name: "NatGatewayId", value: nat.nat_gateway_id }],
        start_time: Time.zone.now - (14 * 86_400), end_time: Time.zone.now,
        period: 14 * 86_400, statistics: ["Sum"]
      )
      gb = (resp.datapoints.first&.sum || 0) / 1e9
      if gb >= NAT_IDLE_GB_14D
        puts "NAT #{nat.nat_gateway_id}: #{gb.round(2)} GB out in 14d — in use, kept"
        next
      end
      if ENV["DELETE_NAT"].blank?
        puts "NAT #{nat.nat_gateway_id}: idle (#{gb.round(3)} GB/14d) — pass DELETE_NAT=1 to delete " \
             "(routed instances lose outbound internet until aws:nat:create restores it)"
        next
      end
      act "delete idle NAT #{nat.nat_gateway_id} (its route becomes blackhole; EIP released next run)" do
        ec2.delete_nat_gateway(nat_gateway_id: nat.nat_gateway_id)
      end
    end
  end

  # ---- 5. explicit stopped-instance termination ---------------------------
  def cleanup_stopped_instances(ec2)
    resp = ec2.describe_instances(filters: [{ name: "instance-state-name", values: ["stopped"] }])
    stopped = resp.reservations.flat_map(&:instances)
    wanted  = ENV["TERMINATE_IDS"].to_s.split(",").map(&:strip)
    stopped.each do |inst|
      name = inst.tags.find { |t| t.key == "Name" }&.value
      unless wanted.include?(inst.instance_id)
        puts "Stopped #{inst.instance_id} (#{name}): kept — add to TERMINATE_IDS to remove"
        next
      end
      act "back up #{inst.instance_id} (#{name}) as AMI then terminate it" do
        # AMI first so the machine is restorable; snapshots cost ~half the volumes.
        ec2.create_image(instance_id: inst.instance_id,
                         name: "cleanup-#{inst.instance_id}-#{Time.zone.today.iso8601}",
                         description: "Pre-termination backup of #{name}")
        ec2.terminate_instances(instance_ids: [inst.instance_id])
      end
    end
  end
end

namespace :aws do
  desc "STAGING-ONLY cleanup of audit findings (ENV: EXECUTE, DELETE_NAT, TERMINATE_IDS, SNAPSHOT_DAYS)"
  # rubocop:disable Rails/RakeEnvironment -- same as aws:cost_audit: a bare
  # :environment prerequisite resolves to aws:environment inside this namespace.
  task :cost_cleanup, [:env_name] do |_t, args|
    Rake::Task["environment"].invoke
    Rake::Task["aws:environment"].reenable
    Rake::Task["aws:environment"].invoke(args[:env_name])
    %w[aws-sdk-ec2 aws-sdk-cloudwatch aws-sdk-s3].each { |g| require g }

    ident = Aws::STS::Client.new(region: "us-east-1").get_caller_identity
    AwsCostCleanup.guard!(args[:env_name], ident.account)

    mode = AwsCostCleanup.execute? ? "EXECUTE" : "DRY RUN"
    puts "== aws:cost_cleanup [#{args[:env_name]}] account #{ident.account} — #{mode} =="

    region = ENV["AWS_REGION"] || "ap-south-1"
    ec2    = Aws::EC2::Client.new(region: region)
    cw     = Aws::CloudWatch::Client.new(region: region)
    # S3 clients need explicit keys for cross-region redirects; Aws.config
    # already holds them (set by aws:environment), so pass an empty hash and
    # let the global config supply credentials.
    AwsCostCleanup.cleanup_snapshots(ec2)
    AwsCostCleanup.cleanup_eips(ec2)
    AwsCostCleanup.cleanup_s3_lifecycle({}, region)
    AwsCostCleanup.cleanup_nat_gateways(ec2, cw)
    AwsCostCleanup.cleanup_stopped_instances(ec2)

    puts AwsCostCleanup.execute? ? "== done ==" : "== dry run complete — re-run with EXECUTE=1 to apply =="
  end
  # rubocop:enable Rails/RakeEnvironment
end
