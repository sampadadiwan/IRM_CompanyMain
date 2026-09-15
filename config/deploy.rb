# config/deploy.rb
set :rails_env, fetch(:stage)

# DR/drill deploys happen BEFORE the database restore, so capistrano-rails'
# deploy-time migrate is meaningless there — and destructive on fresh Packer
# AMIs, which ship a VIRGIN MySQL: migrate auto-creates an empty IRM_<env> and
# dies replaying 4 years of migrations against no schema. (Old snapshot-based
# AMIs only "worked" because they carried a stale populated datadir.)
# aws:setup_infra passes SKIP_MIGRATE=true and replays real migrations AFTER
# the restore via recovery:migrate. Normal deploys are unaffected.
Rake::Task["deploy:migrate"].clear_actions if ENV["SKIP_MIGRATE"] == "true"

set :application, "IRM"
set :repo_url, "git@github.com:ausangshukla/IRM.git"
set :branch, ENV["branch"] || 'main'
set :whenever_roles, :all
# Pass env_variant (in/us) through to schedule.rb, alongside whenever's own
# `environment` var, so region-specific timing (e.g. IST vs US local time)
# can be computed there. Server clocks are always UTC regardless of region.
set :whenever_variables, -> { "'environment=#{fetch(:whenever_environment)}&env_variant=#{fetch(:env_variant)}'" }

set :deploy_to, "/home/ubuntu/IRM"
set :ssh_options, forward_agent: true
if fetch(:stage) == :production

end

# Default value for :pty is false
set :pty, true

# Default value for linked_dirs is []
append :linked_dirs, "log", "tmp/pids", "tmp/cache", "tmp/sockets", "public/system", '.bundle'

set :bundle_binstubs, -> { shared_path.join('bin') }
# Bundler dropped `bundle install --binstubs` (removed in favor of a separate
# `bundle binstubs --all`); capistrano-bundler 2.2.0 supports the new form via
# this setting instead of the (default) :install mode.
set :bundle_binstubs_command, :binstubs
set :bundle_jobs, 8

# Default value for keep_releases is 5
if fetch(:stage) == :production
  set :keep_releases, 3
else
  set :keep_releases, 1
end
# Uncomment the following to require manually verifying the host key before first deploy.
# set :ssh_options, verify_host_key: :secure

set :puma_bind,       "unix://#{shared_path}/tmp/sockets/#{fetch(:application)}-puma.sock"
set :puma_state,      "#{shared_path}/tmp/pids/puma.state"
set :puma_pid,        "#{shared_path}/tmp/pids/puma.pid"
set :puma_access_log, "#{release_path}/log/puma.error.log"
set :puma_error_log,  "#{release_path}/log/puma.access.log"
set :puma_threads, [0,16]
set :puma_restart_command, "bundle exec pumactl -S #{fetch(:puma_state)} restart"
set :puma_preload_app, true
set :puma_worker_timeout, nil
set :puma_workers, 4
set :puma_daemonize, true
set :puma_init_active_record, true


set :puma_systemctl_user, :system
set :skip_notification, ENV['SKIP_NOTIFICATION'] == 'true'
set :puma_service_unit_name, -> { "puma_#{fetch(:application)}_#{fetch(:rails_env)}" }

# Sidekiq runs as a systemd unit (config/deploy/services/sidekiq_IRM_env.service.erb),
# the only thing that starts or stops it. It used to be monit plus two cron
# entries plus Capistrano, each finding "the" Sidekiq by regex — see the unit
# template for how that left duplicate workers behind after deploys.
set :sidekiq_service_unit_name, -> { "sidekiq_#{fetch(:application)}_#{fetch(:rails_env)}" }

