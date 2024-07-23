require 'sidekiq'
# require 'sidekiq-scheduler'

Sidekiq.configure_server do |config|
  # edits the default capsule
  config.queues = %w[critical high default low chewy]
  config.concurrency = 5

  # define a new capsule which processes jobs from the `serial and doc_gen` queue one at a time
  config.capsule("single-threaded") do |cap|
    cap.concurrency = 1
    cap.queues = %w[serial doc_gen]
  end

  # config.on(:startup) do
  #   Sidekiq.schedule = YAML.load_file(File.expand_path('../sidekiq_scheduler.yml', __dir__))
  #   SidekiqScheduler::Scheduler.instance.reload_schedule!
  # end

  Sidekiq::Cron::Job.create(name: 'DailyMorningJob', cron: '*/1 * * * *', class: 'DailyMorningJob')
end

Sidekiq.default_configuration[:max_retries] = 2
