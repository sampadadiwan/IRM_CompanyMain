# Learn more: http://github.com/javan/whenever

set :path, "/home/ubuntu/IRM/current"
job_type :bundle, 'cd :path && :environment_variable=:environment bundle exec :task'

every 1.day, at: '02:01 am' do
  command "logrotate /home/ubuntu/IRM/shared/log/logrotate.conf --state /home/ubuntu/IRM/shared/log/logrotate.state --verbose"
  # runner "ElasticImporterJob.new.perform"
  runner "VestedJob.new.perform"
  runner "ClearMessagesCountJob.new.perform"
  runner "Entity.recompute_all"
  runner "InvestmentSnapshotJob.new.perform"
end

every 1.hours do
  rake "db:backup"
end

every 1.day, at: '23:30 am' do
  runner "ReminderJob.new.perform"
end

every :reboot do
  bundle "sidekiq"
  bundle "puma -C /home/ubuntu/IRM/shared/puma.rb"
end

# every 1.hour do
#   # runner "Money.default_bank.save_rates('tmp/exchange_rates.xml')"
# end