namespace :deploy do
  task :notify_before do
    on roles(:app) do
      within release_path do
        with rails_env: fetch(:rails_env) do
          execute :rake, "deploy:notify_before"
        end
      end
    end
  end

  task :notify_after do
    on roles(:app) do
      within release_path do
        with rails_env: fetch(:rails_env) do
          execute :rake, "deploy:notify_after"
        end
      end
    end
  end

  before 'deploy:starting', 'deploy:notify_before' unless fetch(:skip_notification, false)
  after 'deploy:finished', 'deploy:notify_after' unless fetch(:skip_notification, false)

  desc "Uploads .env remote servers."
  task :ensure_rails_credentials do
    on roles(:app) do
      # This is stored in /etc/environments when the AMI is built
      execute "echo $RAILS_MASTER_KEY > #{release_path}/config/credentials/#{fetch(:stage)}.key"
    end
  end

  task :cleanup do
    on roles(:app) do
      within release_path do
        # rm /home/ubuntu/IRM/current/tmp/db_backup_xtra_#{Rails.env}.sh only if it exists
        if test("[ -f #{shared_path}/tmp/db_backup_xtra_#{fetch(:stage)}.sh ]")
          execute :rm, "-f", "#{shared_path}/tmp/db_backup_xtra_#{fetch(:stage)}.sh"
        else
          info "File #{shared_path}/tmp/db_backup_xtra_#{fetch(:stage)}.sh does not exist, skipping removal."
        end
      end
    end
  end

  desc "Ensure permissions are set for nginx and puma"
  task :ensure_permissions do
    on roles(:app) do
      # Change the ownership of the logs to ubuntu
      execute :sudo, :chown, "-R", "ubuntu", "/home/ubuntu/IRM/current/log/*"
      # Check if the log files exist
      if test("[ -f /home/ubuntu/IRM/current/log/nginx* ]")
        # If the files exist, run the chown command
        execute :sudo, :chown, "-R", "www-data", "/home/ubuntu/IRM/current/log/nginx*"
      else
        info "Nginx log files do not exist, skipping chown step."
      end
      # sudo usermod -aG ubuntu www-data
      execute :sudo, :usermod, "-aG", "ubuntu", "www-data"
      # sudo chmod 660 /home/ubuntu/IRM/shared/tmp/sockets/IRM-puma.sock
      execute :sudo, :chmod, "660", "/home/ubuntu/IRM/shared/tmp/sockets/IRM-puma.sock"
      # restart nginx
      execute :sudo, "service nginx restart"
    end
  end

  # Sidekiq's deploy wiring. It must hang off a deploy:* stage — nginx:switch_app
  # is NOT part of the normal deploy flow (only the DR path and manual runs invoke
  # it). deploy:published is the first stage where the `current` symlink points
  # at the new release, which is what the restart has to verify against;
  # deploy:cleanup runs later, so the outgoing release still exists while the old
  # worker drains. The unit file is (re)installed first so a template change is
  # brought in line by a plain deploy.
  after 'deploy:published', 'sidekiq:install_service'
  after 'deploy:published', 'sidekiq:ensure_clean_restart'

  # Before publishing, so monit is gone — and any puma it launched is off the
  # socket — before capistrano3-puma's `after deploy:published ->
  # puma:smart_restart` and the sidekiq restart above, which then start the
  # systemd units onto the new release.
  before 'deploy:publishing', 'monit:retire'

  before 'deploy:updated', 'IRM:set_rails_master_key'
  # before "deploy:updated", :ensure_rails_credentials
  after  'deploy:finished', :ensure_permissions
end

namespace :puma do
  desc 'Create Directories for Puma Pids and Socket'
  task :make_dirs do
    on roles(:app) do
      execute "mkdir #{shared_path}/tmp/sockets -p"
      execute "mkdir #{shared_path}/tmp/pids -p"
    end
  end

  desc 'Restart puma via systemd, clearing the socket unconditionally first'
  task :ensure_clean_restart do
    on roles(:app) do
      unit = fetch(:puma_service_unit_name)
      socket_path = fetch(:puma_bind).sub('unix://', '')

      # fuser -k kills EVERY process holding the socket, no exceptions —
      # including the systemd unit's own current workers, which is fine
      # because systemctl restart (next line) replaces them seconds later
      # regardless. This sidesteps needing to tell "systemd's own worker"
      # apart from "some other launcher" at all: a stray non-systemd
      # launcher (the old @reboot cron entry, now removed) used to win the
      # socket permanently because `systemctl restart` only has authority
      # over processes it started itself, so it couldn't touch a rogue
      # holder — this just clears the socket outright before restarting.
      # `|| true`: fuser exits non-zero when nothing was holding it, which
      # is the common case and not an error.
      execute "sudo fuser -k #{socket_path} 2>/dev/null || true"
      execute :sudo, "systemctl restart #{unit}"
    end
  end
end

