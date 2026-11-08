# frozen_string_literal: true

module Dr
  # S3 Object Lock on the REPLICA backup and document buckets (openspec fix-backups-deletable).
  #
  # Backups and documents replicate to a second region, but the app's own keys hold S3 full
  # access (G25) and could delete every version in both copies - including overriding a
  # GOVERNANCE lock (they have s3:BypassGovernanceRetention). So the replicas get COMPLIANCE
  # mode with a 30-day default retention (decision 2026-11-08): nothing written there can be
  # deleted or have its lock shortened by anyone, AWS root included, for 30 days.
  #
  # Primary buckets are never locked: the app manages them. Which buckets are replicas is read
  # from the primaries' own replication rules, never hard-coded.
  #
  # Pure: callers read the bucket's lock configuration ({enabled:, mode:, days:}) and apply.
  module BackupLock
    MODE = "COMPLIANCE"
    DAYS = 30
    # AWS asks the replication role for these on the SOURCE side when replicating into an
    # Object Lock bucket. Added before locking, so replication never stalls.
    REPLICATION_ROLE_ACTIONS = %w[s3:GetObjectRetention s3:GetObjectLegalHold].freeze

    module_function

    # What to do to a replica bucket's lock configuration.
    # config: { enabled: true/false, mode: "COMPLIANCE"/"GOVERNANCE"/nil, days: Integer/nil }
    def plan(config, days: DAYS)
      return { action: :none, summary: "nothing to do" } if strong_enough?(config, days)

      # Turning Object Lock on is permanent; setting the default rule is what locks new writes
      action = config[:enabled] ? :set_rule : :enable_and_set_rule
      summary = config[:enabled] ? "set #{MODE} #{days} days" : "enable Object Lock and set #{MODE} #{days} days"
      { action: action, summary: summary, mode: MODE, days: days }
    end

    # dr_readiness's verdict on one replica bucket
    def grade(bucket, config, days: DAYS)
      grade = BackupSchedule::Grade
      return grade.new(:fail, "#{bucket}: Object Lock is off — replica backups can be deleted by any key with S3 access") unless config[:enabled]
      return grade.new(:fail, "#{bucket}: Object Lock on but no default retention — new backups are not locked") if config[:mode].nil?
      return grade.new(:fail, "#{bucket}: #{config[:mode]} mode can be bypassed by the app's own keys (s3:BypassGovernanceRetention) — use #{MODE}") if config[:mode] != MODE
      return grade.new(:fail, "#{bucket}: #{MODE} lock of #{config[:days]} days is shorter than #{days} days") if config[:days].to_i < days

      grade.new(:ok, "#{bucket}: #{MODE}, #{config[:days]} days")
    end

    def strong_enough?(config, days)
      config[:enabled] && config[:mode] == MODE && config[:days].to_i >= days
    end

    # The buckets to lock: the primaries' replication destinations, excluding any primary
    # (a misconfigured rule that points a bucket at itself must never lock a primary).
    def replicas_to_lock(primaries:, destinations:)
      (Array(destinations).map(&:to_s) - Array(primaries).map(&:to_s)).uniq
    end

    # The replication role's inline policy with REPLICATION_ROLE_ACTIONS added to the statement
    # that reads source object versions. Returns nil when nothing needs adding (idempotent).
    def role_policy_with_lock_actions(document)
      statements = Array(document["Statement"])
      reader = statements.find { |st| Array(st["Action"]).include?("s3:GetObjectVersionForReplication") }
      return nil unless reader

      missing = REPLICATION_ROLE_ACTIONS - Array(reader["Action"])
      return nil if missing.empty?

      reader["Action"] = Array(reader["Action"]) + missing
      document
    end

    # Production only with an explicit ALLOW_PRODUCTION=1 (and the user's separate go-ahead)
    def env_allowed?(env_name, allow_production:)
      return true if env_name.to_s.start_with?("staging.")

      env_name.to_s.start_with?("production.") && allow_production
    end

    # The bucket's current lock configuration as a plain hash, from the S3 API
    def read_config(client, bucket)
      lock = client.get_object_lock_configuration(bucket: bucket).object_lock_configuration
      retention = lock.rule&.default_retention
      days = retention && (retention.days || (retention.years.to_i * 365))
      { enabled: lock.object_lock_enabled == "Enabled", mode: retention&.mode, days: days }
    rescue Aws::S3::Errors::ObjectLockConfigurationNotFoundError
      { enabled: false, mode: nil, days: nil }
    end
  end
end
