require 'sidekiq'
require 'etc' # page size lookup for SidekiqJobMemoryMetrics RSS reads

# Server middleware that attributes memory consumption to individual job classes.
# prometheus_exporter's built-in Sidekiq instrumentation only reports counts and
# durations per job — memory (ruby_rss / ruby_heap_*) is only known per PROCESS.
# This middleware measures each job execution and pushes two counters, which the
# Sidekiq Grafana dashboard (graphana/*/sidekiq.dashboard.json) charts by job_name:
#
#   ruby_sidekiq_job_rss_growth_bytes   — positive RSS delta across the job run.
#                                         A leaky job class accumulates a large total.
#   ruby_sidekiq_job_allocated_objects  — objects allocated during the job run.
#                                         High churn = GC pressure even without a leak.
#
# Accuracy caveat: Sidekiq runs 5 concurrent threads (plus single-threaded capsules),
# and both RSS and GC.stat are process-wide, so deltas from overlapping jobs bleed
# into each other. Attribution is therefore approximate — but over hours of traffic
# the leaky/heavy job classes still dominate their own counters, which is what the
# dashboard needs. RSS shrinking mid-job (GC/malloc_trim) is clamped to 0, not negated.
class SidekiqJobMemoryMetrics
  # Registered lazily so the class can load before PrometheusExporter's client exists.
  # Counters are remote metrics — observe() ships them to the shared exporter, which
  # applies the global "ruby_" prefix (same reason ruby_rss is "rss" in code).
  def self.rss_growth_counter
    @rss_growth_counter ||= PrometheusExporter::Client.default.register(
      :counter, 'sidekiq_job_rss_growth_bytes',
      'Cumulative positive RSS growth (bytes) observed across job executions, by job class'
    )
  end

  def self.allocations_counter
    @allocations_counter ||= PrometheusExporter::Client.default.register(
      :counter, 'sidekiq_job_allocated_objects',
      'Cumulative Ruby objects allocated during job executions, by job class'
    )
  end

  def call(worker, msg, queue)
    rss_before       = current_rss_bytes
    allocated_before = GC.stat(:total_allocated_objects)
    yield
  ensure
    # Metrics must never fail a job or mask its exception — hence rescue-all here.
    begin
      # Reuse the patched get_name below so ActiveJob wrappers resolve to the real
      # class (DocGenJob), matching the job_name label on the built-in job metrics.
      labels = {
        job_name: PrometheusExporter::Instrumentation::Sidekiq.get_name(worker.class.to_s, msg),
        queue:    queue,
      }
      rss_delta = current_rss_bytes - rss_before
      self.class.rss_growth_counter.observe(rss_delta, labels) if rss_delta.positive?
      self.class.allocations_counter.observe(GC.stat(:total_allocated_objects) - allocated_before, labels)
    rescue StandardError
      nil
    end
  end

  private

  # RSS from /proc/self/statm (resident pages × page size) — no shell-out, ~µs cost.
  # Falls back to 0 (making deltas 0, never negative garbage) on non-Linux/dev edge cases.
  def current_rss_bytes
    @page_size ||= Etc.sysconf(Etc::SC_PAGE_SIZE)
    File.read('/proc/self/statm').split[1].to_i * @page_size
  rescue StandardError
    0
  end
end

