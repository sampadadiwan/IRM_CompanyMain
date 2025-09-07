# server-based syntax
# ======================
# Defines a single server with a list of roles and multiple properties.
# You can define all roles on a single server, or split them:

# server "40.192.36.112", user: "ubuntu", roles: %w[app web] if ENV["LB"]
# server "98.130.51.54", user: "ubuntu", roles: %w[primary app web db]

server "13.233.55.8", user: "ubuntu", roles: %w[primary app web db]

set :rails_env, "staging"
set :stage, :staging
set :env_variant, "in"

set :ssh_options, keys: "~/.ssh/altxdev.pem", compression: false, keepalive: true

set :ssh_options, {
  user: 'ubuntu',
  keys: ['~/.ssh/altxdev.pem'],
  forward_agent: true,
  auth_methods: %w[publickey],
  verify_host_key: :never
}
