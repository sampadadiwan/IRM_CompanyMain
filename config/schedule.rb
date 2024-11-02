# Learn more: http://github.com/javan/whenever
# env 'MAILTO', 'support@caphive.com'

set :path, "/home/ubuntu/IRM/current"
job_type :bundle, 'cd :path && :environment_variable=:environment bundle exec :task'

every 1.week, at: '02:00 am', roles: [:primary] do
  # Ensure that enable is set to false for all SupportClientMappings after end_date
  rake '"aws:create_and_copy_ami[AppServer]"'
  rake '"aws:create_and_copy_ami[DB-Redis-ES]"'
end

every :reboot, roles: [:app] do
  bundle "sidekiq"
  bundle "prometheus_exporter -b 0.0.0.0"
  bundle "puma -C /home/ubuntu/IRM/shared/puma.rb"
  command 'sudo docker run -d --rm --name xirr_py -p 8000:80 -v /tmp:/tmp thimmaiah/xirr_py:v2.0'
  command 'sudo docker run -d --rm --name=node-exporter -p 9100:9100  prom/node-exporter'
end

# Note times are in UTC, as our users are in IST 8:30 pm UTC is 2:00 am IST
every 1.day, at: '02:30 am', roles: [:all] do
  command "logrotate /home/ubuntu/IRM/shared/log/logrotate.conf --state /home/ubuntu/IRM/shared/log/logrotate.state --verbose"
end

# Reboot servers
# Note times are in UTC, as our users are in IST 10:30 pm UTC is 4:00 am IST
every :saturday, at: '3:00 am', roles: [:app] do
  command 'sudo reboot'
end
