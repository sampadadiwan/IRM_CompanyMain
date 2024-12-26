require 'sidekiq'

Sidekiq.configure_server do |config|
  # edits the default capsule
  config.queues = %w[critical high default low chewy]
  config.concurrency = 5

  # define a new capsule which processes jobs from the `serial and doc_gen` queue one at a time
  config.capsule("single-threaded") do |cap|
    cap.concurrency = 1
    cap.queues = %w[serial doc_gen ai_checks]
  end

  unless Rails.env.local?
    Sidekiq::Cron::Job.create(name: 'DailyMorningJob', cron: 'every day at 01:30', class: 'DailyMorningJob')
    Sidekiq::Cron::Job.create(name: 'CapitalRemittanceStatusJob', cron: 'every day at 01:30', class: 'CapitalRemittanceStatusJob')
    Sidekiq::Cron::Job.create(name: 'ReplicationHealthJob', cron: 'every 5 minutes', class: 'ReplicationHealthJob')
    Sidekiq::Cron::Job.create(name: 'BackupDbJob', cron: 'every 1 hour', class: 'BackupDbJob')
    Sidekiq::Cron::Job.create(name: 'S3CheckJob', cron: 'every 1 hour', class: 'S3CheckJob')
    Sidekiq::Cron::Job.create(name: 'EsignLogCleanupJob', cron: '59 23 * * 0', class: 'EsignLogCleanupJob')

    # Sidekiq::Cron::Job.create(name: 'Weekly Compliance Checks', cron: '59 23 * * 0', class: 'Com')
  end
end

Sidekiq.default_configuration[:max_retries] = 2

Sidekiq.configure_server do |config|
  require 'prometheus_exporter/instrumentation'
  config.server_middleware do |chain|
    chain.add PrometheusExporter::Instrumentation::Sidekiq
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