namespace :sidekiq do
  # Matches a process that IS a Sidekiq at every stage of its life, and nothing
  # that merely mentions it (`tail -f sidekiq.log`, `grep sidekiq`):
  #   ^sidekiq       booted — "sidekiq 8.1.7 IRM [0 of 7 busy]"
  #   bin/sidekiq    booting — Bundler's title "…/bin/sidekiq -e production"
  #   exec sidekiq   launchers — "bash …/rvm default do bundle exec sidekiq -e …",
  #                  "ruby …/bin/bundle exec sidekiq …", and the su/cron/cap shells
  #                  the old monit/cron/Capistrano launchers left behind
  # The old stop script and deploy check matched only the first form, so a copy
  # that was still booting survived the stop and was not counted — that is how
  # duplicate workers got past every deploy. The [s] brackets stop the pattern
  # matching the shell running pgrep, whose command line contains it literally.
  def sidekiq_process_pattern
    '^[s]idekiq |bin/[s]idekiq( |$)|exec [s]idekiq( |$)'
  end

  def sidekiq_pids
    capture("pgrep -f '#{sidekiq_process_pattern}' || true").split.grep(/\A\d+\z/)
  end

  # Kills every Sidekiq on the box. Only called while the unit is stopped, so
  # anything found was started by something other than systemd: a box still on
  # the old monit/cron launchers (first deploy after this change), or a launcher
  # nobody knew about. Warned loudly, because each one is a duplicate worker that
  # would otherwise have run unnoticed.
  def kill_stray_sidekiqs(unit)
    strays = sidekiq_pids
    return if strays.empty?

    listing = capture("ps -o pid=,lstart=,args= -p #{strays.join(',')} || true")
    warn "sidekiq: #{strays.size} process(es) running outside #{unit} — stopping them:\n#{listing}"

    # TERM gives in-flight jobs Sidekiq's 25s shutdown and requeues the rest.
    # sudo because a stray is not guaranteed to be ubuntu's. `|| true`: some pids
    # (e.g. a launcher shell) exit on their own once their child dies.
    execute "sudo kill -TERM #{strays.join(' ')} 2>/dev/null || true"
    40.times do
      break if sidekiq_pids.empty?

      sleep 1
    end

    remaining = sidekiq_pids
    unless remaining.empty?
      warn "sidekiq: still alive after 40s, SIGKILL to #{remaining.join(' ')}"
      execute "sudo kill -KILL #{remaining.join(' ')} 2>/dev/null || true"
      sleep 2
    end

    remaining = sidekiq_pids
    raise "sidekiq: could not kill stray processes #{remaining.join(', ')}" unless remaining.empty?
  end

  # Proves the unit is the only Sidekiq on the box and runs the new release.
  # Every Sidekiq process (launcher shells included) must sit in the unit's
  # cgroup — /proc/<pid>/cgroup names "/<unit>.service" on cgroup v1 and v2 —
  # and there must be exactly one ruby, whose cwd is the current release. Ruby
  # resolves `current` to a physical path at boot, so a worker left on an older
  # (often deleted) release reports that path instead.
  def verify_single_sidekiq(unit)
    release = capture(:readlink, '-f', current_path).strip
    probe = "for p in $(pgrep -f '#{sidekiq_process_pattern}' || true); do " \
            "echo \"$p $(grep -qs '/#{unit}.service' /proc/$p/cgroup && echo unit || echo stray) " \
            "$(readlink /proc/$p/exe 2>/dev/null || echo UNKNOWN) $(readlink /proc/$p/cwd 2>/dev/null || echo UNKNOWN)\"; done"
    # cwd is last and split with a limit: readlink reports a removed directory as
    # "/path/to/release (deleted)", which never compares equal to the live release.
    procs = capture(probe).lines.map(&:strip).grep(/\A\d+ /).map { |line| line.split(' ', 4) }

    raise "sidekiq: #{unit} reported ready but no sidekiq process was found" if procs.empty?

    strays = procs.reject { |(_pid, owner, _exe, _cwd)| owner == 'unit' }
    unless strays.empty?
      raise "sidekiq: processes running outside #{unit}: " \
            "#{strays.map { |(pid, _o, exe, cwd)| "pid #{pid} exe=#{exe} cwd=#{cwd}" }.join(', ')}"
    end

    workers = procs.select { |(_pid, _owner, exe, _cwd)| File.basename(exe).start_with?('ruby') }
    unless workers.size == 1
      raise "sidekiq: expected 1 worker in #{unit}, found #{workers.size} " \
            "(#{procs.map { |(pid, _o, exe, _cwd)| "pid #{pid} #{exe}" }.join(', ')})"
    end

    worker_pid, _owner, _exe, cwd = workers.first
    raise "sidekiq: worker is running #{cwd}, not the current release #{release}" unless cwd == release

    # KillMode=mixed sends the stop SIGTERM to the main PID alone. If that is not
    # the worker (ExecStart's exec chain forked somewhere), every stop would
    # SIGTERM a wrapper, skip Sidekiq's drain and SIGKILL in-flight jobs.
    main_pid = capture(:systemctl, 'show', unit, '-p', 'MainPID', '--value', '--no-pager').strip
    unless main_pid == worker_pid
      raise "sidekiq: systemd's MainPID for #{unit} is #{main_pid}, not the worker #{worker_pid} — " \
            'stops would not drain jobs; ExecStart must exec down to ruby without forking'
    end

    info "sidekiq: 1 worker (pid #{worker_pid}) is #{unit}'s main process, running #{release}"
  end

  # Waits for the unit to turn active (Sidekiq has booted and sent READY), and
  # fails fast when it cannot. Polled instead of a blocking `systemctl start`:
  # with Restart=always and no start limit, a Sidekiq that crashes during boot
  # (bad credentials, unreachable Redis) keeps systemd's start job open across
  # endless auto-restarts, so a blocking start would hang the deploy forever.
  # NRestarts going up is that crash loop; the first read is the baseline.
  def wait_for_sidekiq_ready(unit, timeout: 600)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    baseline = nil
    loop do
      state = capture("systemctl is-active #{unit} || true").strip
      return if state == 'active'

      restarts = capture(:systemctl, 'show', unit, '-p', 'NRestarts', '--value', '--no-pager').strip.to_i
      baseline ||= restarts
      problem =
        if state == 'failed' then 'failed to start'
        elsif restarts > baseline then 'crashed while booting and systemd is restarting it'
        elsif Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline then "was not ready after #{timeout}s"
        end

      if problem
        error capture("sudo systemctl status #{unit} --no-pager --lines=0 || true")
        error capture("tail -n 40 #{shared_path}/log/sidekiq.log || true")
        raise "sidekiq: #{unit} #{problem} — see #{shared_path}/log/sidekiq.log. systemd keeps retrying; " \
              "`sudo systemctl stop #{unit}` halts it"
      end

      sleep 5
    end
  end

  desc 'Install or refresh the sidekiq systemd unit'
  task :install_service do
    on roles(:app) do
      unit      = fetch(:sidekiq_service_unit_name)
      unit_path = "/etc/systemd/system/#{unit}.service"
      tmp_path  = "/tmp/#{unit}.service"

      rendered = ERB.new(File.read('./config/deploy/services/sidekiq_IRM_env.service.erb')).result(binding)
      upload! StringIO.new(rendered), tmp_path
      if test(:cmp, '-s', tmp_path, unit_path)
        execute :rm, '-f', tmp_path
      else
        execute :sudo, :mv, tmp_path, unit_path
        execute :sudo, :chown, 'root:root', unit_path
        execute :sudo, :chmod, '644', unit_path
        execute :sudo, :systemctl, 'daemon-reload'
        info "sidekiq: installed #{unit_path}"
      end
      # Boot-time start. This replaces the @reboot cron entry that used to launch
      # a second, unsupervised Sidekiq alongside monit's.
      execute :sudo, :systemctl, :enable, '--quiet', unit

      # Leftover from the monit era; monit itself is switched off by monit:retire,
      # which runs before this in a deploy.
      execute :rm, '-f', "#{shared_path}/bin/sidekiq_stop.sh"
    end
  end

  desc 'Stop sidekiq via systemd (waits for in-flight jobs to drain)'
  task :stop do
    on roles(:app) do
      unit = fetch(:sidekiq_service_unit_name)
      if test("[ -f /etc/systemd/system/#{unit}.service ]")
        execute :sudo, :systemctl, :stop, unit
      else
        # A box not yet deployed since the move to systemd (e.g. the other region
        # during maintenance). Stop monit relaunching it, then stop it directly —
        # aborting here would leave the old worker running mid-maintenance.
        warn "sidekiq: #{unit}.service is not installed on this box; stopping the monit-era sidekiq directly"
        execute "sudo monit unmonitor sidekiq_IRM_#{fetch(:stage)} >/dev/null 2>&1 || true"
        kill_stray_sidekiqs(unit)
      end
    end
  end

  desc 'Restart sidekiq via systemd, clear out any sidekiq systemd does not own, and prove exactly one worker runs the current release'
  task :ensure_clean_restart do
    on roles(:app) do
      unit = fetch(:sidekiq_service_unit_name)

      installed = test("[ -f /etc/systemd/system/#{unit}.service ]")
      raise "sidekiq: #{unit}.service is not installed — run `bundle exec cap #{fetch(:stage)}_#{fetch(:env_variant)} sidekiq:install_service`" unless installed

      # stop + start rather than `restart`, so the stray sweep runs while no
      # legitimate worker exists and anything it finds is by definition not ours.
      # stop is synchronous: it returns once the unit's cgroup is empty (drained,
      # or SIGKILLed at TimeoutStopSec). start is fired without blocking and
      # awaited by wait_for_sidekiq_ready, which can fail instead of hanging.
      execute :sudo, :systemctl, :stop, unit
      kill_stray_sidekiqs(unit)

      execute :sudo, :systemctl, :start, '--no-block', unit

      # --dry-run swaps in SSHKit's Printer backend, which returns "" from every
      # capture, so there is nothing real to wait for or verify.
      if fetch(:sshkit_backend) == SSHKit::Backend::Printer
        info 'dry run: skipping sidekiq readiness wait and worker verification'
        next
      end

      wait_for_sidekiq_ready(unit)
      verify_single_sidekiq(unit)
    end
  end

  desc 'Alias for sidekiq:ensure_clean_restart'
  task :restart do
    invoke 'sidekiq:ensure_clean_restart'
  end
