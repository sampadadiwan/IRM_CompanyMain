# Learn more: http://github.com/javan/whenever

set :path, "/home/ubuntu/IRM/current"
job_type :bundle, 'cd :path && :environment_variable=:environment bundle exec :task'

every 1.day, at: '02:01 am' do
  command "logrotate /home/ubuntu/IRM/shared/log/logrotate.conf --state /home/ubuntu/IRM/shared/log/logrotate.state --verbose"

  runner "ElasticImporterJob.perform_now"
  runner "VestedJob.perform_now"
  # runner "ClearMessagesCountJob.perform_now"
  runner "Entity.recompute_all"
  # runner "InvestmentSnapshotJob.perform_now"
  # runner "ResendConfirmationJob.perform_now"
  runner "DocumentEsignUpdateJob.perform_now"
end

every 1.hour do
  rake "db:backup"
end

every 1.day, at: '23:30 am' do
  runner "ReminderJob.perform_now"
  runner "InvestorNoticeJob.perform_now"
  runner "SignatureWorkflowJob.perform_now"
end

every :reboot do
  bundle "sidekiq"
  bundle "puma -C /home/ubuntu/IRM/shared/puma.rb"
  command 'sudo docker run -d --rm --name xirr_py -p 8000:80 thimmaiah/xirr_py'
end

# every 1.hour do
#   # runner "Money.default_bank.save_rates('tmp/exchange_rates.xml')"
# end
