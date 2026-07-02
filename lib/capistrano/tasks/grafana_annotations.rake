require 'net/http'
require 'uri'
require 'json'
require 'base64'

# Posts a deployment annotation to Grafana after every successful deploy.
# This adds a vertical marker on all dashboards showing exactly when deploys happened,
# making it easy to correlate "memory spiked at 14:00" with "we deployed at 13:55".
#
# Usage:
#   Set GRAFANA_PASS (and optionally GRAFANA_URL, GRAFANA_USER) in your shell before deploying.
#   If GRAFANA_PASS is not set, the annotation is silently skipped — deploy is never blocked.
#
# In Grafana, to see the markers on a dashboard:
#   Dashboard settings → Annotations → Add annotation query
#   → Datasource: Grafana → Filter by tag: deploy

namespace :grafana do
  desc 'Post a deploy annotation to Grafana (non-fatal if Grafana is unreachable)'
  task :annotate do
    grafana_url  = ENV.fetch('GRAFANA_URL',  'https://graphana.caphive.com')
    grafana_user = ENV.fetch('GRAFANA_USER', 'admin')
    grafana_pass = ENV.fetch('GRAFANA_PASS', '')

    # Silently skip if no credentials — don't break deploys over a missing annotation
    next if grafana_pass.empty?

    # fetch(:current_revision) is the exact SHA Capistrano deployed — more reliable than git HEAD
    sha      = fetch(:current_revision, 'unknown')[0, 8]
    branch   = fetch(:branch, 'main').to_s
    stage    = fetch(:stage, 'production').to_s
    deployer = `git config user.name 2>/dev/null`.strip.presence || ENV['USER'] || 'unknown'
    text     = "Deploy #{sha} → #{stage} (#{branch}) by #{deployer}"

    uri      = URI("#{grafana_url}/api/annotations")
    req      = Net::HTTP::Post.new(uri)
    req['Authorization'] = "Basic #{Base64.strict_encode64("#{grafana_user}:#{grafana_pass}")}"
    req['Content-Type']  = 'application/json'
    req.body             = { text: text, tags: ['deploy', stage] }.to_json

    http             = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl     = (uri.scheme == 'https')
    http.read_timeout = 10

    res  = http.request(req)
    body = JSON.parse(res.body) rescue {}
    puts "  Grafana annotation: #{body['message'] || res.code} — #{text}"
  rescue => e
    # Never fail a deploy because Grafana is unreachable
    puts "  Grafana annotation skipped: #{e.message}"
  end
end

# Runs after every successful deploy, regardless of stage
after 'deploy:finished', 'grafana:annotate'
