# lib/tasks/aws_cost_cleanup_prod.rake
#
# PRODUCTION-scoped cleanup of audit findings — SAFE ACTIONS ONLY.
#
#   bundle exec rake "aws:cost_cleanup_prod[production.in]"            # DRY RUN (default)
#   EXECUTE=1 bundle exec rake "aws:cost_cleanup_prod[production.in]"  # apply
#
# Deliberately narrower than aws:cost_cleanup (staging): only actions with no
# recovery/compliance implications are included.
#   1. Snapshots  — delete snapshots older than SNAPSHOT_DAYS (default 180) that
#      back NO registered AMI, checked per region. AMI-backed snapshots (DR bake
#      lineage) are always kept. Scans all prod regions, since the bulk of the
#      waste sits in the DR region ap-south-2.
#   2. Log buckets — CloudTrail / VPC-flow-log buckets get an expiry lifecycle
#      (180d) plus abort-incomplete-multipart-upload (7d).
#   3. Other buckets without lifecycle — MPU-abort (7d) ONLY. No noncurrent
#      version expiry and no transitions: production document versions are
#      recovery/compliance artifacts and are never touched here.
#      Backup buckets (*-backup-xtra) are skipped entirely — they belong to the
#      chain-safe xtrabackup lifecycle (rake xtrabackup tasks), not this one.
#   4. Log groups — retention set to 90d where retention is "Never".
#
# Explicitly NOT here (kept out on purpose): NAT gateways (live prod egress),
# stopped DbCheckInstance boxes (backup-verification tooling), instance
# termination/downsizing (SP-covered since 2026-08-31), EIPs (none unused),
# and any version-expiry on document buckets.
#
# Guards: [env_name] must start with "production", STS account must be the
# prod account, and the local Rails env must not be production.

