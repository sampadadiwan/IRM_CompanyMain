# deploy/production_india.rb
# server-based syntax
# ======================
# Defines a single server with a list of roles and multiple properties.
# You can define all roles on a single server, or split them:

# ap_south_1
server "54.147.171.162", user: "ubuntu", roles: %w[primary app db web]
# server "13.217.203.38", user: "ubuntu", roles: %w[app web] if ENV["LB"]
# ap_south_2
# server "", user: "ubuntu", roles: %w[primary app db web]
# server "", user: "ubuntu", roles: %w[app web] if ENV["LB"]

set :rails_env, "production"
set :stage, :production
set :env_variant, "us"

set :ssh_options, keys: "~/.ssh/caphive2.us.pem", compression: false, keepalive: true

set :ssh_options, {
  user: 'ubuntu',
  keys: ['~/.ssh/caphive2.us.pem'],
  forward_agent: true,
  auth_methods: %w[publickey],
  verify_host_key: :never
}
