# Learn more: http://github.com/javan/whenever
# env 'MAILTO', 'support@caphive.com'

set :path, "/home/ubuntu/IRM/current"

# Default region variant. Capistrano passes the real value through whenever's
# --set (see :whenever_variables in config/deploy.rb); those pre-set variables
# take precedence over `set`, so this only applies when schedule.rb is rendered
# without deploy context (e.g. a bare `whenever` run, or the Cucumber scenario
# in features/core/report_builder/scheduling.feature).
set :env_variant, "in"
job_type :bundle, 'cd :path && :environment_variable=:environment bundle exec :task'

every :reboot, roles: [:app] do
  bundle "sidekiq"
  bundle "prometheus_exporter -b 0.0.0.0"
  # puma is deliberately NOT started here — it's already managed by the
  # puma_IRM_staging systemd unit (WantedBy=multi-user.target starts it on
  # boot on its own). Starting it a second time here raced systemd for the
  # shared unix socket: whichever `current` release the box's FIRST boot
  # happened to be symlinked to won the socket permanently, and every later
  # `systemctl restart puma_IRM_staging` from any subsequent deploy
  # crash-looped against the already-bound socket instead of replacing it —
  # so the app kept serving off a release that could be arbitrarily old
  # (found live during a DR drill: puma was still serving a release from a
  # week earlier, with a DB_HOST from an even older restore, causing every
  # DB/Redis/ES-backed health check to fail against a dead IP).
  command 'sudo docker run -d --rm --name xirr_py -p 8000:80 -v /tmp:/tmp thimmaiah/xirr_py:v2.6'
  # node_exporter runs natively via systemd (node_exporter.service) on app servers, not Docker —
  # a Dockerized node-exporter only ever sees its own container's mount namespace (Docker always
  # populates just /etc/hostname, /etc/hosts, /etc/resolv.conf), so disk/inode metrics silently
  # reported nothing for the host. The native systemd service is enabled and survives reboot on
  # its own; nothing needs to be (re)started here.
end

# Reboot servers, but first run logrotate
every :saturday, at: '00:50 am', roles: [:app] do
  command "logrotate /home/ubuntu/IRM/shared/log/logrotate.conf --state /home/ubuntu/IRM/shared/log/logrotate.state --verbose"
end
every :saturday, at: '1:00 am', roles: [:app] do
  # This time is in UTC 2am IST is 9pm UTC
  command 'sudo reboot'
end

every 1.week, at: '02:00 am', roles: [:primary] do
  # Ensure AMIs are created and backed up
  rake '"aws:create_and_copy_ami[AppServer]"'
  rake '"aws:create_and_copy_ami[DB-Redis-ES]"'
  rake '"aws:create_and_copy_ami[Observability]"'
end

# Retention sweep AFTER the bake above has finished (the bake's cross-region
# copy waiter can run ~40 min, so 4am leaves headroom). cleanup_amis inside
# create_and_copy_ami deregisters old AMIs but never deleted their backing
# snapshots — this task deletes those AND mops up the years of orphaned
# snapshots already accumulated. EXECUTE=1 because aws:ebs_* tasks are
# dry-run by default; regions come from the box's own AWS_REGION/AWS_BACKUP_REGION.
every 1.week, at: '04:00 am', roles: [:primary] do
  # Log what an unattended EXECUTE=1 deletion sweep actually did (or failed to
  # do — act() prints-and-continues on AWS errors) — with MAILTO off, no
  # :output would mean silent, invisible deletions.
  rake '"aws:ebs_cleanup" EXECUTE=1', output: '/home/ubuntu/IRM/shared/log/ebs_cleanup.log'
end

# This is to ensure next year's partition exists for account_entries table
every 1.year, at: 'December 15 02:00am', roles: [:primary] do
  rake "partitions:ensure_account_entries"
end
# This is idempotent, so just run it again to ensure
every 1.year, at: 'December 15 03:00am', roles: [:primary] do
  rake "partitions:ensure_account_entries"
end

# Runs every hour; ReportBuilderSchedulerJob itself decides which ReportSchedules are due
every 1.hour, roles: [:primary] do
  runner "ReportBuilderSchedulerJob.perform_later"
end

# Enforces the WebsiteLead retention windows published in the website's privacy
# policy: visitor IP and user-agent are nulled after 90 days, whole leads deleted
# after 24 months. Idempotent, so a missed night costs nothing but a day.
every 1.day, at: '2:30 am', roles: [:primary] do
  rake "website_leads:purge"
end

# Force-restart Sidekiq daily at ~7:20am local time. Works around a build-up
# (stuck/leaked workers) that a plain `monit restart` alone doesn't clear.
# Server clocks are UTC regardless of region:
#   in -> IST is UTC+5:30 year-round -> 7:20am IST = 1:50am UTC
#   us -> US Eastern has DST the server clock can't track; 11:50am UTC splits
#         the difference between EDT (7:50am) and EST (6:50am) year-round
sidekiq_restart_at = env_variant == 'us' ? '11:50 am' : '1:50 am'

every 1.day, at: sidekiq_restart_at, roles: [:app] do
  command "(sudo /usr/bin/monit unmonitor sidekiq_IRM_#{environment}; pkill -9 -f '^sidekiq [0-9]'; sleep 2; cd /home/ubuntu/IRM/current && MALLOC_ARENA_MAX=2 ~/.rvm/bin/rvm default do bundle exec sidekiq -e #{environment}     >> /home/ubuntu/IRM/shared/log/sidekiq.log 2>&1 & sleep 2; sudo /usr/bin/monit monitor sidekiq_IRM_#{environment}) >> /home/ubuntu/sidekiq_restart.log 2>&1"
end
