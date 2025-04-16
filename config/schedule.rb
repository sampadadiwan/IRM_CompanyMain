# Learn more: http://github.com/javan/whenever
# env 'MAILTO', 'support@caphive.com'

set :path, "/home/ubuntu/IRM/current"
job_type :bundle, 'cd :path && :environment_variable=:environment bundle exec :task'

every 1.week, at: '02:00 am', roles: [:primary] do
  # Ensure AMIs are created and backed up
  rake '"aws:create_and_copy_ami[AppServer]"'
  rake '"aws:create_and_copy_ami[DB-Redis-ES]"'
  rake '"aws:create_and_copy_ami[Observability]"'
end

every :reboot, roles: [:app] do
  bundle "sidekiq"
  bundle "prometheus_exporter -b 0.0.0.0"
  bundle "puma -C /home/ubuntu/IRM/shared/puma.rb"
  command 'sudo docker run -d --rm --name xirr_py -p 8000:80 -v /tmp:/tmp thimmaiah/xirr_py:v2.4'
  command 'sudo docker run -d --rm --name=node-exporter -p 9100:9100  prom/node-exporter'
end

# Reboot servers, but first run logrotate
every :saturday, at: '00:50 am', roles: [:app] do
  command "logrotate /home/ubuntu/IRM/shared/log/logrotate.conf --state /home/ubuntu/IRM/shared/log/logrotate.state --verbose"
end
every :saturday, at: '1:00 am', roles: [:app] do
  # This time is in UTC 2am IST is 9pm UTC
  command 'sudo reboot'
end