end

# monit used to supervise puma and sidekiq alongside systemd — two supervisors
# each able to launch its own copy, which is how duplicate sidekiq workers
# survived deploys (config/deploy/services/sidekiq_IRM_env.service.erb). systemd
# now runs both, so monit has nothing left to do. AMIs baked before this change
# still ship it enabled, which is why every deploy (and IRM:setup) runs this.
namespace :monit do
  # Kills every process holding puma's socket that is not in puma's systemd unit.
  # monit launched puma with `sudo -iu ubuntu`, and pam_systemd moves a `sudo -i`
  # (or `su -`) login into its own session scope — so a monit-started puma is NOT
  # in monit.service's cgroup and survives monit being stopped. One exists on any
  # box where monit relaunched puma after a maintenance window's puma:stop. It
  # would keep the socket and serve the old release while the systemd puma
  # crash-loops unable to bind, and puma:smart_restart (a plain `systemctl
  # restart`) has no authority over it. Workers inherit the socket, so they are
  # found and killed along with their master.
  def kill_stray_pumas(unit)
    socket = fetch(:puma_bind).sub('unix://', '')
    probe  = "for p in $(sudo fuser #{socket} 2>/dev/null); do " \
             "grep -qs '/#{unit}.service' /proc/${p%%[a-zA-Z]*}/cgroup || echo ${p%%[a-zA-Z]*}; done"
    strays = -> { capture(probe).split.grep(/\A\d+\z/).uniq }

    pids = strays.call
    return if pids.empty?

    listing = capture("ps -o pid=,lstart=,args= -p #{pids.join(',')} || true")
    warn "monit: #{pids.size} puma process(es) outside #{unit} hold #{socket} — stopping them:\n#{listing}"
    # TERM first so a stray master finishes in-flight requests; it exits well
    # inside 30s unless wedged.
    execute "sudo kill -TERM #{pids.join(' ')} 2>/dev/null || true"
    30.times do
      break if strays.call.empty?

      sleep 1
    end

    remaining = strays.call
    return if remaining.empty?

    warn "monit: stray puma still alive after 30s, SIGKILL to #{remaining.join(' ')}"
    execute "sudo kill -KILL #{remaining.join(' ')} 2>/dev/null || true"
  end

  desc 'Stop and disable monit and remove its configs; systemd supervises puma and sidekiq'
  task :retire do
    on roles(:app, :web) do
      next unless test('systemctl --no-pager cat monit.service >/dev/null 2>&1')

      # On a box where puma has no systemd unit, monit is the only thing keeping
      # puma up, and stopping it would take the site down with nothing to bring
      # it back. Refuse rather than guess.
      puma_unit = fetch(:puma_service_unit_name)
      unless test("[ -f /etc/systemd/system/#{puma_unit}.service ]")
        raise "monit: #{puma_unit}.service is not installed, so monit may be puma's only supervisor here — " \
              "run `bundle exec cap #{fetch(:stage)}_#{fetch(:env_variant)} IRM:setup` first"
      end

      # Boot-time start for puma no longer has monit as a fallback.
      execute :sudo, :systemctl, :enable, '--quiet', puma_unit

      if test('systemctl is-enabled --quiet monit') || test('systemctl is-active --quiet monit')
        # --now stops synchronously, so monit cannot relaunch anything after the
        # sweep below. It does NOT take monit's launches with it: those ran under
        # `sudo -i`/`su -` and live in session scopes outside monit.service.
        execute :sudo, :systemctl, :disable, '--now', '--quiet', 'monit'
        info 'monit: stopped and disabled'
      end

      # A monit-launched puma survives the stop above; clear it so the systemd
      # unit can own the socket. (A monit-launched sidekiq is cleared by
      # sidekiq:ensure_clean_restart's stray sweep.)
      kill_stray_pumas(puma_unit)

      # Disabled rather than purged: apt-get would contend for the dpkg lock with
      # unattended-upgrades, and a disabled unit stays down across package
      # upgrades. The configs go so re-enabling monit by hand cannot resurrect
      # the old checks.
      execute :sudo, :rm, '-f', "/etc/monit/conf.d/puma_IRM_#{fetch(:stage)}.conf",
              "/etc/monit/conf.d/sidekiq_IRM_#{fetch(:stage)}.conf"
      if test('[ -d /etc/systemd/system/monit.service.d ]')
        # The drop-in that un-sandboxed monit so it could su/sudo to ubuntu.
        execute :sudo, :rm, '-rf', '/etc/systemd/system/monit.service.d'
        execute :sudo, :systemctl, 'daemon-reload'
      end
    end
  end
