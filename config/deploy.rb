# config valid for current version and patch releases of Capistrano
lock "~> 3.18"

set :application, "IRM"
set :repo_url, "git@github.com:ausangshukla/IRM.git"
set :branch, ENV["branch"] || 'main'

set :deploy_to, "/home/ubuntu/IRM"
set :ssh_options, forward_agent: true
if fetch(:stage) == :production
  set :ssh_options, keys: "~/.ssh/caphive2.pem", compression: false, keepalive: true
else
  set :ssh_options, keys: "~/.ssh/altxdev.pem", compression: false, keepalive: true
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
set :puma_preload_app, true
set :puma_worker_timeout, nil
set :puma_workers, 4
set :puma_daemonize, true
set :puma_init_active_record, true

set :puma_systemctl_user, :system
set :puma_service_unit_name, "puma_IRM_#{fetch(:stage)}"


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

  before 'deploy:starting', 'deploy:notify_before'
  after 'deploy:finished', 'deploy:notify_after'

  desc "Uploads .env remote servers."
  task :ensure_rails_credentials do
    on roles(:app) do
      # This is stored in /etc/environments when the AMI is built
      execute "echo $RAILS_MASTER_KEY > #{release_path}/config/credentials/#{fetch(:stage)}.key"
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

  before "deploy:updated", :ensure_rails_credentials
  before 'deploy:finished', 'sidekiq:restart'
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
  before 'nginx:switch_maintenance', 'puma:monit:unmonitor'
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
  before 'nginx:switch_app', 'puma:monit:monitor'
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
        execute :rake, "'db:restore['IRM_#{fetch(:stage)}', 'Primary']' RAILS_ENV=#{fetch(:stage)}"
        execute :rake, "db:create_replica RAILS_ENV=#{fetch(:stage)}"
      end
    end
  end

  task :create_replica do
    on roles(:primary), in: :sequence, wait: 5 do
      within release_path do
        execute :rake, "db:create_replica RAILS_ENV=#{fetch(:stage)}"
      end
    end
  end

  task :delete_old_assets do
    on roles(:app) do |_host|
      execute :docker, 'stop uptime-kuma|| true'
      execute :rm, '-rf', '/home/ubuntu/IRM/shared/releases/* || true'
      execute :rm, '-rf', '/home/ubuntu/IRM/shared/tmp/cache/assets/* || true'
    end
  end

  
end

# These tasks are to be called only when a completely new AMI, with no previous setup, is being used
# E.x bundle exec cap staging IRM:setup
namespace :IRM do
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
      local_credentials_key = "./config/credentials/#{fetch(:stage)}.key"

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

      # Reload the environment so the change takes effect
      # execute :sudo, 'source /etc/environment'
    end
  end

  desc 'Generate and upload Monit, nginx configuration and systemd service files'
  task :setup do
    on roles(:app) do
      configure_logrotate
    
      # Define the paths
      monit_config_path = "/etc/monit/conf.d"
      system_config_path = "/etc/systemd/system/"
      nginx_config_path = "/etc/nginx/sites-available"

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

      # For Puma Monit config
      local_puma_monit = "/tmp/puma_IRM_#{fetch(:stage)}.conf"
      generate_and_upload('./config/deploy/monit/puma_IRM_env.conf.erb', local_puma_monit, monit_config_path)

      # For Puma systemd service
      local_puma_service = "/tmp/puma_IRM_#{fetch(:stage)}.service"
      generate_and_upload('./config/deploy/services/puma_IRM_env.service.erb', local_puma_service, system_config_path)

      # For Sidekiq Monit config
      local_sidekiq_monit = "/tmp/sidekiq_IRM_#{fetch(:stage)}.conf"
      generate_and_upload('./config/deploy/monit/sidekiq_IRM_env.conf.erb', local_sidekiq_monit, monit_config_path)

      # for nginx config
      local_nginx_conf = "/tmp/nginx_IRM_#{fetch(:stage)}"
      generate_and_upload('./config/deploy/templates/nginx_conf.erb', local_nginx_conf, nginx_config_path)
      execute :sudo, "ln -s #{nginx_config_path}/nginx_IRM_#{fetch(:stage)} /etc/nginx/sites-enabled/nginx_IRM_#{fetch(:stage)} || true"

      # for monitrc
      local_monitrc = "/tmp/monitrc"
      generate_and_upload('./config/deploy/templates/monitrc.erb', local_monitrc, "/etc/monit/monitrc")
      execute :sudo, :chown, "root", "/etc/monit/monitrc"
      execute :sudo, :chmod, "700", "/etc/monit/monitrc"
      # Reload Monit to apply the new configuration
      execute :sudo, "monit reload"

      # Remove the /etc/nginx/sites-enabled/default file
      execute :sudo, :rm, "-f", "/etc/nginx/sites-enabled/default"

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
      execute :sudo, "apt-get update"
      execute :sudo, "apt-get upgrade -y"
      execute :sudo, "journalctl --vacuum-time=2d"
      execute :sudo, "reboot"
    end
  end

  before 'IRM:setup', 'IRM:set_rails_master_key'
end
