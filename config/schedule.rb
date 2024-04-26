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
  # Delete old notifications
  runner "Noticed::Notification.where(created_at: ..(Date.today - 2.month)).each(&:destroy)"
  runner "Noticed::Event.where(created_at: ..(Date.today - 2.month)).each(&:destroy)"
end

every 1.week, at: '02:00 am' do
  # Ensure that enable is set to false for all SupportClientMappings after end_date
  runner "SupportClientMapping.disable_expired"
end

every 1.hour do
  # Backup the database
  rake "db:backup"
  # Check if the latest file in the source bucket is present in the destination bucket
  rake "s3:check_latest_file" if Rails.env.production?
end

every 1.day, at: '23:30 am' do
  runner "ReminderJob.perform_now"
  runner "InvestorNoticeJob.perform_now"
  runner "SignatureWorkflowJob.perform_now"
  runner "Notification.where(created_at: ..(Date.today - 1.month)).each(&:destroy)"
end

every :reboot do
  bundle "sidekiq --yjit"
  bundle "puma --yijit -C /home/ubuntu/IRM/shared/puma.rb"
  command 'sudo docker run -d --rm --name xirr_py -p 8000:80 thimmaiah/xirr_py'
end

# every 1.hour do
#   # runner "Money.default_bank.save_rates('tmp/exchange_rates.xml')"
# end
