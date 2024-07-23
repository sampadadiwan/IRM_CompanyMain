# Learn more: http://github.com/javan/whenever
# env 'MAILTO', 'support@caphive.com'

set :path, "/home/ubuntu/IRM/current"
job_type :bundle, 'cd :path && :environment_variable=:environment bundle exec :task'

every 1.hour, roles: [:primary] do
  # Backup the database
  rake "db:backup"
  # Replace with Incremental DB backup # Add Full DB backup https://www.percona.com/mysql/software/percona-xtrabackup

  # Check if the latest file in the source bucket is present in the destination bucket
  rake "s3:check_latest_file"
end

every 1.week, at: '09:00 pm', roles: [:primary] do
  # Ensure that enable is set to false for all SupportClientMappings after end_date
  rake '"aws:create_and_copy_ami[AppServer]"'
  rake '"aws:create_and_copy_ami[DB-Redis-ES]"'
end

every :reboot, roles: [:app] do
  bundle "sidekiq"
  bundle "puma -C /home/ubuntu/IRM/shared/puma.rb"
  command 'sudo docker run -d --rm --name xirr_py -p 8000:80 thimmaiah/xirr_py'
end

# Note times are in UTC, as our users are in IST 8:30 pm UTC is 2:00 am IST
every 1.day, at: '08:30 pm', roles: [:all] do
  command "logrotate /home/ubuntu/IRM/shared/log/logrotate.conf --state /home/ubuntu/IRM/shared/log/logrotate.state --verbose"
end

# Reboot servers
# Note times are in UTC, as our users are in IST 10:30 pm UTC is 4:00 am IST
every :saturday, at: '10:30 pm', roles: [:app] do
  command 'sudo reboot'
end
