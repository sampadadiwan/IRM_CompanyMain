require 'sidekiq'

Sidekiq.configure_server do |config|
  # edits the default capsule
  config.queues = %w[critical high default low chewy]
  config.concurrency = 5

  # define a new capsule which processes jobs from the `serial and doc_gen` queue one at a time
  config.capsule("single-threaded") do |cap|
    cap.concurrency = 1
    cap.queues = %w[serial doc_gen]
  end

  # 20:30 UTC is 2:00 am IST
  Sidekiq::Cron::Job.create(name: 'DailyMorningJob', cron: 'every day at 20:30', class: 'DailyMorningJob')
  Sidekiq::Cron::Job.create(name: 'ReplicationHealthJob', cron: 'every 5 minutes', class: 'ReplicationHealthJob')
  Sidekiq::Cron::Job.create(name: 'BackupDbJob', cron: 'every 1 hour', class: 'BackupDbJob')
  Sidekiq::Cron::Job.create(name: 'S3CheckJob', cron: 'every 1 hour', class: 'S3CheckJob')
end

Sidekiq.default_configuration[:max_retries] = 2
