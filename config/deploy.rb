# config valid for current version and patch releases of Capistrano
lock "~> 3.18"

set :application, "IRM"
set :repo_url, "git@github.com:ausangshukla/IRM.git"
set :branch, ENV["branch"] || 'main'

set :deploy_to, "/home/ubuntu/IRM"
set :ssh_options, forward_agent: true
if fetch(:stage) == :production
  set :ssh_options, keys: "~/.ssh/caphive.pem"
else
  set :ssh_options, keys: "~/.ssh/altxdev.pem"
end

# Default value for :pty is false
set :pty, true

# Default value for linked_dirs is []
append :linked_dirs, "log", "tmp/pids", "tmp/cache", "tmp/sockets", "public/system", '.bundle'

set :bundle_binstubs, -> { shared_path.join('bin') }
set :bundle_jobs, 8

# Default value for keep_releases is 5
set :keep_releases, 3

# Uncomment the following to require manually verifying the host key before first deploy.
# set :ssh_options, verify_host_key: :secure

set :puma_bind,       "unix://#{shared_path}/tmp/sockets/#{fetch(:application)}-puma.sock"
set :puma_state,      "#{shared_path}/tmp/pids/puma.state"
set :puma_pid,        "#{shared_path}/tmp/pids/puma.pid"
set :puma_access_log, "#{release_path}/log/puma.error.log"
set :puma_error_log,  "#{release_path}/log/puma.access.log"
set :puma_preload_app, true
set :puma_worker_timeout, nil
set :puma_daemonize, true
set :puma_init_active_record, true

namespace :deploy do
  desc "Uploads .env remote servers."
  task :upload_env do
    on roles(:app) do
      # This is stored in /etc/environments
      execute "echo $RAILS_MASTER_KEY > #{release_path}/config/credentials/#{fetch(:stage)}.key"
    end
    # Rake::Task["deploy:assets:precompile"].clear_actions
    # Rake::Task["deploy:migrate"].clear_actions
  end

  before "deploy:updated", :upload_env
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

  task :stop_kuma do
    on roles(:app) do |_host|
      execute :docker, 'stop uptime-kuma|| true'
    end
  end
end
