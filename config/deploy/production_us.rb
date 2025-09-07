# deploy/production_india.rb
# server-based syntax
# ======================
# Defines a single server with a list of roles and multiple properties.
# You can define all roles on a single server, or split them:

# ap_south_1
server "13.201.60.201", user: "ubuntu", roles: %w[primary app db web]
server "13.233.131.224", user: "ubuntu", roles: %w[app web] if ENV["LB"]
# ap_south_2
# server "18.61.81.133", user: "ubuntu", roles: %w[primary app db web]
# server "18.61.2.41", user: "ubuntu", roles: %w[app web] if ENV["LB"]

set :rails_env, "production_us"
set :stage, :production

set :ssh_options, keys: "~/.ssh/caphive2.pem", compression: false, keepalive: true

set :ssh_options, {
  user: 'ubuntu',
  keys: ['~/.ssh/caphive2.pem'],
  forward_agent: true,
  auth_methods: %w[publickey],
  verify_host_key: :never
}
