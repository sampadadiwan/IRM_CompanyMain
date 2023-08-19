# config valid for current version and patch releases of Capistrano
lock "~> 3.17.2"

set :application, "IRM"
set :repo_url, "git@github.com:thimmaiah/IRM.git"
set :branch, 'main'

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
append :linked_dirs, "log", "tmp/pids", "tmp/cache", "tmp/sockets", "public/system"

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
    Rake::Task["deploy:assets:precompile"].clear_actions

  end

  before "deploy:updated", :upload_env
  after "deploy", "sidekiq:restart"

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