Sidekiq.configure_server do |config|
  # edits the default capsule
  config.queues = %w[critical high default low chewy agents]

  config.concurrency = 5

  # define a new capsule which processes jobs from the `serial and doc_gen` queue one at a time
  config.capsule("single-threaded") do |cap|
    cap.concurrency = 1
    cap.queues = %w[serial doc_gen ai_checks]
  end

  # New capsule for db_restore jobs
  config.capsule("db_restore") do |cap|
    cap.concurrency = 1 # run only one restore job at a time
    cap.queues = %w[db_restore]
  end

  unless Rails.env.local?

    # Used to update the tracking currency for all funds

    Sidekiq::Cron::Job.create(name: 'WorkflowAutoReminderJob', cron: 'every day at 06:00', class: 'WorkflowAutoReminderJob')
    # Drives ALL support agent schedules (AgentSchedule → AgentRunnerJob): scans
    # due schedules and enqueues runs. Was never cron-registered before, so no
    # scheduled agent (incl. the SideLetterObligationAgent daily enforcement
    # pass) ever fired outside manual runs. NOTE: on first deploy this activates
    # any stored enabled schedules whose next_run_at has already passed.
    Sidekiq::Cron::Job.create(name: 'SchedulerPollingJob', cron: 'every 10 minutes', class: 'SchedulerPollingJob')
    Sidekiq::Cron::Job.create(name: 'RecurringTaskGeneratorJob', cron: 'every day at 01:00', class: 'RecurringTaskGeneratorJob')
    # Weekly task digest — Friday (docs/product/weekly_task_digest_prd.md). Server
    # clocks are UTC regardless of region (see the sidekiq_restart_at comment in
    # config/schedule.rb), so this expression is UTC: 11:30 UTC Friday is 5:00pm IST
    # and 7:30am US Eastern. Override per region with WEEKLY_TASK_DIGEST_CRON rather
    # than editing this line. The job itself sends nothing until an entity turns on
    # entity_setting.weekly_task_digest_enabled.
    Sidekiq::Cron::Job.create(name: 'WeeklyTaskDigestJob', cron: ENV.fetch('WEEKLY_TASK_DIGEST_CRON', '30 11 * * 5'), class: 'WeeklyTaskDigestJob')
    Sidekiq::Cron::Job.create(name: 'MultiSiteUserSyncAllJob', cron: 'every day at 01:00', class: 'MultiSiteUserSyncAllJob')
    Sidekiq::Cron::Job.create(name: 'TrackingCurrencyJob', cron: 'every day at 01:00', class: 'TrackingCurrencyJob')
    # Used to cleanup various models in the DB
    Sidekiq::Cron::Job.create(name: 'DailyMorningJob', cron: 'every day at 01:30', class: 'DailyMorningJob')
    # Update the overdue status of remittances
    Sidekiq::Cron::Job.create(name: 'CapitalRemittanceStatusJob', cron: 'every day at 01:30', class: 'CapitalRemittanceStatusJob')
    # Check the S3 bucket for the backup
    Sidekiq::Cron::Job.create(name: 'S3CheckJob', cron: 'every 1 hour', class: 'S3CheckJob') if Rails.env.production?
    # Alert when DB backups (xtrabackup buckets, primary + cross-region replica)
    # go stale — catches dead cron, unarmed marker, broken replication, IAM drift.
    # Deliberately NOT production-gated: staging backups silently died on
    # 2026-06-08 and the gap went unnoticed for a month until a DR drill
    # restored a 30-day-old database. Staging monitors its own buckets.
    Sidekiq::Cron::Job.create(name: 'DbBackupFreshnessJob', cron: 'every 1 hour', class: 'DbBackupFreshnessJob')
    # Cleanup the old logs for ESign
    Sidekiq::Cron::Job.create(name: 'EsignLogCleanupJob', cron: '59 23 * * 0', class: 'EsignLogCleanupJob')
    # SkippedNotificationReportJob is NOT cron-scheduled — ApplicationMailer#record_notification_skip
    # enqueues it directly (with a delay) the moment a recipient is actually skipped, so it never
    # runs on a timer when nothing happened. See that method for details.

    if Rails.env.production?
      # Snapshot the funds at the end of every quarter March, June, September and December
      Sidekiq::Cron::Job.create(name: 'FundSnapshotJob', cron: '0 2 31 3,12 *', class: 'FundSnapshotJob')
      Sidekiq::Cron::Job.create(name: 'FundSnapshotJob', cron: '0 2 30 6,9 *', class: 'FundSnapshotJob')
      Sidekiq::Cron::Job.create(name: 'ReplicationHealthJob', cron: 'every 5 minutes', class: 'ReplicationHealthJob')
    end

    Sidekiq::Cron::Job.create(name: 'DbRestoreJob', cron: 'every 4 hours', class: 'DbRestoreJob') if Rails.env.production? # Rails.env.staging? works # rubocop:disable Rails/UnknownEnv

    # Sidekiq::Cron::Job.create(name: 'Weekly Compliance Checks', cron: '59 23 * * 0', class: 'Com')
  end
end

Sidekiq.default_configuration[:max_retries] = 2

Sidekiq.configure_server do |config|
  require 'prometheus_exporter/instrumentation'

  # prometheus_exporter knows how to unwrap the old ActiveJob wrapper class name but not the
  # new one used by Rails 7+ with Sidekiq 7+. Extend get_name to handle both so the real
  # job class (e.g. DocGenJob) appears in Prometheus instead of "Sidekiq::ActiveJob::Wrapper".
  #
  # Strings are hardcoded rather than referencing gem constants (JOB_WRAPPER_CLASS_NAME,
  # DELAYED_CLASS_NAMES) because those constants vary across prometheus_exporter versions
  # and cause NameError when the production gem version differs from development.
  PrometheusExporter::Instrumentation::Sidekiq.class_eval do
    ACTIVEJOB_WRAPPER_NAMES = [
      "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper", # Rails <7 / old Sidekiq adapter
      "Sidekiq::ActiveJob::Wrapper",                          # Sidekiq 7+ native ActiveJob wrapper
    ].freeze

    DELAYED_WRAPPER_NAMES = %w[
      Sidekiq::Extensions::DelayedClass
      Sidekiq::Extensions::DelayedModel
      Sidekiq::Extensions::DelayedMailer
    ].freeze

    def self.get_name(class_name, msg)
      if ACTIVEJOB_WRAPPER_NAMES.include?(class_name)
        get_job_wrapper_name(msg)
      elsif DELAYED_WRAPPER_NAMES.include?(class_name)
        get_delayed_name(msg, class_name)
      else
        class_name
      end
    end
  end

  config.server_middleware do |chain|
    chain.add PrometheusExporter::Instrumentation::Sidekiq
    # Per-job memory attribution (RSS growth + allocations) — see class comment above.
    chain.add SidekiqJobMemoryMetrics
  end
  config.death_handlers << PrometheusExporter::Instrumentation::Sidekiq.death_handler
  config.on :startup do
    PrometheusExporter::Instrumentation::Process.start type: 'sidekiq'
    PrometheusExporter::Instrumentation::SidekiqProcess.start
    PrometheusExporter::Instrumentation::SidekiqQueue.start
    PrometheusExporter::Instrumentation::SidekiqStats.start
  end
end

# Sidekiq.redis(&:flushdb)
