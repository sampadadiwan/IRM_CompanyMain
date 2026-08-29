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

  before 'deploy:updated', 'IRM:set_rails_master_key'
  # before "deploy:updated", :ensure_rails_credentials
  # before 'deploy:finished', 'sidekiq:restart' # This is handled by the capistrano-sidekiq gem
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

  before 'nginx:switch_maintenance', 'sidekiq:monit:unmonitor'
  # before 'nginx:switch_maintenance', 'puma:monit:unmonitor'
  before 'nginx:switch_maintenance', 'sidekiq:stop'
  before 'nginx:switch_maintenance', 'puma:stop'

  task :switch_app do
    on roles(:app) do
      within release_path do
        execute :rake, "\"nginx:switch[IRM_#{fetch(:stage)}]\" RAILS_ENV=#{fetch(:stage)}"
      end
    end
  end

  after 'nginx:switch_app', 'sidekiq:restart'
  after 'nginx:switch_app', 'puma:restart'
  before 'nginx:switch_app', 'sidekiq:monit:monitor'
  # before 'nginx:switch_app', 'puma:monit:monitor'

  desc 'Render and install ONLY the nginx config, then validate and reload'
  task :update do
    on roles(:app) do
      # IRM:setup also re-uploads puma/monit/systemd configs and reloads
      # monit. When the only change is nginx_conf.erb (e.g. adding the
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

  # Installs the systemd drop-in that undoes the sandbox Ubuntu's monit package
  # applies to monit.service, then re-execs monit so it takes effect. The
  # sandbox is a property of the monit PROCESS and is inherited by everything it
  # spawns, so `monit reload` is NOT enough here — monit itself has to restart.
  # Idempotent; called from IRM:setup and from IRM:fix_monit_sandbox.
  def configure_monit_sandbox
    override_dir = "/etc/systemd/system/monit.service.d"

    execute :sudo, :mkdir, "-p", override_dir
    upload! StringIO.new(File.read('./config/deploy/templates/monit_service_override.conf')),
            "/tmp/monit_override.conf"
    execute :sudo, :mv, "/tmp/monit_override.conf", "#{override_dir}/override.conf"
    execute :sudo, :chown, "root:root", "#{override_dir}/override.conf"
    execute :sudo, :chmod, "644", "#{override_dir}/override.conf"

    execute :sudo, "systemctl daemon-reload"
    execute :sudo, "systemctl restart monit"

    # Prove the sandbox is actually gone rather than assuming the restart took —
    # this is precisely the class of failure that was passing silently before.
    # --no-pager: `:pty, true` (above) makes stdout look like a real terminal to
    # systemctl, and CapabilityBoundingSet's value is long enough that it pages
    # through `less` — which then hangs forever waiting for a keypress that a
    # non-interactive deploy will never send (found live during a DR drill).
    nnp = capture(:systemctl, "show", "monit", "-p", "NoNewPrivileges", "--value", "--no-pager").strip
    caps = capture(:systemctl, "show", "monit", "-p", "CapabilityBoundingSet", "--value", "--no-pager").strip
    info "monit sandbox now: NoNewPrivileges=#{nnp}, CapabilityBoundingSet=#{caps}"
    raise "monit is still sandboxed (NoNewPrivileges=#{nnp}) — drop-in did not apply" if nnp == "yes"
  end

  desc 'Install the systemd drop-in that lets monit start/stop our services'
  task :fix_monit_sandbox do
    on roles(:app) do
      configure_monit_sandbox
    end
  end

  desc 'Generate and upload Monit, nginx configuration and systemd service files'
  task :setup do
    on roles(:app) do
      # configure_logrotate

      # Define the paths
      monit_config_path = "/etc/monit/conf.d"
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


      # For Puma Monit config
      local_puma_monit = "/tmp/puma_IRM_#{fetch(:stage)}.conf"
      generate_and_upload('./config/deploy/monit/puma_IRM_env.conf.erb', local_puma_monit, monit_config_path)

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

      # For Sidekiq Monit config
      local_sidekiq_monit = "/tmp/sidekiq_IRM_#{fetch(:stage)}.conf"
      generate_and_upload('./config/deploy/monit/sidekiq_IRM_env.conf.erb', local_sidekiq_monit, monit_config_path)

      # for nginx config
      local_nginx_conf = "/tmp/IRM_#{fetch(:stage)}"
      generate_and_upload('./config/deploy/templates/nginx_conf.erb', local_nginx_conf, nginx_config_path)
      execute :sudo, "ln -s #{nginx_config_path}/IRM_#{fetch(:stage)} /etc/nginx/sites-enabled/IRM_#{fetch(:stage)} || true"

      # for monitrc
      local_monitrc = "/tmp/monitrc"
      generate_and_upload('./config/deploy/templates/monitrc.erb', local_monitrc, "/etc/monit/monitrc")
      execute :sudo, :chown, "root", "/etc/monit/monitrc"
      execute :sudo, :chmod, "700", "/etc/monit/monitrc"

      # Un-sandbox monit before restarting it. The AMI installs monit from apt
      # (see templates/packer/appserver.ami.pkr.hcl), and the packaged unit is
      # hardened to the point where monit cannot su/sudo to ubuntu or even see
      # /home — so every `start program` fails and nothing it supervises can be
      # started. Full explanation in the drop-in itself. This also restarts
      # monit, which picks up the conf.d/monitrc changes above, so no separate
      # `monit reload` is needed here.
      configure_monit_sandbox

      # Remove the /etc/nginx/sites-enabled/default file
      execute :sudo, :rm, "-f", "/etc/nginx/sites-enabled/default"

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

  # before 'IRM:setup', 'IRM:set_rails_master_key'
end
