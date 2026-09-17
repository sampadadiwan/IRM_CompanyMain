# Pulumi state backend provisioning.
#
# Creates and maintains the S3 bucket pair that holds Pulumi state for one
# (account x geography): a PRIMARY bucket written by every `pulumi up`, and a
# DR bucket in the geography's failover region kept current by S3 cross-region
# replication.
#
# Full design, day-2 usage and the failover runbook live in
# IRM-Infra/PULUMI_STATE.md. This task owns only the buckets and replication —
# the one-time migration of existing stacks off Pulumi Cloud is
# IRM-Infra/migrate_state_to_s3.sh, which requires these buckets to exist.
#
#   bundle exec rake "aws:provision_pulumi_state_bucket[production.in]"
#   bundle exec rake "aws:provision_pulumi_state_bucket[production.us]"
#   bundle exec rake "aws:provision_pulumi_state_bucket[staging.in]"
#
# SCOPE: production (both geographies) plus staging.in, which is the stack used
# to rehearse DR. A drill that runs against a personal Pulumi Cloud login is not
# rehearsing the real procedure, so staging.in gets the same primary+replica
# backend as production. staging.us is not migrated — nothing depends on it.
#
# Idempotent — safe to re-run to repair drift or restore a deleted rule.

require 'dotenv'
require 'rake'
require_relative 'aws_utils'

include AwsUtils