module AwsCostCleanupProd
  module_function

  PROD_ACCOUNT_IDS = %w[825199636520].freeze
  # Regions with prod spend per the 2026-08-31 audit (snapshots/log groups scan).
  REGIONS = %w[ap-south-1 ap-south-2 us-east-1 us-east-2 ap-southeast-1].freeze

  SNAPSHOT_DAYS      = Integer(ENV.fetch("SNAPSHOT_DAYS", "180"))
  LOG_EXPIRY_DAYS    = 180 # CloudTrail / flow-log objects kept this long
  LOG_RETENTION_DAYS = 90  # CloudWatch log groups with retention=Never

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
    abort "❌ env_name is required, e.g. rake \"aws:cost_cleanup_prod[production.in]\"" if env_name.blank?
    abort "❌ #{env_name} is not a production env" unless env_name.start_with?("production")
    abort "❌ account #{account} is not the whitelisted prod account" unless PROD_ACCOUNT_IDS.include?(account)
    abort "❌ refusing to run in the production Rails env" if Rails.env.production?
  end

  # ---- 1. orphaned aged snapshots, per region -----------------------------
  def cleanup_snapshots(region)
    ec2 = Aws::EC2::Client.new(region: region)
    # Snapshots referenced by ANY registered AMI in this region are kept —
    # that's the DR bake lineage.
    ami_snap_ids = ec2.describe_images(owners: ["self"]).images.flat_map do |img|
      img.block_device_mappings.filter_map { |bd| bd.ebs&.snapshot_id }
    end.to_set
    cutoff = Time.zone.now - (SNAPSHOT_DAYS * 86_400)
    old = ec2.describe_snapshots(owner_ids: ["self"]).snapshots.select { |s| s.start_time < cutoff }
    candidates, kept = old.partition { |s| ami_snap_ids.exclude?(s.snapshot_id) }
    return if old.empty?

    puts "#{region}: #{old.size} snapshots > #{SNAPSHOT_DAYS}d (keeping #{kept.size} AMI-backed, " \
         "deleting #{candidates.size} / #{candidates.sum(&:volume_size)} GB referenced)"
    candidates.each do |snap|
      act "delete #{snap.snapshot_id} (#{snap.volume_size} GB, #{snap.start_time.to_date})" do
        ec2.delete_snapshot(snapshot_id: snap.snapshot_id)
      rescue Aws::EC2::Errors::InvalidSnapshotInUse
        puts "  ⚠️  #{snap.snapshot_id} in use (AMI registered since scan?) — skipped"
      end
    end
  rescue Aws::Errors::ServiceError => e
    puts "#{region}: skipped snapshots (#{e.class.name.demodulize})"
  end

  # ---- 2+3. bucket lifecycles ---------------------------------------------
  def log_bucket?(name)
    name.match?(/cloudtrail|flow-logs/)
  end

  def cleanup_s3_lifecycle(home_region)
    s3      = Aws::S3::Client.new(region: home_region)
    clients = { home_region => s3 }
    s3.list_buckets.buckets.each do |bucket|
      # Backup buckets get the chain-safe xtrabackup lifecycle, never this one.
      if bucket.name.include?("backup-xtra")
        puts "  ⚠️  #{bucket.name}: backup bucket — skipped (apply the xtrabackup lifecycle instead)"
        next
      end
      region = s3.get_bucket_location(bucket: bucket.name).location_constraint.presence || "us-east-1"
      client = clients[region] ||= Aws::S3::Client.new(region: region)
      begin
        client.get_bucket_lifecycle_configuration(bucket: bucket.name)
        next # already has lifecycle — leave it alone
      rescue Aws::S3::Errors::NoSuchLifecycleConfiguration
        # fall through: this bucket needs one
      end

      if log_bucket?(bucket.name)
        # Pure log history: expire objects, abort stuck uploads.
        act "add log lifecycle to #{bucket.name} (expire #{LOG_EXPIRY_DAYS}d, abort MPU 7d)" do
          client.put_bucket_lifecycle_configuration(
            bucket: bucket.name,
            lifecycle_configuration: { rules: [{
              id: "cost-cleanup-logs", status: "Enabled", filter: {},
              expiration: { days: LOG_EXPIRY_DAYS },
              abort_incomplete_multipart_upload: { days_after_initiation: 7 }
            }] }
          )
        end
      else
        # Document buckets: MPU-abort ONLY — object versions are never expired.
        act "add MPU-abort-only lifecycle to #{bucket.name} (7d; no version expiry)" do
          client.put_bucket_lifecycle_configuration(
            bucket: bucket.name,
            lifecycle_configuration: { rules: [{
              id: "cost-cleanup-mpu-only", status: "Enabled", filter: {},
              abort_incomplete_multipart_upload: { days_after_initiation: 7 }
            }] }
          )
        end
      end
    end
  rescue Aws::Errors::ServiceError => e
    puts "S3: skipped (#{e.class.name.demodulize})"
  end

  # ---- 4. log groups without retention ------------------------------------
  def cleanup_log_groups(region)
    logs   = Aws::CloudWatchLogs::Client.new(region: region)
    groups = []
    token  = nil
    loop do
      args = { limit: 50 }
      args[:next_token] = token if token
      resp = logs.describe_log_groups(args)
      groups.concat(resp.log_groups)
      token = resp.next_token
      break unless token
    end
    groups.reject(&:retention_in_days).each do |group|
      act "set #{LOG_RETENTION_DAYS}d retention on #{region} log group #{group.log_group_name}" do
        logs.put_retention_policy(log_group_name: group.log_group_name,
                                  retention_in_days: LOG_RETENTION_DAYS)
      end
    end
  rescue Aws::Errors::ServiceError => e
    puts "#{region}: skipped log groups (#{e.class.name.demodulize})"
  end
end

namespace :aws do
  desc "PROD-scoped SAFE cleanup: orphaned snapshots, log lifecycles, log retention (ENV: EXECUTE, SNAPSHOT_DAYS)"
  # rubocop:disable Rails/RakeEnvironment -- same as aws:cost_audit: a bare
  # :environment prerequisite resolves to aws:environment inside this namespace.
  task :cost_cleanup_prod, [:env_name] do |_t, args|
    Rake::Task["environment"].invoke
    Rake::Task["aws:environment"].reenable
    Rake::Task["aws:environment"].invoke(args[:env_name])
    %w[aws-sdk-ec2 aws-sdk-s3 aws-sdk-cloudwatchlogs].each { |g| require g }

    ident = Aws::STS::Client.new(region: "us-east-1").get_caller_identity
    AwsCostCleanupProd.guard!(args[:env_name], ident.account)

    mode = AwsCostCleanupProd.execute? ? "EXECUTE" : "DRY RUN"
    puts "== aws:cost_cleanup_prod [#{args[:env_name]}] account #{ident.account} — #{mode} =="

    AwsCostCleanupProd::REGIONS.each { |r| AwsCostCleanupProd.cleanup_snapshots(r) }
    AwsCostCleanupProd.cleanup_s3_lifecycle(ENV["AWS_REGION"] || "ap-south-1")
    AwsCostCleanupProd::REGIONS.each { |r| AwsCostCleanupProd.cleanup_log_groups(r) }

    puts AwsCostCleanupProd.execute? ? "== done ==" : "== dry run complete — re-run with EXECUTE=1 to apply =="
  end
  # rubocop:enable Rails/RakeEnvironment
end
