# server-based syntax
# ======================
# Defines a single server with a list of roles and multiple properties.
# You can define all roles on a single server, or split them:

server "34.229.217.208", user: "ubuntu", roles: %w[app web] if ENV["LB"]
server "13.222.236.84", user: "ubuntu", roles: %w[primary app web db]

set :rails_env, "staging"
set :stage, :staging
set :env_variant, "us"

set :ssh_options, keys: "~/.ssh/altx.us.pem", compression: false, keepalive: true

set :ssh_options, {
  user: 'ubuntu',
  keys: ['~/.ssh/altx.us.pem'],
  forward_agent: true,
  auth_methods: %w[publickey],
  verify_host_key: :never
}
