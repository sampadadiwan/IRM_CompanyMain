# Verifies cross-region replication of the documents bucket (AWS_S3_BUCKET ->
# AWS_S3_BUCKET_REPLICA): the replication rule is still in place, and the newest
# file in the bucket has actually landed in the replica.
#
# Finding "the newest file" means listing the WHOLE bucket — S3 has no
# sort-by-date listing. That is the price of checking real uploads rather than a
# canary; the report records how many objects were scanned and how long it took.
class S3CheckJob < ApplicationJob
  # S3 cross-region replication typically completes within this window. Files
  # newer than this are skipped when picking the file to verify, so a run never
  # judges an upload that simply has not had time to copy yet.
  REPLICATION_GRACE_PERIOD = 15.minutes
  # PENDING is normal for a while (a 2GB upload takes time to copy); PENDING on a
  # file older than this means replication is stuck, not slow.
  PENDING_MAX_AGE = 6.hours

  # env_name (e.g. production.in / production.us): lets this run locally against
  # a specific deployment's AWS account, exactly as DbBackupFreshnessJob#perform
  # does. On the deployed server Capistrano symlinks the regional credentials
  # file, so the hourly cron keeps calling this with no argument and resolves
  # correctly; from a laptop, Rails.application.credentials is whatever the
  # default (development) credentials hold — a DIFFERENT account — so the DR
  # verification entry point s3:check_latest_file must pass env_name.
  def perform(env_name: nil)
    report = collect_report(env_name: env_name)
    if report[:failures].any?
      msg = "S3 replication check FAILED: #{report[:failures].join(' | ')}"
      Rails.logger.error msg
      ErrorReport.notify(StandardError.new(msg), job: self, **report.except(:failures))
    else
      Rails.logger.info { "✓ S3 replication check #{report[:status]}: #{report[:detail]}" }
    end
  end

  # Runs the checks and describes the result without alerting — the hourly job
  # (#perform) alerts on it, the morning report (rake s3:backup_daily_report)
  # prints it. Keys: source/replica bucket + region, :rule, :objects_scanned,
  # :scan_seconds, :newest (key/last_modified/size of the file verified),
  # :status (ok | PENDING | EMPTY | UNREADABLE | NO RULE | FAILED | STUCK | MISSING
  # | SIZE DIFFERS), :detail (one sentence), :failures (empty = healthy).
  def collect_report(env_name: nil)
    @env_name = env_name
    report = {
      source_bucket: ENV.fetch('AWS_S3_BUCKET', nil).to_s,
      source_region: ENV.fetch('AWS_S3_REGION', nil),
      replica_bucket: ENV.fetch('AWS_S3_BUCKET_REPLICA', nil).to_s,
      replica_region: ENV.fetch('AWS_S3_REPLICA_REGION', nil),
      failures: []
    }

    report[:rule] = replication_rule(report)
    report[:failures] << "no enabled replication rule on s3://#{report[:source_bucket]} targets s3://#{report[:replica_bucket]} (#{report[:rule]})" unless rule_ok?(report[:rule])

    newest = newest_settled_object(report)
    return finish(report, 'UNREADABLE', "cannot list s3://#{report[:source_bucket]}: #{report[:list_error]}", failure: true) if report[:list_error]
    return finish(report, 'EMPTY', "no file older than #{REPLICATION_GRACE_PERIOD.inspect} in s3://#{report[:source_bucket]} to verify") unless newest

    report[:newest] = { key: newest.key, last_modified: newest.last_modified, size: newest.size }
    verify_replicated(report, newest)
  rescue Aws::Errors::ServiceError, Seahorse::Client::NetworkingError => e
    finish(report, 'UNREADABLE', "cannot check '#{newest&.key}': #{e.class.name.demodulize}: #{e.message}", failure: true)
  end

  private

  # The rule is what makes replication happen at all: a removed or disabled rule
  # stops every future copy while existing files still look fine in the replica.
  # Lack of permission to READ the config is reported but is not a failure —
  # the file check below still proves (or disproves) that copies are landing.
  def replication_rule(report)
    rules = source_client.get_bucket_replication(bucket: report[:source_bucket]).replication_configuration.rules
    rule = rules.find { |r| r.destination.bucket == "arn:aws:s3:::#{report[:replica_bucket]}" }
    return "MISSING (replicates to #{rules.map { |r| r.destination.bucket }.join(', ')})" unless rule
    return "DISABLED (#{rule.id})" unless rule.status == 'Enabled'

    "enabled (#{rule.id})"
  rescue Aws::S3::Errors::ReplicationConfigurationNotFoundError
    'MISSING (bucket has no replication configuration)'
  rescue Aws::S3::Errors::AccessDenied
    'unknown (no permission to read the replication configuration)'
  rescue Aws::Errors::ServiceError, Seahorse::Client::NetworkingError => e
    "unknown (#{e.class.name.demodulize})"
  end

  def rule_ok?(rule)
    rule.start_with?('enabled', 'unknown')
  end

  # One pass over every object, keeping only the newest one old enough to have
  # replicated — constant memory however large the bucket is.
  def newest_settled_object(report)
    cutoff = Time.current - REPLICATION_GRACE_PERIOD
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    newest = nil
    count = 0
    source_client.list_objects_v2(bucket: report[:source_bucket]).each_page do |page|
      page.contents.each do |obj|
        count += 1
        next if obj.last_modified > cutoff

        newest = obj if newest.nil? || obj.last_modified > newest.last_modified
      end
    end
    newest
  rescue Aws::Errors::ServiceError, Seahorse::Client::NetworkingError => e
    report[:list_error] = "#{e.class.name.demodulize}: #{e.message}"
    nil
  ensure
    report[:objects_scanned] = count
    report[:scan_seconds] = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(1)
  end

  def verify_replicated(report, newest)
    key = newest.key
    age = Time.current - newest.last_modified

    # Prefer S3's own replication_status (x-amz-replication-status on HeadObject)
    # over guessing from a clock: it says definitively whether replication is
    # done, still pending, or failed. It only comes from HeadObject, not from
    # the listing, hence the extra call.
    replication_status = source_client.head_object(bucket: report[:source_bucket], key: key).replication_status
    report[:replication_status] = replication_status

    case replication_status
    when 'FAILED'
      return finish(report, 'FAILED', "S3 marked replication of '#{key}' as FAILED", failure: true)
    when 'PENDING'
      return finish(report, 'STUCK', "'#{key}' is still PENDING replication after #{(age / 1.hour).round(1)}h", failure: true) if age > PENDING_MAX_AGE

      return finish(report, 'PENDING', "'#{key}' is still copying (PENDING for #{(age / 1.minute).round} min)")
    end

    # COMPLETED — or no status at all (object not covered by a rule, or written
    # before replication was enabled): either way, the replica is the proof.
    replica = begin
      replica_client.head_object(bucket: report[:replica_bucket], key: key)
    rescue Aws::S3::Errors::NotFound
      nil
    end

    return finish(report, 'MISSING', "the newest file '#{key}' (#{replication_status || 'no replication status'}) is not in s3://#{report[:replica_bucket]}", failure: true) unless replica
    return finish(report, 'SIZE DIFFERS', "'#{key}' is #{newest.size} bytes in the source but #{replica.content_length} in the replica", failure: true) if replica.content_length != newest.size

    finish(report, 'ok', "the newest file '#{key}' is in s3://#{report[:replica_bucket]} with the same size")
  end

  def finish(report, status, detail, failure: false)
    report[:status] = status
    report[:detail] = detail
    report[:failures] << detail if failure
    # A broken rule outranks a file that still happens to be present (or one
    # still copying): no future upload will replicate.
    report[:status] = 'NO RULE' if %w[ok PENDING EMPTY].include?(status) && !rule_ok?(report[:rule])
    report
  end

  def source_client
    @source_client ||= s3_client(ENV.fetch('AWS_S3_REGION', nil))
  end

  def replica_client
    @replica_client ||= s3_client(ENV.fetch('AWS_S3_REPLICA_REGION', nil))
  end

  def s3_client(region)
    Aws::S3::Client.new(
      access_key_id: credentials[:AWS_ACCESS_KEY_ID],
      secret_access_key: credentials[:AWS_SECRET_ACCESS_KEY],
      region: region
    )
  end

  # Mirrors DbBackupFreshnessJob#credentials.
  def credentials
    @credentials ||= if @env_name
                       key_path = Rails.root.join("config", "credentials", "#{@env_name}.key")
                       raise "Key file not found for environment '#{@env_name}' at #{key_path}" unless File.exist?(key_path)

                       Rails.application.encrypted(
                         Rails.root.join("config", "credentials", "#{@env_name}.yml.enc"),
                         key_path: key_path
                       )
                     else
                       Rails.application.credentials
                     end
  end
end
