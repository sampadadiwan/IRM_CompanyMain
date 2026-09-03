require 'net/http'
require 'uri'
require 'json'
require 'base64'

namespace :grafana do
  # Local/redundant health check driven by bin/check_grafana_health (cron: 8am + 6pm).
  # Reads every stat panel on the checked-in "CapHive Overview" dashboard
  # (config/initializers/observability/graphana/<region>/overview.dashboard.json) —
  # the same PromQL + thresholds provisioned into Grafana by
  # `rake grafana:provision:overview_dashboard` — queries each one live via the
  # Grafana datasource proxy, and evaluates it against the panel's own
  # green/yellow/red thresholds. A red breach here is the same condition an
  # actual Grafana alert rule would fire on; this exists to catch the case
  # where Grafana's OWN alerting path is broken (analogous to why
  # bin/check_db_backup_freshness re-checks S3 from outside AWS instead of
  # trusting the server's own DbBackupFreshnessJob email).
  #
  #   rake "grafana:health_check[production.in]"
  #   rake "grafana:health_check[production.us]"
  desc 'Query the CapHive Overview dashboard panels and report red/yellow threshold breaches'
  task :health_check, [:env_name] => :environment do |_t, args|
    GrafanaHealthChecker.new(args[:env_name]).run
  end
end

class GrafanaHealthChecker
  # env_name -> Grafana instance. Mirrors GrafanaProvisioner::REGION_BY_HOST (inverted) —
  # two separate Grafana instances, one per AWS account/region.
  GRAFANA_URLS = {
    'production.in' => 'https://graphana.caphive.com',
    'production.us' => 'https://graphana.caphive.us'
  }.freeze

  # Both instances' Prometheus datasource happens to be id 1 (verified live), but stays
  # overridable in case that ever drifts — same as infra_report.rake's GRAFANA_DS_ID.
  DS_ID = ENV.fetch('GRAFANA_DS_ID', '1')

  UNIT_SUFFIX = { 'percent' => '%', 'ms' => 'ms', 's' => 's', 'short' => '' }.freeze

  def initialize(env_name)
    raise "env_name required — one of #{GRAFANA_URLS.keys.join(', ')}" unless GRAFANA_URLS.key?(env_name)

    @env_name = env_name
    @url = GRAFANA_URLS.fetch(env_name)
    @pass = credentials[:GRAFANA_PASS]
    raise "GRAFANA_PASS not set in config/credentials/#{env_name}.yml.enc" if @pass.blank?

    @user = ENV.fetch('GRAFANA_USER', 'admin')
    @region = env_name.sub('production.', '')
  end

  def run
    panels = dashboard_panels
    results = panels.map { |panel| evaluate_panel(panel) }

    results.each { |r| puts format_line(r) }

    failed = results.select { |r| r[:status] == 'red' }
    warned = results.select { |r| r[:status] == 'yellow' }
    missing = results.select { |r| r[:status] == 'nodata' }

    puts
    if failed.empty? && missing.empty?
      puts "Grafana health check passed (#{@region}): #{results.size} panels checked, #{warned.size} warning(s)"
    else
      puts "Grafana health check FAILED (#{@region}): #{failed.size} critical, #{missing.size} no-data, #{warned.size} warning"
    end
  end

  private

  # env_name-aware credentials source — same approach as DbBackupFreshnessJob#credentials.
  # This never boots against a deployed server, so Rails.application.credentials would
  # otherwise resolve to whatever is symlinked locally (development) — reading the
  # regional config/credentials/<env_name>.yml.enc directly is what makes GRAFANA_PASS
  # resolve to the right AWS account's Grafana instance from a laptop.
  def credentials
    key_path = Rails.root.join('config', 'credentials', "#{@env_name}.key")
    raise "Key file not found for environment '#{@env_name}' at #{key_path}" unless File.exist?(key_path)

    Rails.application.encrypted(
      Rails.root.join('config', 'credentials', "#{@env_name}.yml.enc"),
      key_path: key_path
    )
  end

  def dashboard_panels
    path = Rails.root.join('config', 'initializers', 'observability', 'graphana', @region, 'overview.dashboard.json')
    raise "No overview dashboard found for region '#{@region}' at #{path}" unless File.exist?(path)

    JSON.parse(File.read(path))['panels'].select { |p| p['type'] == 'stat' }
  end

  def evaluate_panel(panel)
    title = panel['title']
    expr = panel.dig('targets', 0, 'expr')
    steps = panel.dig('fieldConfig', 'defaults', 'thresholds', 'steps') || []
    unit = panel.dig('fieldConfig', 'defaults', 'unit')

    series = query(expr)
    if series.empty?
      return { title: title, status: 'nodata', detail: 'no data returned (exporter unreachable?)' }
    end

    # by(instance)/by(instance,device) queries return one series per host — evaluate
    # each independently so one bad host isn't diluted by averaging with healthy ones,
    # and surface which instance/series tripped the worst status.
    evaluated = series.map { |s| [s[:instance], s[:value], status_for(s[:value], steps)] }
    worst = evaluated.max_by { |(_i, _v, status)| SEVERITY[status] }
    _instance, value, status = worst

    detail = evaluated.size > 1 ? "#{format_value(value, unit)} (#{worst[0] || 'n/a'}, worst of #{evaluated.size})" : format_value(value, unit)
    { title: title, status: status, detail: detail }
  end

  SEVERITY = { 'green' => 0, 'yellow' => 1, 'red' => 2 }.freeze

  def status_for(value, steps)
    sorted = steps.sort_by { |s| s['value'] || -Float::INFINITY }
    applicable = sorted.select { |s| (s['value'] || -Float::INFINITY) <= value }
    applicable.last&.dig('color') || 'green'
  end

  def format_value(value, unit)
    "#{value.round(1)}#{UNIT_SUFFIX.fetch(unit, '')}"
  end

  # Instant query via the Grafana datasource proxy, WAF-bypassed the same way
  # infra_report.rake does: raw queries with {label=...} matchers are blocked in a GET
  # querystring, but pass when wrapped in a window function and sent via POST body.
  def query(raw_query)
    return [] if raw_query.blank?

    wrapped = "max_over_time((#{raw_query})[10m:5m])"
    uri = URI("#{@url}/api/datasources/proxy/#{DS_ID}/api/v1/query")
    req = Net::HTTP::Post.new(uri)
    req['Authorization'] = "Basic #{Base64.strict_encode64("#{@user}:#{@pass}")}"
    req['Content-Type'] = 'application/x-www-form-urlencoded'
    req.body = URI.encode_www_form('query' => wrapped, 'time' => Time.now.to_i)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.read_timeout = 30

    body = JSON.parse(http.request(req).body)
    Array(body.dig('data', 'result')).filter_map do |r|
      val = r.dig('value', 1)&.to_f
      next if val.nil?

      { instance: r.dig('metric', 'instance'), value: val }
    end
  rescue => e
    warn "  query error: #{e.message}"
    []
  end

  def format_line(r)
    icon = { 'red' => '✗', 'yellow' => '⚠', 'nodata' => '?', 'green' => '✓' }.fetch(r[:status])
    "#{icon} #{r[:title]}: #{r[:detail]}"
  end
end
