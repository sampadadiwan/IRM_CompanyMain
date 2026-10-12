# server-based syntax
# ======================
# Defines a single server with a list of roles and multiple properties.
# You can define all roles on a single server, or split them:

# Two app servers, matching production topology (Pulumi launches one web
# server per public subnet behind the ALB):
#   - LB unset -> only the primary line active -> normal single-host deploy
#   - LB=true  -> both lines active (aws:setup_infra/dr_drill pass LB=true)
# Both lines deliberately carry the SAME IP while live staging is a single
# box: Capistrano merges duplicate hosts, so LB=true degrades gracefully.
# A DR rewrite (replace_ip_addresses) fills the two fresh IPs in file order.
server "52.66.163.132", user: "ubuntu", roles: %w[app web] if ENV["LB"]
server "52.66.163.132", user: "ubuntu", roles: %w[primary app web db]

set :rails_env, "staging"
set :stage, :staging
set :env_variant, "in"

# Enables the static-website server blocks in nginx_conf.erb: apex serves
# public/website, www 301s to the apex. Pairs with WEBSITE_HOSTS in
# .env.staging.in. Lets the website rollout be rehearsed end-to-end on
# staging before the production DNS cutover.
set :website_domain, "altconnects.com"

# One ssh_options hash: a second `set :ssh_options` replaces the first rather
# than merging, which silently dropped keepalive. Without it, the ~5 min of
# silence during assets:precompile lets mobile/NAT links drop the connection,
# so cap hangs on a command that already finished on the box.
set :ssh_options, {
  user: 'ubuntu',
  keys: ['~/.ssh/altxdev.pem'],
  forward_agent: true,
  auth_methods: %w[publickey],
  verify_host_key: :never,
  compression: false,
  keepalive: true,
  keepalive_interval: 30 # seconds between keepalives during silent steps
}
