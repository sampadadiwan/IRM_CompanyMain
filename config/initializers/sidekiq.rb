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

  # SidekiqCanaryJob's own thread. On a shared capsule the canary queues behind
  # whatever is running, so five long imports/exports would read as "Sidekiq is
  # not processing" and fire a false critical alert. Here it proves the process
  # is fetching and executing jobs; a backlog is the queue-latency alert's job.
  config.capsule("canary") do |cap|
    cap.concurrency = 1
    cap.queues = %w[canary]
  end

  # Support Console turns: each job holds an HTTP stream to the support machine for up to
  # 15 minutes, so they get their own threads instead of starving the default capsule. Three
  # keeps Bedrock spend bounded and stays under support_ro's 4 replica connections.
  config.capsule("support_console") do |cap|
    cap.concurrency = 3
    cap.queues = %w[support_console]
  end

  # Per-region LOCAL time anchors for the fixed-time cron strings below.
  # config/schedule.rb gets env_variant at DEPLOY time via Capistrano/whenever
  # (see maintenance_bake_at there); this file is a plain initializer loaded
  # at RAILS BOOT from the identical codebase in every region, so that
  # variable doesn't exist here. AWS_REGION — baked into .env.production.{in,us}
  # and already used the same way by db_backup_xtra.sh / the xtrabackup rake
  # tasks — is the runtime equivalent. All cron strings below are UTC (Fugit's
  # default with no TZ= prefix, confirmed by the WeeklyTaskDigestJob comment),
  # so a flat UTC time landed these jobs at ~6:30-8:30am IST — mid-morning in
  # India — same issue the maintenance window in schedule.rb had.
  in_region = ENV.fetch('AWS_REGION', '').start_with?('ap-south')

  unless Rails.env.local?

    # Daily off-peak maintenance block, LOCAL midnight-to-1:30am, staggered
    # 15 minutes apart so seven jobs don't all hit the DB in the same tick.
    # Ordered so data-generating jobs run before things that read what they
    # just produced, and non-essential cleanup/verification runs last:
    #   00:00 RecurringTaskGeneratorJob — today's recurring tasks exist before
    #         anything downstream looks for them
    #   00:15 MultiSiteUserSyncAllJob   — user data other jobs may reference
    #   00:30 TrackingCurrencyJob
    #   00:45 CapitalRemittanceStatusJob — reads updated currency data
    #   01:00 DailyMorningJob           — general DB cleanup, after the above
    #   01:15 WebsiteLeadPurgeJob       — non-essential retention purge
    #   01:30 FaqVerificationJob        — non-essential link/staleness check, last
    # UTC per slot: in -> 18:30/18:45/19:00/19:15/19:30/19:45/20:00 (day
    # before); us -> 04:30/04:45/05:00/05:15/05:30/05:45/06:00 (same day).
    recurring_task_cron        = in_region ? '30 18 * * *' : '30 4 * * *'
    multi_site_sync_cron       = in_region ? '45 18 * * *' : '45 4 * * *'
    tracking_currency_cron     = in_region ? '0 19 * * *'  : '0 5 * * *'
    capital_remittance_cron    = in_region ? '15 19 * * *' : '15 5 * * *'
    daily_morning_cron         = in_region ? '30 19 * * *' : '30 5 * * *'
    website_lead_purge_cron    = in_region ? '45 19 * * *' : '45 5 * * *'
    faq_verification_cron      = in_region ? '0 20 * * *'  : '0 6 * * *'

    # 6:00am LOCAL, after the maintenance block above has finished: in ->
    # 00:30 UTC same day; us -> 10:30 UTC splits the EDT/EST difference (same
    # "split the difference" approach as sidekiq_restart_at in
    # config/schedule.rb).
    workflow_reminder_cron = in_region ? '30 0 * * *' : '30 10 * * *'
    Sidekiq::Cron::Job.create(name: 'WorkflowAutoReminderJob', cron: workflow_reminder_cron, class: 'WorkflowAutoReminderJob')
    # capital-call-journey: re-checks every journey every 15 minutes so progress is picked up and
    # approvers are told promptly even when nobody opens the record (WorkflowEvaluateJob)
    Sidekiq::Cron::Job.create(name: 'WorkflowEvaluateJob', cron: '*/15 * * * *', class: 'WorkflowEvaluateJob')
    # Evergreen jobs follow the same per-region LOCAL anchors as the jobs above (review fix 10, 10 Oct
    # 2026). They used flat UTC times, which in the US region put the investor reminders and team
    # alerts at ~11:30pm Eastern the evening before.
    # Evergreen funds: generate upcoming dealing dates (and their journeys) daily (open-ended-funds H16).
    # 01:45 LOCAL, right after the maintenance block ends at 01:30: in -> 20:15 UTC (day before);
    # us -> 06:15 UTC.
    dealing_date_generate_cron = in_region ? '15 20 * * *' : '15 6 * * *'
    Sidekiq::Cron::Job.create(name: 'DealingDateGenerateJob', cron: dealing_date_generate_cron, class: 'DealingDateGenerateJob')
    # Evergreen funds: daily reminders, cut-off summaries and overdue checks (open-ended-funds § Notifications).
    # 08:00 LOCAL, before the working day: in -> 02:30 UTC; us -> 12:30 UTC (splits EDT/EST, as above).
    evergreen_notifications_cron = in_region ? '30 2 * * *' : '30 12 * * *'
    Sidekiq::Cron::Job.create(name: 'EvergreenNotificationsJob', cron: evergreen_notifications_cron, class: 'EvergreenNotificationsJob')
    # Drives ALL support agent schedules (AgentSchedule → AgentRunnerJob): scans
    # due schedules and enqueues runs. Was never cron-registered before, so no
    # scheduled agent (incl. the SideLetterObligationAgent daily enforcement
    # pass) ever fired outside manual runs. NOTE: on first deploy this activates
    # any stored enabled schedules whose next_run_at has already passed.
    Sidekiq::Cron::Job.create(name: 'SchedulerPollingJob', cron: 'every 10 minutes', class: 'SchedulerPollingJob')
    # LP mobile app: Expo push receipts (dead phones) and delivery-log retention (lp-mobile-app X10).
    # Does nothing in a region without an Expo access token.
    Sidekiq::Cron::Job.create(name: 'ExpoPushReceiptsJob', cron: '*/15 * * * *', class: 'ExpoPushReceiptsJob')
    # ReportSchedules can be due any hour of the day, so this stays on an
    # always-on hourly cadence rather than joining the off-peak block above.
    # Was `runner "ReportBuilderSchedulerJob.perform_later"` from
    # config/schedule.rb — a full Rails boot 24x/day just to enqueue one job;
    # sidekiq-cron can invoke the job class directly.
    Sidekiq::Cron::Job.create(name: 'ReportBuilderSchedulerJob', cron: 'every 1 hour', class: 'ReportBuilderSchedulerJob')

    Sidekiq::Cron::Job.create(name: 'RecurringTaskGeneratorJob', cron: recurring_task_cron, class: 'RecurringTaskGeneratorJob')
    # Weekly task digest — Friday (docs/modules/tasks/weekly_task_digest_prd.md). Server
    # clocks are UTC regardless of region (see the sidekiq_restart_at comment in
    # config/schedule.rb), so this expression is UTC: 11:30 UTC Friday is 5:00pm IST
    # and 7:30am US Eastern. Override per region with WEEKLY_TASK_DIGEST_CRON rather
    # than editing this line. The job itself sends nothing until an entity turns on
    # entity_setting.weekly_task_digest_enabled.
    Sidekiq::Cron::Job.create(name: 'WeeklyTaskDigestJob', cron: ENV.fetch('WEEKLY_TASK_DIGEST_CRON', '30 11 * * 5'), class: 'WeeklyTaskDigestJob')
    Sidekiq::Cron::Job.create(name: 'MultiSiteUserSyncAllJob', cron: multi_site_sync_cron, class: 'MultiSiteUserSyncAllJob')
    # Confirms both regions still share CROSS_INSTANCE_SECRET. Hourly and always-on rather
    # than in the off-peak block above: a divergence breaks EVERY region switch, and the
    # 90-minute cache TTL on the result assumes an hourly cadence.
    Sidekiq::Cron::Job.create(name: 'CrossSiteTrustCheckJob', cron: ENV.fetch('CROSS_SITE_TRUST_CRON', 'every 1 hour'), class: 'CrossSiteTrustCheckJob')
    Sidekiq::Cron::Job.create(name: 'TrackingCurrencyJob', cron: tracking_currency_cron, class: 'TrackingCurrencyJob')
    # fund-market-data: ECB publishes its reference rates around 16:00 CET on TARGET business days;
    # load them at 15:30 UTC on weekdays in both regions (FxFeedJob skips weekends itself).
    Sidekiq::Cron::Job.create(name: 'FxFeedJob', cron: '30 15 * * 1-5', class: 'FxFeedJob')
    # fund-market-data: NSE/BSE publish their daily bhavcopy by about 19:00 IST and AMFI its NAVs by
    # about 21:00 IST; load prices at 16:00 UTC (21:30 IST) on weekdays.
    Sidekiq::Cron::Job.create(name: 'PriceFeedJob', cron: '0 16 * * 1-5', class: 'PriceFeedJob')
    # fund-market-data: one reminder 5 business days before an open derivative contract expires
    Sidekiq::Cron::Job.create(name: 'DerivativeExpiryJob', cron: '30 3 * * *', class: 'DerivativeExpiryJob')
    # support-console: purge conversations 90 days after their last message (and their machine
    # transcripts), and close turns left running by a restart.
    Sidekiq::Cron::Job.create(name: 'SupportConsoleRetentionJob', cron: '0 21 * * *', class: 'SupportConsoleRetentionJob')
    # support-console: stop the support machine after an hour with no questions (the next one starts it)
    Sidekiq::Cron::Job.create(name: 'SupportConsoleIdleStopJob', cron: 'every 10 minutes', class: 'SupportConsoleIdleStopJob')

    # Used to cleanup various models in the DB
    Sidekiq::Cron::Job.create(name: 'DailyMorningJob', cron: daily_morning_cron, class: 'DailyMorningJob')
    # Update the overdue status of remittances
    Sidekiq::Cron::Job.create(name: 'CapitalRemittanceStatusJob', cron: capital_remittance_cron, class: 'CapitalRemittanceStatusJob')
    # Was `rake "website_leads:purge"` from config/schedule.rb — see
    # WebsiteLeadPurgeJob for why it moved here.
    Sidekiq::Cron::Job.create(name: 'WebsiteLeadPurgeJob', cron: website_lead_purge_cron, class: 'WebsiteLeadPurgeJob')
    # Flags published user-guide FAQs whose paths or links broke, or that are overdue for re-verification.
    Sidekiq::Cron::Job.create(name: 'FaqVerificationJob', cron: faq_verification_cron, class: 'FaqVerificationJob')
    # Check the S3 bucket for the backup
    Sidekiq::Cron::Job.create(name: 'S3CheckJob', cron: 'every 1 hour', class: 'S3CheckJob') if Rails.env.production?
    # Alert when DB backups (xtrabackup buckets, primary + cross-region replica)
    # go stale — catches dead cron, unarmed marker, broken replication, IAM drift.
    # Deliberately NOT production-gated: staging backups silently died on
    # 2026-06-08 and the gap went unnoticed for a month until a DR drill
    # restored a 30-day-old database. Staging monitors its own buckets.
    Sidekiq::Cron::Job.create(name: 'DbBackupFreshnessJob', cron: 'every 1 hour', class: 'DbBackupFreshnessJob')
    # Records that a job actually ran; "Sidekiq Canary Stale" fires when it stops.
    # See SidekiqCanaryJob for why process liveness alone missed stuck workers.
    Sidekiq::Cron::Job.create(name: 'SidekiqCanaryJob', cron: '* * * * *', class: 'SidekiqCanaryJob')

    # Sunday 11:59pm LOCAL: in -> 18:29 UTC the same Sunday; us -> 04:29 UTC
    # Monday (the local instant is close enough to midnight that the +4:30h
    # US split pushes it across into the next UTC day — the day-of-week
    # field has to shift too, not just the hour).
    esign_cleanup_cron = in_region ? '29 18 * * 0' : '29 4 * * 1'
    # Cleanup the old logs for ESign
    Sidekiq::Cron::Job.create(name: 'EsignLogCleanupJob', cron: esign_cleanup_cron, class: 'EsignLogCleanupJob')
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
