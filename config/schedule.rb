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
  # sidekiq is deliberately NOT started here either — the sidekiq_IRM_<stage>
  # systemd unit is enabled and starts it on boot. This line used to launch a
  # second, unsupervised Sidekiq alongside monit's, one of the duplicate-worker
  # sources described in config/deploy/services/sidekiq_IRM_env.service.erb.
  bundle "prometheus_exporter -b 0.0.0.0"
  # puma is deliberately NOT started here — it's already managed by the
  # puma_IRM_<stage> systemd unit (WantedBy=multi-user.target starts it on
  # boot on its own). Starting it a second time here raced systemd for the
  # shared unix socket: whichever `current` release the box's FIRST boot
  # happened to be symlinked to won the socket permanently, and every later
  # `systemctl restart puma_IRM_<stage>` from any subsequent deploy
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
  # 01:00 UTC Saturday (server clocks are UTC): 6:30am IST; Friday 9pm EDT /
  # 8pm EST in the US. Puma and sidekiq come back on their own — both systemd
  # units are enabled — and the reboot stops sidekiq through its unit, so
  # in-flight jobs drain before shutdown. See docs/technical/process_supervision.md.
  command 'sudo reboot'
end

# Weekly maintenance window, anchored to 3:00 AM LOCAL time in each region —
# NOT a shared UTC time. Server clocks are UTC everywhere regardless of
# region (see sidekiq_restart_at above), so "3am" has to be computed per
# env_variant the same way:
#   in -> IST is UTC+5:30 year-round -> 3:00am IST = 9:30pm UTC the day before
#   us -> US Eastern has DST the server clock can't track; 7:30am UTC splits
#         the difference between EDT (3:30am) and EST (2:30am) year-round
# The bake/purge/cleanup jobs below keep the same 1h/2h gaps after the bake
# as before (see the retention-sweep comment), just anchored here instead of
# a flat 2am UTC that happened to land at 7:30am IST — mid-morning in India.
maintenance_bake_at, maintenance_purge_at, maintenance_cleanup_at =
  if env_variant == 'us'
    ['7:30 am', '8:30 am', '9:30 am']
  else
    ['9:30 pm', '10:30 pm', '11:30 pm']
  end

every 1.week, at: maintenance_bake_at, roles: [:primary] do
  # Ensure AMIs are created and backed up
  rake '"aws:create_and_copy_ami[AppServer]"'
  rake '"aws:create_and_copy_ami[DB-Redis-ES]"'
  rake '"aws:create_and_copy_ami[Observability]"'
end

# Binary log retention on the primary, 1h after the bake starts. Renders
# identically on every stage (staging + production, both regions) since this
# file is shared — the task itself no-ops outside Rails.env.production?, same
# as website_leads:purge below no-ops when there's nothing due. See
# lib/tasks/db_log_cleanup.rake.
every 1.week, at: maintenance_purge_at, roles: [:primary] do
  rake "db:purge_binlogs"
end

# Retention sweep AFTER the bake above has finished (the bake's cross-region
# copy waiter can run ~40 min, so a 2h gap leaves headroom). cleanup_amis
# inside create_and_copy_ami deregisters old AMIs but never deleted their
# backing snapshots — this task deletes those AND mops up the years of
# orphaned snapshots already accumulated. EXECUTE=1 because aws:ebs_* tasks
# are dry-run by default; regions come from the box's own
# AWS_REGION/AWS_BACKUP_REGION.
every 1.week, at: maintenance_cleanup_at, roles: [:primary] do
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

# ReportBuilderSchedulerJob and website_leads:purge used to run from here
# (hourly `runner`, daily `rake`) — both moved into sidekiq-cron
# (config/initializers/sidekiq.rb) so they run inside the already-running
# Sidekiq process instead of forking a fresh Rails boot on every tick. See
# WebsiteLeadPurgeJob and the ReportBuilderSchedulerJob registration there.

# Restart Sidekiq daily at ~7:20am local time to shed accumulated memory.
# Through systemd: the old `pkill -9` + relaunch here dropped in-flight jobs,
# and its async `monit unmonitor`/`monitor` pair could leave monit starting a
# second copy. `systemctl restart` drains jobs first and waits for the new
# worker to be ready — bounded by `timeout`, because with Restart=always a
# Sidekiq that crash-loops on boot would otherwise leave this job hanging.
# Server clocks are UTC regardless of region:
#   in -> IST is UTC+5:30 year-round -> 7:20am IST = 1:50am UTC
#   us -> US Eastern has DST the server clock can't track; 11:50am UTC splits
#         the difference between EDT (7:50am) and EST (6:50am) year-round
sidekiq_restart_at = env_variant == 'us' ? '11:50 am' : '1:50 am'

every 1.day, at: sidekiq_restart_at, roles: [:app] do
  command "(date; sudo /usr/bin/timeout 900 /usr/bin/systemctl restart sidekiq_IRM_#{environment} && echo restarted || echo 'restart failed or timed out') >> /home/ubuntu/sidekiq_restart.log 2>&1"
end