end

namespace :nginx do
  desc 'Switch nginx configuration to maintenance or IRM_production'
  task :switch_maintenance do
    on roles(:app) do

      # Copy the maintenance page to /etc/nginx/sites-available/maintenance
      within release_path do
        execute :sudo, :cp, "config/deploy/templates/maintenance", "/etc/nginx/sites-available/maintenance"
        execute :rake, "\"nginx:switch[maintenance]\" RAILS_ENV=#{fetch(:stage)}"
      end
    end
  end

  # systemctl stop is synchronous and, unlike the old monit stop, nothing else
  # will relaunch sidekiq behind it while the site is in maintenance.
  before 'nginx:switch_maintenance', 'sidekiq:stop'
  before 'nginx:switch_maintenance', 'puma:stop'

  task :switch_app do
    on roles(:app) do
      within release_path do
        execute :rake, "\"nginx:switch[IRM_#{fetch(:stage)}]\" RAILS_ENV=#{fetch(:stage)}"
      end
    end
  end

  after 'nginx:switch_app', 'sidekiq:ensure_clean_restart'
  after 'nginx:switch_app', 'puma:ensure_clean_restart'

  desc 'Render and install ONLY the nginx config, then validate and reload'
  task :update do
    on roles(:app) do
      # IRM:setup also re-uploads puma/systemd configs. When the only
      # change is nginx_conf.erb (e.g. adding the
      # website vhosts), this task touches nothing else.
      nginx_config_path = "/etc/nginx/sites-available"
      site_name = "IRM_#{fetch(:stage)}"
      tmp_path = "/tmp/#{site_name}"

      config = ERB.new(File.read('./config/deploy/templates/nginx_conf.erb')).result(binding)

      # Surface what is being installed — the vhosts are the whole point of
      # this task, so a silent upload would hide a mis-rendered template.
      config.scan(/^\s*server_name\s+(.+);/).flatten.each do |names|
        info "  vhost: #{names}"
      end

      upload! StringIO.new(config), tmp_path
      execute :sudo, :mv, tmp_path, "#{nginx_config_path}/#{site_name}"

      # Idempotent: "|| true" keeps a pre-existing symlink from failing the run.
      execute :sudo, "ln -s #{nginx_config_path}/#{site_name} /etc/nginx/sites-enabled/#{site_name} || true"

      # nginx -t before reload. execute raises on a non-zero exit, so a bad
      # config aborts here and the running server keeps its old config.
      execute :sudo, "nginx -t"
      execute :sudo, "nginx -s reload"
      info "nginx reloaded with the new configuration"
    end
  end
