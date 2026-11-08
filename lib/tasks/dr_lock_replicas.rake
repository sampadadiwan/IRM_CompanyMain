# frozen_string_literal: true

# Locks an environment's REPLICA backup and document buckets so nobody can delete what was
# replicated there for 30 days: S3 Object Lock, COMPLIANCE mode, 30-day default retention
# (openspec fix-backups-deletable). The app's own keys hold S3 full access (G25) and could
# otherwise delete every version in both regions, governance locks included.
#
#   rake "aws:lock_replica_buckets[staging.in]"                     # dry run: shows the plan
#   EXECUTE=1 rake "aws:lock_replica_buckets[staging.in]"           # applies it (PERMANENT)
#   PROVE=1 rake "aws:lock_replica_buckets[staging.in]"             # proves a new backup is locked
#   ALLOW_PRODUCTION=1 EXECUTE=1 rake "aws:lock_replica_buckets[production.in]"  # separate go-ahead
#
# Which buckets: the destinations of the primaries' own replication rules, never a primary.
# Irreversible: Object Lock cannot be turned off, and a compliance-locked version cannot be
# deleted or shortened by anyone, AWS root included, until its date.
require "active_support/encrypted_configuration"
require "cgi"
require "json"

namespace :aws do
  # No :environment: runs from the operator's machine against AWS only (Dr from dr_requires.rb)
  desc "Lock an env's replica backup/document buckets: COMPLIANCE 30 days (dry run; EXECUTE=1; PROVE=1)"
  task :lock_replica_buckets, [:env_name] do |_t, args| # rubocop:disable Rails/RakeEnvironment
    env_name = args[:env_name].to_s
    abort "❌ Unknown environment #{env_name.inspect}. Supported: #{DR_ASSESS_ENVIRONMENTS.keys.join(', ')}" unless DR_ASSESS_ENVIRONMENTS.key?(env_name)
    unless Dr::BackupLock.env_allowed?(env_name, allow_production: ENV["ALLOW_PRODUCTION"] == "1")
      abort "❌ Refusing #{env_name}: production needs ALLOW_PRODUCTION=1 and a separate go-ahead " \
            "(staging first). Nothing touched."
    end
    execute = ENV["EXECUTE"] == "1"

    # 1. The keys in use must belong to this environment's AWS account
    Rake::Task["aws:environment"].invoke(env_name)
    expected = DR_ASSESS_ENVIRONMENTS.fetch(env_name)[:account]
    actual = Aws::STS::Client.new.get_caller_identity.account
    abort "❌ AWS account #{actual} is not #{env_name}'s (#{expected}). Nothing touched." unless actual == expected
    puts "✅ AWS account #{actual} (#{env_name})"

    # 2. The replicas, from where the primaries actually replicate (never a primary)
    replicas = replica_buckets_for_env
    abort "❌ No replica buckets found in the primaries' replication rules. Nothing touched." if replicas.empty?
    puts "🪣 Replica buckets of #{env_name}:"
    replicas.each { |r| puts "   • #{r[:bucket]} (#{r[:region]})" }

    # 3. Replication role: add the two read permissions locking needs, BEFORE locking
    source = Aws::S3::Client.new(region: ENV.fetch("AWS_S3_REGION"))
    lock_ensure_replication_role!(source, execute: execute)

    # 4. The lock itself
    if execute
      puts "\n⚠️  PERMANENT: Object Lock cannot be turned off; everything replicated from now on is"
      puts "   undeletable by anyone (root included) for #{Dr::BackupLock::DAYS} days."
    end
    puts "\n🔒 Lock plan (#{Dr::BackupLock::MODE}, #{Dr::BackupLock::DAYS} days):"
    replicas.each do |r|
      s3_ensure_object_lock!(client: Aws::S3::Client.new(region: r[:region]), bucket: r[:bucket], execute: execute)
    end
    puts "ℹ️  Dry run — nothing changed. Re-run with EXECUTE=1 to apply." unless execute

    # 5. Proof: a fresh backup marker replicates, is locked, and the app key cannot delete it
    lock_prove!(env_name, source, replicas) if ENV["PROVE"] == "1"
  end

  # Adds Dr::BackupLock::REPLICATION_ROLE_ACTIONS to each primary's replication role (upsert of
  # its inline policy). Idempotent; dry run only prints.
  def lock_ensure_replication_role!(source, execute:)
    iam = Aws::IAM::Client.new
    primaries = ["#{ENV.fetch('AWS_S3_BUCKET')}-backup-xtra", ENV.fetch("AWS_S3_BUCKET")]
    roles = primaries.filter_map do |bucket|
      source.get_bucket_replication(bucket: bucket).replication_configuration.role.split("/").last
    rescue Aws::S3::Errors::ReplicationConfigurationNotFoundError
      nil
    end
    roles.uniq.each do |role|
      iam.list_role_policies(role_name: role).policy_names.each do |name|
        document = JSON.parse(CGI.unescape(iam.get_role_policy(role_name: role, policy_name: name).policy_document))
        updated = Dr::BackupLock.role_policy_with_lock_actions(document)
        next puts "✅ Replication role #{role}/#{name}: lock permissions present" unless updated

        puts "🔐 Replication role #{role}/#{name}: add #{Dr::BackupLock::REPLICATION_ROLE_ACTIONS.join(', ')}"
        iam.put_role_policy(role_name: role, policy_name: name, policy_document: updated.to_json) if execute
      end
    end
  end

  # Writes a tiny marker to the primary BACKUP bucket, waits for it on the replica, checks it
  # carries the compliance lock, then tries to delete that version with the APP's own key and
  # the bypass header. Success = AccessDenied. The marker stays 30 days (a few bytes).
  def lock_prove!(env_name, source, replicas)
    primary = "#{ENV.fetch('AWS_S3_BUCKET')}-backup-xtra"
    replica = replicas.find { |r| r[:bucket].include?("backup-xtra") } || replicas.first
    key = "dr-lock-check/#{Time.now.utc.strftime('%Y%m%d%H%M%S')}.txt"
    source.put_object(bucket: primary, key: key, body: "DR lock check #{Time.now.utc.iso8601} (#{env_name})")
    puts "\n🧪 Proof: wrote s3://#{primary}/#{key}; waiting for it on #{replica[:bucket]} (up to 15 min)…"

    # Wait for replication
    dest = Aws::S3::Client.new(region: replica[:region])
    head = nil
    60.times do
      head = begin
        dest.head_object(bucket: replica[:bucket], key: key)
      rescue Aws::S3::Errors::NotFound
        nil
      end
      break if head

      sleep 15
    end
    abort "❌ The marker did not replicate in 15 minutes — check replication (#{key})." unless head
    puts "   ✅ Replicated (version #{head.version_id})"

    # It must carry the compliance lock for ~30 days
    days_left = head.object_lock_retain_until_date ? ((head.object_lock_retain_until_date - Time.now.utc) / 86_400).round(1) : 0
    abort "❌ Replica not locked as expected: mode=#{head.object_lock_mode.inspect}, until=#{head.object_lock_retain_until_date.inspect}" unless head.object_lock_mode == Dr::BackupLock::MODE && days_left >= Dr::BackupLock::DAYS - 1
    puts "   ✅ Locked: #{head.object_lock_mode} until #{head.object_lock_retain_until_date.utc.iso8601} (#{days_left} days)"

    # The leaked-key case: the app's own key, with the bypass header, must be refused
    creds = ActiveSupport::EncryptedConfiguration.new(
      config_path: Rails.root.join("config/credentials/#{env_name}.yml.enc"),
      key_path: Rails.root.join("config/credentials/#{env_name}.key"),
      env_key: "RAILS_MASTER_KEY_UNUSED", raise_if_missing_key: true
    ).config
    app = Aws::S3::Client.new(region: replica[:region],
                              credentials: Aws::Credentials.new(creds[:AWS_ACCESS_KEY_ID], creds[:AWS_SECRET_ACCESS_KEY]))
    begin
      app.delete_object(bucket: replica[:bucket], key: key, version_id: head.version_id, bypass_governance_retention: true)
      abort "❌ The app key DELETED a locked replica version — the lock is not protecting backups!"
    rescue Aws::S3::Errors::AccessDenied => e
      puts "   ✅ App key + bypass header → AccessDenied (#{e.message})"
    end
    puts "✅ Proven: new backups on #{replica[:bucket]} cannot be deleted for #{Dr::BackupLock::DAYS} days."
  end
end
