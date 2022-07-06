# config valid for current version and patch releases of Capistrano
lock "~> 3.16.0"

set :application, "IRM"
set :repo_url, "git@github.com:thimmaiah/IRM.git"
set :branch, 'main'

# Default branch is :master
# ask :branch, `git rev-parse --abbrev-ref HEAD`.chomp

# Default deploy_to directory is /var/www/my_app_name
# set :deploy_to, "/var/www/my_app_name"
set :deploy_to, "/home/ubuntu/IRM"
set :ssh_options, forward_agent: true
# set :ssh_options, keys: "/home/thimmaiah/.ssh/altxdev.pem"
set :ssh_options, keys: "/home/thimmaiah/.ssh/caphive.pem"
# Default value for :format is :airbrussh.
# set :format, :airbrussh

# You can configure the Airbrussh format using :format_options.
# These are the defaults.
# set :format_options, command_output: true, log_file: "log/capistrano.log", color: :auto, truncate: :auto

# Default value for :pty is false
set :pty, true

# Default value for :linked_files is []
# append :linked_files, "config/database.yml"

# Default value for linked_dirs is []
append :linked_dirs, "log", "tmp/pids", "tmp/cache", "tmp/sockets", "public/system"

# Default value for default_env is {}
# set :default_env, { path: "/opt/ruby/bin:$PATH" }

# Default value for local_user is ENV['USER']
# set :local_user, -> { `git config user.name`.chomp }

# Default value for keep_releases is 5
# set :keep_releases, 5

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
      upload!("/data/work/IRM/.env", release_path.to_s, recursive: false)
      upload!("/data/work/IRM/.env.local", release_path.to_s, recursive: false) if fetch(:stage) != :production
      upload!("/data/work/IRM/.env.staging", release_path.to_s, recursive: false) if fetch(:stage) == :staging
      upload!("/data/work/IRM/.env.sandbox", release_path.to_s, recursive: false) if fetch(:stage) == :sandbox
      upload!("/data/work/IRM/.env.production", release_path.to_s, recursive: false) if fetch(:stage) == :production
    end
  end

  before "deploy:assets:precompile", :upload_env
  after "deploy", "sidekiq:restart"

  # desc 'Initial Deploy'
  # task :initial do
  #   on roles(:app) do
  #     before 'deploy:restart', 'puma:start'
  #     invoke 'deploy'
  #   end
  # end

  # desc 'Restart application'
  # task :restart do
  #   on roles(:app), in: :sequence, wait: 5 do
  #     invoke 'puma:restart'
  #   end
  # end
end

namespace :puma do
  desc 'Create Directories for Puma Pids and Socket'
  task :make_dirs do
    on roles(:app) do
      execute "mkdir #{shared_path}/tmp/sockets -p"
      execute "mkdir #{shared_path}/tmp/pids -p"
    end
  end

  # before :start, :make_dirs
end
