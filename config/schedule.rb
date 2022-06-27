# Learn more: http://github.com/javan/whenever

set :path, "/home/ubuntu/IRM/current"
job_type :bundle, 'cd :path && :environment_variable=:environment bundle exec :task'

every 1.day, at: '02:01 am' do
  command "logrotate /home/ubuntu/IRM/shared/log/logrotate.conf --state /home/ubuntu/IRM/shared/log/logrotate.state --verbose"
  # runner "ElasticImporterJob.new.perform"
  runner "VestedJob.new.perform"
  runner "ClearMessagesCountJob.new.perform"
  runner "Entity.recompute_all"
end

every :reboot do
  bundle "sidekiq"
  # runner "ElasticImporterJob.new.perform"
  bundle "puma -C /home/ubuntu/IRM/shared/puma.rb"
  # runner "Money.default_bank.save_rates('tmp/exchange_rates.xml')"
end

every 1.hour do
  # runner "Money.default_bank.save_rates('tmp/exchange_rates.xml')"
end
