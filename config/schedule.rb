# Learn more: http://github.com/javan/whenever
# env 'MAILTO', 'support@caphive.com'

set :path, "/home/ubuntu/IRM/current"
job_type :bundle, 'cd :path && :environment_variable=:environment bundle exec :task'

every 1.day, at: '02:01 am', roles: [:primary] do
  # runner "ElasticImporterJob.perform_now"
  runner "VestedJob.perform_now"
  runner "Entity.recompute_all"
  runner "DocumentEsignUpdateJob.perform_now"
  # Delete old notifications
  runner "Noticed::Notification.where(created_at: ..(Date.today - 2.month)).each(&:destroy)"
  runner "Noticed::Event.where(created_at: ..(Date.today - 2.month)).each(&:destroy)"
  runner "SecondarySale.where(active: true, end_date: ..Date.today).update(active: false)"
end

every 1.hour, roles: [:primary] do
  # Backup the database
  rake "db:backup"
  # Replace with Incremental DB backup # Add Full DB backup https://www.percona.com/mysql/software/percona-xtrabackup

  # Check if the latest file in the source bucket is present in the destination bucket
  rake "s3:check_latest_file"
end

every 1.day, at: '23:30 am', roles: [:primary] do
  runner "ReminderJob.perform_now"
  runner "InvestorNoticeJob.perform_now"
  runner "SignatureWorkflowJob.perform_now"
  runner "Notification.where(created_at: ..(Date.today - 1.month)).each(&:destroy)"
end

every 1.week, at: '02:30 am', roles: [:primary] do
  # Ensure that enable is set to false for all SupportClientMappings after end_date
  runner "SupportClientMapping.disable_expired"
  rake '"aws:create_and_copy_ami[AppServer]"'
  rake '"aws:create_and_copy_ami[DB-Redis-ES]"'
end

every :reboot, roles: [:app] do
  bundle "sidekiq"
  bundle "puma --yjit -C /home/ubuntu/IRM/shared/puma.rb"
  command 'sudo docker run -d --rm --name xirr_py -p 8000:80 thimmaiah/xirr_py'
end

every 1.day, at: '02:01 am', roles: [:all] do
  command "logrotate /home/ubuntu/IRM/shared/log/logrotate.conf --state /home/ubuntu/IRM/shared/log/logrotate.state --verbose"
end