namespace :aws do
  # Account each env_name prefix must resolve to. Guards the most likely
  # operator error: running with the other account's credentials exported.
  PULUMI_STATE_ACCOUNTS = {
    "staging"    => "174852986003",
    "production" => "825199636520"
  }.freeze

  desc "Provision the Pulumi state S3 bucket pair (primary + replicated DR), e.g. aws:provision_pulumi_state_bucket[production.in]"
  task :provision_pulumi_state_bucket, [:env_name] do |t, args|
    env_name = args[:env_name] or raise "env_name required: production.in | production.us"
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(env_name)
    require "aws-sdk-s3"
    require "aws-sdk-iam"
    require "aws-sdk-core"

    account, geo = env_name.split(".")
    expected_account = PULUMI_STATE_ACCOUNTS[account] or
      raise "Unknown account '#{account}' in env_name '#{env_name}' (expected staging|production)"
    raise "Unknown geography '#{geo}' in env_name '#{env_name}' (expected in|us)" unless %w[in us].include?(geo)

    # Primary region: where state is written day to day.
    primary_region = ENV["AWS_S3_REGION"] || ENV["AWS_REGION"] or
      raise "Neither AWS_S3_REGION nor AWS_REGION set for #{env_name}"

    # DR region, in order of preference:
    #   1. explicit override
    #   2. the env's AWS_S3_REPLICA_REGION — but ONLY if it is a real other
    #      region. .env.staging.* sets it equal to the source region (staging
    #      app buckets have no replica), which would silently give us a
    #      same-region "DR" copy.
    #   3. the known primary -> DR pairs
    env_replica = ENV["AWS_S3_REPLICA_REGION"]
    env_replica = nil if env_replica == primary_region
    dr_region = ENV["PULUMI_STATE_REPLICA_REGION"] ||
                env_replica ||
                AwsUtils::S3_DR_REGION_PAIRS[primary_region] or
      raise "No DR region known for primary region '#{primary_region}'. " \
            "Set PULUMI_STATE_REPLICA_REGION or add the pair to AwsUtils::S3_DR_REGION_PAIRS."

    if primary_region == dr_region
      raise "DR region equals primary region (#{primary_region}) for #{env_name} — " \
            "that is not a disaster recovery copy. Set PULUMI_STATE_REPLICA_REGION."
    end

    # Bucket names spell out account, ROLE and REGION. Deliberately not a
    # "-dr" suffix on a shared stem: the two buckets of a pair must not be
    # distinguishable only by their last few characters, because logging in to
    # the wrong one is how you get split-brain state. "primary" and "replica"
    # are different words, and the region is in the name so there is never a
    # question of where a bucket lives.
    #   irm-pulumi-state-production-primary-ap-south-1
    #   irm-pulumi-state-production-replica-ap-south-2
    stem           = "irm-pulumi-state-#{account}"
    state_bucket   = ENV.fetch("PULUMI_STATE_BUCKET",    "#{stem}-primary-#{primary_region}")
    dr_bucket      = ENV.fetch("PULUMI_STATE_DR_BUCKET", "#{stem}-replica-#{dr_region}")
    role_name      = ENV.fetch("PULUMI_STATE_REPLICATION_ROLE",
                               "irm-pulumi-state-replication-#{primary_region}-to-#{dr_region}")
    overwrite_rule = ENV["PULUMI_STATE_REPLICATION_OVERWRITE"] == "true"

    caller_account = Aws::STS::Client.new(region: primary_region).get_caller_identity.account
    if caller_account != expected_account
      raise "Credentials resolve to AWS account #{caller_account}, but '#{account}' is #{expected_account}. " \
            "Check config/credentials/#{env_name}.key and the exported keys."
    end
    puts "✅ Credentials match account #{account} (#{caller_account})."
    puts "→ #{env_name}: s3://#{state_bucket} (#{primary_region}) replicating to s3://#{dr_bucket} (#{dr_region})"

    s3_primary = Aws::S3::Client.new(region: primary_region)
    s3_dr      = Aws::S3::Client.new(region: dr_region)
    iam        = Aws::IAM::Client.new(region: primary_region)

    # Both ends of the pair. NO lifecycle rules are applied, deliberately: the
    # xtrabackup buckets expire objects after 180d and purge noncurrent
    # versions after 30d (IRM-Infra/s3_backups.py). Anything like that here
    # would delete Pulumi state and its version history — and the version
    # history IS the state backup story. State is a few hundred KB per stack;
    # there is nothing to save by expiring it.
    s3_ensure_bucket!(client: s3_primary, bucket: state_bucket, region: primary_region)
    s3_ensure_bucket!(client: s3_dr,      bucket: dr_bucket,    region: dr_region)

    role_arn = s3_ensure_replication_role!(
      iam: iam, role_name: role_name,
      source_buckets: [state_bucket], dest_buckets: [dr_bucket]
    )

    # IAM role creation is eventually consistent — S3 rejects a role it cannot
    # yet assume. Retry rather than failing the whole run on a race.
    configured = false
    10.times do |attempt|
      begin
        configured = s3_ensure_replication!(
          client: s3_primary,
          source_bucket: state_bucket, dest_bucket: dr_bucket, role_arn: role_arn,
          rule_id: "irm-pulumi-state-to-dr",
          replicate_delete_markers: false,
          replication_time_control: true,
          overwrite: overwrite_rule
        )
        break
      rescue Aws::S3::Errors::InvalidRequest => e
        raise if attempt == 9
        puts "  waiting for IAM role to propagate (attempt #{attempt + 1}): #{e.message}"
        sleep 6
      end
    end

    puts ""
    if configured
      puts "✅ #{env_name} Pulumi state backend ready."
    else
      puts "⚠️  #{env_name} buckets exist but replication was NOT (re)configured — see the message above."
      puts "    Re-run with PULUMI_STATE_REPLICATION_OVERWRITE=true to replace an existing rule."
    end
    puts "   Operators use:"
    puts "     export PULUMI_CONFIG_PASSPHRASE=$(aws ssm get-parameter --name /irm/pulumi/passphrase \\"
    puts "       --with-decryption --region #{primary_region} --query Parameter.Value --output text)"
    puts "     pulumi login \"s3://#{state_bucket}?region=#{primary_region}\""
    puts "   Never log in to #{dr_bucket} except during a #{primary_region} outage"
    puts "   (failover runbook: IRM-Infra/PULUMI_STATE.md)."
  end
end