end

# These recovery tasks are to be invoked ONLY if you are rebuilding an environment from scratch
# For example, if you are setting up a new environment or if you are recovering from a disaster
# This is not to be used for regular deployments
# Prerequisites:
# 1. The DB backups should be available in the S3 bucket
namespace :recovery do
  desc 'Setup the DB and the Replica from the latest backup'
  task :load_db_from_backups do
    on roles(:primary), in: :sequence, wait: 5 do
      within release_path do
        # DR path: run the BAKED script on the DB boxes over SSH (app server →
        # private DB IP). The old db:restore_primary_db/replica_db route went
        # through DbRestoreService, which is a backup VERIFIER (DbCheckInstance)
        # and drags script generation + IAM + service-cleanup into DR.
        # restore_all_remote runs primary + replica IN PARALLEL (halving the
        # longest DR phase), then resets replication once both are up —
        # output is [primary]/[replica]-prefixed. Single-box manual forms
        # remain: db:restore_primary_remote / db:restore_replica_remote.
        execute :rake, "db:restore_all_remote RAILS_ENV=#{fetch(:stage)}"
      end
    end
  end

  task :restore_replica_db do
    on roles(:primary), in: :sequence, wait: 5 do
      within release_path do
        execute :rake, "db:restore_replica_db RAILS_ENV=#{fetch(:stage)}"
      end
    end
  end

  # Replays any migrations newer than the restored backup. Run after
  # load_db_from_backups and BEFORE nginx:switch_app — a backup taken before
  # the last deploy is missing those migrations, and serving traffic on a
  # stale schema is the failure mode this closes.
  desc 'Run pending migrations against the restored DB (after load_db_from_backups)'
  task :migrate do
    on roles(:primary), in: :sequence do
      within release_path do
        execute :rake, "db:migrate RAILS_ENV=#{fetch(:stage)}"
      end
    end
  end

  task :delete_old_assets do
    on roles(:app) do |_host|
      execute :rm, '-rf', '/home/ubuntu/IRM/shared/releases/* || true'
      execute :rm, '-rf', '/home/ubuntu/IRM/shared/tmp/cache/assets/* || true'
    end
  end

  # Post-recovery smoke test (lib/tasks/dr_verify.rake): proves each app server
  # is SERVING (nginx/puma/sidekiq) and can reach MySQL/Redis/ES/S3, and that
  # the DB-box daemons are up, backups are armed on the primary and replication
  # flows. aws:setup_infra runs this as its FINAL step, so a DR run or drill
  # only succeeds if the stack verifies — "deployed but dead" fails loudly.
  # Also safe standalone after any deploy:
  #   LB=true bundle exec cap staging_in recovery:verify
  desc 'Smoke-test every app server + DB boxes; fails the run if anything is down'
  task :verify do
    on roles(:app), in: :sequence do
      within release_path do
        # dr:verify exits non-zero on any ❌, which makes execute raise here
        execute :rake, "dr:verify RAILS_ENV=#{fetch(:stage)}"
      end
    end
  end


end


namespace :env do
  task :point_envfile do
    on roles(:app) do

      # Link the .env file in the release to the correct regional file from the repo
      execute :ln, "-nfs",
        "#{release_path}/.env.#{fetch(:rails_env)}.#{fetch(:env_variant)}",
        "#{release_path}/.env.#{fetch(:rails_env)}"


      # Link the encrypted file in the release to the correct regional file (from repo)
      execute :ln, "-nfs",
        "#{release_path}/config/credentials/#{fetch(:rails_env)}.#{fetch(:env_variant)}.yml.enc",
        "#{release_path}/config/credentials/#{fetch(:rails_env)}.yml.enc"

      # Link the key in the release to the regional key stored in shared/
      execute :ln, "-nfs",
        "#{release_path}/config/credentials/#{fetch(:rails_env)}.#{fetch(:env_variant)}.key",
        "#{release_path}/config/credentials/#{fetch(:rails_env)}.key"
    end
  end
end

before "deploy:symlink:shared", "env:point_envfile"

