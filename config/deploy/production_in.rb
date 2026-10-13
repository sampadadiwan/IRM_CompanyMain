# deploy/production_india.rb
# server-based syntax
# ======================
# Defines a single server with a list of roles and multiple properties.
# You can define all roles on a single server, or split them:

# ap_south_1
server "15.206.165.118", user: "ubuntu", roles: %w[primary app db web]
server "35.154.185.236", user: "ubuntu", roles: %w[app web]
# ap_south_2
# server "18.61.81.133", user: "ubuntu", roles: %w[primary app db web]
# server "18.61.2.41", user: "ubuntu", roles: %w[app web] if ENV["LB"]

set :rails_env, "production"
set :stage, :production
set :env_variant, "in"

# Enables the static-website server blocks in nginx_conf.erb: apex serves
# public/website, www 301s to the apex. Stages without this render the
# template exactly as before. Pairs with WEBSITE_HOSTS in .env.production.in.
set :website_domain, "caphive.com"

# One ssh_options hash: a second `set :ssh_options` replaces the first rather
# than merging, which silently dropped keepalive. Without it, the ~5 min of
# silence during assets:precompile lets mobile/NAT links drop the connection,
# so cap hangs on a command that already finished on the box.
set :ssh_options, {
  user: 'ubuntu',
  keys: ['~/.ssh/caphive2.pem'],
  forward_agent: true,
  auth_methods: %w[publickey],
  verify_host_key: :never,
  compression: false,
  keepalive: true,
  keepalive_interval: 30 # seconds between keepalives during silent steps
}