# These tasks are to be called only when a completely new AMI, with no previous setup, is being used
# E.x bundle exec cap staging IRM:setup
namespace :IRM do

  desc 'Truncate all log files in the logs/ directory (including root-owned files)'
  task :truncate_logs do
    on roles(:app) do
      within release_path do
        # This will find all files under log/ and truncate them with sudo
        execute :sudo, "find #{release_path}/log/*.log -type f -exec truncate -s 0 {} \\;"
      end
    end
  end

  # Closes the first-boot gap: whenever installs the @reboot crontab
  # (config/schedule.rb) during cap deploy — AFTER a fresh box already booted,
  # so those entries do nothing until the NEXT reboot. Puma and sidekiq are
  # started by the deploy's own restart hooks anyway; xirr_py and
  # prometheus_exporter are not — this starts them, with a "already running?
  # do nothing" guard so it is a no-op on established boxes.
  # aws:setup_infra calls this right after deploy on every DR/drill/new-LZ
  # build; safe to run manually anytime:
  #   LB=true bundle exec cap staging_in IRM:start_boot_services
  desc 'Start services @reboot cron would start (for boxes deployed after their first boot)'
  task :start_boot_services do
    on roles(:app) do
      # xirr_py: keep image tag in sync with config/schedule.rb's @reboot line
      execute "sudo docker ps --format '{{.Names}}' | grep -qx xirr_py || " \
              "sudo docker run -d --rm --name xirr_py -p 8000:80 -v /tmp:/tmp thimmaiah/xirr_py:v2.6"
      # prometheus_exporter: same command as schedule.rb's @reboot bundle line;
      # nohup + log redirect so it survives this SSH session ending
      execute "pgrep -f prometheus_exporter >/dev/null || " \
              "(cd /home/ubuntu/IRM/current && RAILS_ENV=#{fetch(:stage)} nohup bundle exec prometheus_exporter -b 0.0.0.0 " \
              ">> /home/ubuntu/IRM/shared/log/prometheus_exporter.log 2>&1 &)"
    end
  end


  def configure_logrotate
    logrotate_config_path = "/home/ubuntu/IRM/shared/log/logrotate.conf"
    upload! StringIO.new(File.read('./config/deploy/logrotate.conf')), logrotate_config_path
    execute :sudo, "mkdir -p /home/ubuntu/IRM/shared/log"
    execute :sudo, 'chown root:root /home/ubuntu/IRM/shared/log/logrotate.conf'
    execute :sudo, 'chmod 644 /home/ubuntu/IRM/shared/log/logrotate.conf'
  end

  desc 'Setup logrotate configuration'
  task :setup_logrotate do
    on roles(:app) do
      configure_logrotate
    end
  end

  desc 'Set environment variable on remote host based on a local file'
  task :set_rails_master_key do
    on roles(:app) do
      # Path to the local file on your machine (relative to the project root or absolute)
      local_credentials_key = "./config/credentials/#{fetch(:rails_env)}.#{fetch(:env_variant)}.key"

      # Ensure the file exists locally
      unless File.exist?(local_credentials_key)
        error "The file #{local_credentials_key} does not exist."
        exit 1
      end

      # Read the content of the local file (assumed to contain the environment variable value)
      env_value = File.read(local_credentials_key).strip

      # Environment variable name (you can customize it or read from file if needed)
      env_var_name = 'RAILS_MASTER_KEY'

      # Command to append the environment variable to /etc/environment on the remote host
      set_env_command = "echo '#{env_var_name}=\"#{env_value}\"' | sudo tee -a /etc/environment"

      # Execute the command on the remote host
      execute set_env_command
      # Export the RAILS_MASTER_KEY
      execute "echo \"#{env_value}\" > #{release_path}/config/credentials/#{fetch(:stage)}.key"
      # Reload the environment so the change takes effect
      # execute :sudo, 'source /etc/environment'
    end
  end

  desc 'Generate and upload puma, nginx and systemd configuration'
  task :setup do
    on roles(:app) do
      # configure_logrotate

      # Define the paths
      system_config_path = "/etc/systemd/system/"
      nginx_config_path = "/etc/nginx/sites-available"
      puma_config_path = "/home/ubuntu/IRM/shared"

      # Helper method to generate and upload files
      def generate_and_upload(template_path, local_temp_path, remote_path)
        # Generate the file from the ERB template
        template = File.read(template_path)
        config = ERB.new(template).result(binding)
        # Upload the config file to the temporary location
        upload! StringIO.new(config), local_temp_path
        # Move the file to the final destination with sudo
        execute :sudo, :mv, local_temp_path, remote_path
      end

      # For Puma config
      execute :mkdir, "-p", "/home/ubuntu/IRM/shared/"
      local_puma_config = "/tmp/puma.rb"
      generate_and_upload('./config/deploy/templates/puma.rb.erb', local_puma_config, puma_config_path)

      # For Puma systemd service
      local_puma_service = "/tmp/puma_IRM_#{fetch(:stage)}.service"
      generate_and_upload('./config/deploy/services/puma_IRM_env.service.erb', local_puma_service, system_config_path)
      # Enable (not just restart) the unit so systemd itself starts puma on
      # every boot — WantedBy=multi-user.target in the unit file only takes
      # effect once `enable` has created the symlink. Without this, puma had
      # no boot-start path of its own, which is why config/schedule.rb used
      # to also launch puma directly from an @reboot cron entry — a second,
      # uncoordinated launcher that raced this systemd unit for the shared
      # unix socket and could permanently win with a stale release. Enabling
      # here is what makes removing that cron entry safe.
      execute :sudo, "systemctl daemon-reload"
      execute :sudo, "systemctl enable #{fetch(:puma_service_unit_name)}"

      # Sidekiq's systemd unit is installed by sidekiq:install_service, hooked
      # after this task below (and run by every deploy). Nothing uses monit any
      # more; monit:retire, also hooked below, switches it off on boxes whose
      # AMI still ships it.

      # for nginx config
      local_nginx_conf = "/tmp/IRM_#{fetch(:stage)}"
      generate_and_upload('./config/deploy/templates/nginx_conf.erb', local_nginx_conf, nginx_config_path)
      execute :sudo, "ln -s #{nginx_config_path}/IRM_#{fetch(:stage)} /etc/nginx/sites-enabled/IRM_#{fetch(:stage)} || true"

      # Remove the /etc/nginx/sites-enabled/default file
      execute :sudo, :rm, "-f", "/etc/nginx/sites-enabled/default"

      # Legacy naming: AMIs baked before the IRM_<stage> convention ship an
      # ENABLED `nginx_IRM_<stage>` site (symlink dated 2024-09 on the current
      # production AMI) that declares the SAME `upstream puma_IRM_<stage>`
      # block as the config installed above. Two enabled files declaring one
      # upstream makes `nginx -t` fail with "duplicate upstream", so nginx
      # refuses to start and the run dies at deploy:ensure_permissions'
      # `service nginx restart`.
      # Found by the FIRST production DR drill — staging AMIs don't carry the
      # legacy file, so this was invisible to every staging drill.
      execute :sudo, :rm, "-f", "/etc/nginx/sites-enabled/nginx_IRM_#{fetch(:stage)}"

      execute :mkdir, "-p", "/home/ubuntu/IRM/shared/tmp/sockets"
      execute :touch, "/home/ubuntu/IRM/shared/tmp/sockets/IRM-puma.sock"

      # Install Pandoc for DOCX export with charts.
      # DPkg::Lock::Timeout makes apt WAIT (up to 10 min) for the dpkg lock
      # instead of dying with exit 100 — on a freshly booted instance,
      # unattended-upgrades holds the lock for the first few minutes, which
      # broke IRM:setup during DR rebuilds (found by the DR drill).
      execute :sudo, "apt-get -o DPkg::Lock::Timeout=600 install -y pandoc"

      # restart nginx - Does not work as the nginx config is pointing to the app, which is not yet deployed
      # execute :sudo, "service nginx restart"
    end
  end

  # After setup, not inside it: monit:retire needs the puma unit that setup has
  # just installed and enabled.
  after 'IRM:setup', 'monit:retire'
  after 'IRM:setup', 'sidekiq:install_service'

  task :reboot do
    on roles(:app) do
      execute :sudo, :reboot
    end
  end

  task :apt_update do
    on roles(:app) do
      # Same dpkg-lock wait as IRM:setup — never race unattended-upgrades
      execute :sudo, "apt-get -o DPkg::Lock::Timeout=600 update"
      execute :sudo, "apt-get -o DPkg::Lock::Timeout=600 upgrade -y"
      execute :sudo, "journalctl --vacuum-time=2d"
      execute :sudo, "reboot"
    end
  end

  # Installs an RVM Ruby on the box (if it isn't already) and makes it the RVM
  # default, so every rvm-wrapped command picks it up: capistrano-rvm's own
  # command prefix (rvm_ruby_version defaults to "default" — see
  # lib/capistrano/tasks/rvm.rake in the gem), and the literal
  # `~/.rvm/bin/rvm default do` in the sidekiq systemd unit's ExecStart
  # (config/deploy/services/sidekiq_IRM_env.service.erb). The AMI's baked-in Ruby comes
  # from the same `rvm install` mechanism (see get.rvm.io line in
  # config/deploy/templates/packer/appserver.ami.pkr.hcl) — this task is what
  # to run afterwards on a box that needs a *different* Ruby than the AMI
  # shipped with, without re-baking an AMI. Idempotent: re-running is a no-op
  # once the target is installed and already default.
  #
  # Does NOT touch the app's gems — with the default Ruby switched, RVM gems
  # live in a fresh gemset, so the next `deploy` (via capistrano-bundler) is
  # what (re)installs them under the new Ruby.
  #
  # Version defaults to the repo's own .ruby-version; override for a one-off:
  #   bundle exec cap staging_in IRM:install_ruby
  #   RUBY_VERSION=4.0.6 bundle exec cap staging_us IRM:install_ruby
  desc 'Install an RVM Ruby on the box and set it as the RVM default'
  task :install_ruby do
    on roles(:app) do
      target = (ENV["RUBY_VERSION"] || File.read("./.ruby-version").strip).sub(/\Aruby-/, "")
      rvm = "source ~/.rvm/scripts/rvm &&"

      installed = capture(:bash, "-lc", "'#{rvm} rvm list strings'").split("\n")
      unless installed.include?("ruby-#{target}")
        info "ruby-#{target} not found on this box — installing via RVM (this can take several minutes)"
        # Same dpkg-lock wait as IRM:setup/apt_update: `rvm install` calls
        # apt-get for build deps under the hood and would otherwise race
        # unattended-upgrades on a freshly booted or freshly-upgraded box.
        execute :sudo, "apt-get -o DPkg::Lock::Timeout=600 update"
        execute :bash, "-lc", "'#{rvm} rvm install ruby-#{target}'"
      end

      execute :bash, "-lc", "'#{rvm} rvm --default use ruby-#{target}'"

      current = capture(:bash, "-lc", "'#{rvm} rvm current'").strip
      raise "expected ruby-#{target} to be the RVM default, got #{current}" unless current == "ruby-#{target}"

      info "RVM default on #{host} is now #{current}"
    end
  end

  # before 'IRM:setup', 'IRM:set_rails_master_key'
end
