require 'net/http'
require 'uri'
require 'json'
require 'base64'
require 'yaml'
require 'fileutils'

namespace :grafana do
  desc "Apply all Grafana provisioning — contact points, alert rules, dashboard patches"
  task provision: :environment do
    GrafanaProvisioner.new.run_all
  end

  namespace :provision do
    desc "Apply contact points and notification policy only"
    task contact_points: :environment do
      p = GrafanaProvisioner.new
      p.provision_contact_points
      p.provision_notification_policy
    end

    desc "Apply alert rules only (idempotent — deletes and recreates rules in the folder)"
    task alert_rules: :environment do
      GrafanaProvisioner.new.provision_alert_rules
    end

    desc "Patch dashboards (fix queries, add panels/variables) and save JSON to config/grafana/dashboards/"
    task dashboards: :environment do
      GrafanaProvisioner.new.provision_dashboards
    end

    desc "Save current live dashboard JSON to config/grafana/dashboards/ without patching (for initial backup)"
    task save: :environment do
      GrafanaProvisioner.new.save_dashboards
    end

    desc "Create/update the CapHive Overview dashboard (current-state stat panels for all systems)"
    task overview_dashboard: :environment do
      GrafanaProvisioner.new.provision_overview_dashboard
    end
  end
end

class GrafanaProvisioner
  CONFIG_FILE = Rails.root.join('config', 'initializers', 'observability', 'grafana_provision.yml')
  DASH_DIR    = Rails.root.join('config', 'initializers', 'observability', 'graphana')

  # Map Grafana dashboard UID → filename used in DASH_DIR (matches pre-existing naming convention)
  DASH_FILENAMES = {
    'rYdddlPWk' => 'node.dashboard.json',
    'L-0CZ_WVk' => 'rails.dashboard.json',
  }.freeze

  def initialize
    @cfg = {
      url:  ENV.fetch('GRAFANA_URL',  'https://graphana.caphive.com'),
      user: ENV.fetch('GRAFANA_USER', 'admin'),
      pass: ENV.fetch('GRAFANA_PASS', ''),
    }
    @spec = YAML.safe_load_file(CONFIG_FILE, symbolize_names: true)
    puts "Target: #{@cfg[:url]}"
  end

  def run_all
    provision_contact_points
    provision_notification_policy
    provision_alert_rules
    provision_dashboards
    provision_overview_dashboard
    puts "\nDone. Commit config/initializers/observability/ to version control."
  end

  # ── Contact points ──────────────────────────────────────────────────────────

  def provision_contact_points
    puts "\n=== Contact Points ==="
    existing = get('/api/v1/provisioning/contact-points')
    @spec[:contact_points].each do |cp|
      # Expand ${VAR_NAME} placeholders from ENV so secrets stay out of the YAML
      resolved = deep_expand_env(cp)
      found    = existing.find { |e| e['name'] == cp[:name].to_s }
      if found
        put("/api/v1/provisioning/contact-points/#{found['uid']}", resolved)
        puts "  Updated: #{cp[:name]}"
      else
        post('/api/v1/provisioning/contact-points', resolved)
        puts "  Created: #{cp[:name]}"
      end
    end
  end

  # Recursively expand ${VAR_NAME} in all string values from ENV.
  # Missing ENV vars expand to empty string (Grafana will accept it; you will see auth failures).
  def deep_expand_env(obj)
    case obj
    when Hash   then obj.transform_values { |v| deep_expand_env(v) }
    when Array  then obj.map { |v| deep_expand_env(v) }
    when String then obj.gsub(/\$\{([A-Z0-9_]+)\}/) { ENV[$1].to_s }
    else obj
    end
  end

  # ── Notification policy ─────────────────────────────────────────────────────

  def provision_notification_policy
    puts "\n=== Notification Policy ==="
    put('/api/v1/provisioning/policies', @spec[:notification_policy])
    puts "  Applied (receiver: #{@spec[:notification_policy][:receiver]})"
  end

  # ── Alert rules ─────────────────────────────────────────────────────────────

  def provision_alert_rules
    puts "\n=== Alert Rules ==="
    ds_uid     = datasource_uid
    folder_uid = ensure_folder(@spec[:alert_folder].to_s)
    puts "  Datasource UID: #{ds_uid}  |  Folder UID: #{folder_uid}"

    # GET /api/v1/provisioning/alert-rules returns 404 on this Grafana version.
    # Fetch all ruler namespaces (no folder path = no encoding issue), filter by folder name.
    folder_name  = @spec[:alert_folder].to_s
    all_ruler    = get('/api/ruler/grafana/api/v1/rules')
    folder_groups = (all_ruler.is_a?(Hash) ? (all_ruler[folder_name] || []) : [])
    existing_uids = folder_groups.flat_map do |group|
      (group['rules'] || []).filter_map { |r| r.dig('grafana_alert', 'uid') }
    end
    puts "  Found #{existing_uids.size} existing rules to delete"
    existing_uids.each do |uid|
      delete("/api/v1/provisioning/alert-rules/#{uid}")
      puts "  Deleted: #{uid}"
    end

    @spec[:alert_rules].each do |rule|
      payload = build_alert_rule(rule, folder_uid, ds_uid)
      result  = post('/api/v1/provisioning/alert-rules', payload)
      if result['uid']
        puts "  Created: #{rule[:title]}"
      else
        puts "  ERROR creating #{rule[:title]}: #{result.inspect}"
      end
    end
  end

  # ── Dashboards ──────────────────────────────────────────────────────────────

  def provision_dashboards
    puts "\n=== Dashboards ==="
    FileUtils.mkdir_p(DASH_DIR)

    @spec[:dashboards].each do |spec|
      uid  = spec[:uid].to_s
      data = get("/api/dashboards/uid/#{uid}")
      unless data['dashboard']
        puts "  SKIP #{uid}: not found on server"
        next
      end

      board = data['dashboard']
      puts "  Patching: #{board['title']} (#{uid})"

      (spec[:patches] || []).each do |patch|
        case patch.to_s
        when 'fix_disk_queries'        then fix_disk_queries!(board)
        when 'add_node_variable'       then add_template_variable!(board, node_variable)
        when 'add_controller_variable' then add_template_variable!(board, controller_variable)
        when 'add_roc_panels'          then add_roc_panels!(board)
        when 'add_rails_depth_panels'  then add_rails_depth_panels!(board)
        when 'add_mysql_depth_panels'  then add_mysql_depth_panels!(board)
        end
      end

      # Increment version so Grafana accepts the overwrite
      board['version'] = (board['version'].to_i + 1)

      result = post('/api/dashboards/db', {
        dashboard: board,
        folderId:  data.dig('meta', 'folderId') || 0,
        overwrite: true,
        message:   'grafana:provision rake task',
      })

      if result['status'] == 'success'
        puts "    Pushed OK (version #{result['version']})"
        # Save the applied board JSON for version control
        filename = DASH_FILENAMES[uid] || "#{uid}.json"
        File.write(DASH_DIR.join(filename), JSON.pretty_generate(board))
        puts "    Saved: config/initializers/observability/graphana/#{filename}"
      else
        puts "    ERROR: #{result.inspect}"
      end
    end
  end

  # Saves live dashboard JSON without modifying it — useful for initial snapshot
  def save_dashboards
    puts "\n=== Saving Dashboard Snapshots ==="
    FileUtils.mkdir_p(DASH_DIR)
    @spec[:dashboards].each do |spec|
      uid  = spec[:uid].to_s
      data = get("/api/dashboards/uid/#{uid}")
      next unless data['dashboard']
      filename = DASH_FILENAMES[uid] || "#{uid}.json"
      File.write(DASH_DIR.join(filename), JSON.pretty_generate(data['dashboard']))
      puts "  Saved: config/initializers/observability/graphana/#{filename} (#{data['dashboard']['title']})"
    end
  end

  private

  # ── Dashboard patch helpers ─────────────────────────────────────────────────

  # Strips mountpoint="/" from disk panel selectors.
  # Container nodes bind-mount root disk to /etc/hosts etc. so mountpoint="/" returns no data.
  # Unlike infra_report.rake (which uses max by(instance) for cross-node aggregation), here we
  # just remove the mountpoint filter so the $node variable still scopes results per node.
  def fix_disk_queries!(board)
    count = 0
    each_panel(board) do |panel|
      (panel['targets'] || []).each do |t|
        expr = t['expr'].to_s
        next unless expr.include?('node_filesystem') && expr.match?(/mountpoint=["']\/["']/)
        t['expr'] = expr
          .gsub(/,\s*mountpoint=["']\/["']/, '')   # strip ,mountpoint="/" (not first label)
          .gsub(/mountpoint=["']\/["']\s*,\s*/, '') # strip mountpoint="/"  , (first label)
          .gsub(/\{mountpoint=["']\/["']\}/, '{}')  # strip when only label
        count += 1
      end
    end
    puts "    fix_disk_queries: patched #{count} target(s)"
  end

  # $node — multi-select dropdown listing all node-exporter instances
  def node_variable
    {
      'name'        => 'node',
      'label'       => 'Node',
      'type'        => 'query',
      'datasource'  => { 'type' => 'prometheus' },
      'query'       => 'label_values(node_uname_info, instance)',
      'refresh'     => 2,   # refresh on time range change
      'includeAll'  => true,
      'allValue'    => '.+',
      'multi'       => true,
      'sort'        => 1,
      'hide'        => 0,
    }
  end

  # $controller — multi-select for Rails controller breakdown panels
  def controller_variable
    {
      'name'        => 'controller',
      'label'       => 'Controller',
      'type'        => 'query',
      'datasource'  => { 'type' => 'prometheus' },
      'query'       => 'label_values(ruby_http_requests_total, controller)',
      'refresh'     => 2,
      'includeAll'  => true,
      'allValue'    => '.+',
      'multi'       => true,
      'sort'        => 1,
      'hide'        => 0,
    }
  end

  def add_template_variable!(board, var)
    board['templating'] ||= {}
    board['templating']['list'] ||= []
    list = board['templating']['list']
    if list.any? { |v| v['name'] == var['name'] }
      # Variable already exists — leave it alone to avoid clobbering datasource uid,
      # query format, and other fields that Grafana needs in a specific structure.
      puts "    add_template_variable: $#{var['name']} already present, skipping"
    else
      list.unshift(var)
      puts "    add_template_variable: added $#{var['name']}"
    end
  end

  # Appends P95 latency, Puma thread saturation, and Sidekiq depth/latency panels.
  def add_rails_depth_panels!(board)
    panels = board['panels'] ||= []
    max_id = panels.map { |p| p['id'].to_i }.max.to_i

    if panels.any? { |p| p['title'].to_s.include?('P95 Latency') }
      puts "    add_rails_depth_panels: already present, skipping"
      return
    end

    new_panels = [
      ts_panel(id: max_id + 200, title: 'P95 Latency (ms)', x: 0,
        desc: '95th-percentile response time. 5% of users wait at least this long — ' \
              'invisible to the average but critical for perceived app speed.',
        expr: 'histogram_quantile(0.95,sum by(le)(rate(ruby_http_request_duration_seconds_bucket[5m])))*1000',
        legend: 'P95', unit: 'ms'),

      ts_panel(id: max_id + 201, title: 'Puma Thread Saturation (%)', x: 12,
        desc: 'Busy Puma threads / max threads. At 100% new requests queue at the OS level ' \
              'before Rails even sees them.',
        expr: 'avg(ruby_puma_busy_threads/ruby_puma_max_threads)*100',
        legend: 'saturation', unit: 'percent'),

      ts_panel(id: max_id + 202, title: 'Sidekiq Queue Depth (jobs)', x: 0,
        desc: 'Total jobs waiting in the Sidekiq enqueued queue. ' \
              'A growing queue means workers cannot keep pace.',
        expr: 'max(ruby_sidekiq_stats_enqueued)',
        legend: 'enqueued', unit: 'short'),

      ts_panel(id: max_id + 203, title: 'Sidekiq Queue Latency (s)', x: 12,
        desc: 'Age of the oldest unprocessed job. ' \
              'Spikes here mean workers are stuck or blocked on a slow resource.',
        expr: 'max(ruby_sidekiq_queue_latency)',
        legend: 'latency', unit: 's'),
    ]

    board['panels'] += new_panels
    puts "    add_rails_depth_panels: appended #{new_panels.size} panels (P95, Puma, Sidekiq depth/latency)"
  end

  # Appends InnoDB buffer pool miss rate, deadlocks, and aborted connection panels.
  def add_mysql_depth_panels!(board)
    panels = board['panels'] ||= []
    max_id = panels.map { |p| p['id'].to_i }.max.to_i

    if panels.any? { |p| p['title'].to_s.include?('InnoDB') }
      puts "    add_mysql_depth_panels: already present, skipping"
      return
    end

    new_panels = [
      ts_panel(id: max_id + 210, title: 'InnoDB Buffer Pool Miss Rate (%)', x: 0,
        desc: 'Cache miss rate — % of reads served from disk rather than RAM. ' \
              '>1% means MySQL is disk-bound; increase innodb_buffer_pool_size.',
        expr: 'max by(instance)(rate(mysql_global_status_innodb_buffer_pool_reads[5m])/' \
              'rate(mysql_global_status_innodb_buffer_pool_read_requests[5m]))*100',
        legend: '{{instance}}', unit: 'percent'),

      ts_panel(id: max_id + 211, title: 'MySQL Deadlocks (/min)', x: 12,
        desc: 'InnoDB deadlocks per minute. Even 1/min causes application retries ' \
              'and degraded write throughput.',
        expr: 'max by(instance)(rate(mysql_global_status_innodb_deadlocks[5m]))*60',
        legend: '{{instance}}', unit: 'short'),

      ts_panel(id: max_id + 212, title: 'MySQL Aborted Connections (/min)', x: 0,
        desc: 'Failed connection attempts per minute. High values indicate Rails pool ' \
              'timeout, wrong credentials, or max_connections exceeded.',
        expr: 'max by(instance)(rate(mysql_global_status_aborted_connects[5m]))*60',
        legend: '{{instance}}', unit: 'short'),
    ]

    board['panels'] += new_panels
    puts "    add_mysql_depth_panels: appended #{new_panels.size} panels (InnoDB miss, deadlocks, aborted)"
  end

  # Builds a Grafana timeseries panel hash. unit is a Grafana unit string (ms, percent, s, short).
  def ts_panel(id:, title:, desc:, expr:, legend:, x:, unit: nil, w: 12, y: 9999)
    ds_ref = { 'type' => 'prometheus', 'uid' => '${datasource}' }
    panel  = {
      'type'        => 'timeseries',
      'title'       => title,
      'description' => desc,
      'gridPos'     => { 'h' => 8, 'w' => w, 'x' => x, 'y' => y },
      'id'          => id,
      'datasource'  => ds_ref,
      'targets'     => [
        { 'datasource' => ds_ref, 'expr' => expr,
          'legendFormat' => legend, 'refId' => 'A' },
      ],
    }
    panel['fieldConfig'] = { 'defaults' => { 'unit' => unit }, 'overrides' => [] } if unit
    panel
  end

  # ── Overview dashboard ──────────────────────────────────────────────────────

  # Creates/updates the CapHive Overview dashboard: one stat panel per key metric,
  # colour-coded green/yellow/red matching alert rule thresholds.
  # All panels use instant queries so they always show the current value, not a time series.
  def provision_overview_dashboard
    puts "\n=== Overview Dashboard ==="
    ds_uid = datasource_uid
    board  = build_overview_dashboard(ds_uid)

    result = post('/api/dashboards/db', {
      dashboard: board,
      folderId:  0,
      overwrite: true,
      message:   'grafana:provision:overview_dashboard',
    })

    if result['status'] == 'success'
      puts "  Pushed OK — CapHive Overview (version #{result['version']})"
      FileUtils.mkdir_p(DASH_DIR)
      File.write(DASH_DIR.join('overview.dashboard.json'), JSON.pretty_generate(board))
      puts "  Saved: config/initializers/observability/graphana/overview.dashboard.json"
    else
      puts "  ERROR: #{result.inspect}"
    end
  end

  def build_overview_dashboard(ds_uid)
    ds_ref  = { 'type' => 'prometheus', 'uid' => ds_uid }
    panels  = []
    next_id = 1
    y       = 0

    # Each section: a row header followed by 4 stat panels (6 wide each = full 24-wide row)
    sections = [
      {
        title: 'App Servers',
        stats: [
          { title: 'CPU %',
            expr:   '100-(avg by(instance)(rate(node_cpu_seconds_total{mode="idle",instance!~"10.0.[34].*"}[5m]))*100)',
            legend: '{{instance}}', unit: 'percent', warn: 70,  crit: 90  },
          { title: 'Memory %',
            expr:   '(node_memory_MemTotal_bytes{instance!~"10.0.[34].*"}-node_memory_MemAvailable_bytes{instance!~"10.0.[34].*"})/node_memory_MemTotal_bytes{instance!~"10.0.[34].*"}*100',
            legend: '{{instance}}', unit: 'percent', warn: 70,  crit: 90  },
          { title: 'Disk %',
            expr:   'max by(instance)((node_filesystem_size_bytes{instance!~"10.0.[34].*",fstype!~"tmpfs|overlay",mountpoint!~"/etc/.*"}-node_filesystem_free_bytes{instance!~"10.0.[34].*",fstype!~"tmpfs|overlay",mountpoint!~"/etc/.*"})/node_filesystem_size_bytes{instance!~"10.0.[34].*",fstype!~"tmpfs|overlay",mountpoint!~"/etc/.*"}*100)',
            legend: '{{instance}}', unit: 'percent', warn: 70,  crit: 90  },
          { title: 'Inodes %',
            expr:   'max by(instance)((1-node_filesystem_files_free{instance!~"10.0.[34].*",fstype!~"tmpfs|overlay",mountpoint!~"/etc/.*"}/node_filesystem_files{instance!~"10.0.[34].*",fstype!~"tmpfs|overlay",mountpoint!~"/etc/.*"})*100)',
            legend: '{{instance}}', unit: 'percent', warn: 70,  crit: 90  },
        ],
      },
      {
        title: 'DB Servers',
        stats: [
          { title: 'DB Memory %',
            expr:   '(node_memory_MemTotal_bytes{instance=~"10.0.[34].*"}-node_memory_MemAvailable_bytes{instance=~"10.0.[34].*"})/node_memory_MemTotal_bytes{instance=~"10.0.[34].*"}*100',
            legend: '{{instance}}', unit: 'percent', warn: 85,  crit: 95  },
          { title: 'Connections %',
            expr:   'max by(instance)(mysql_global_status_threads_connected/mysql_global_variables_max_connections*100)',
            legend: '{{instance}}', unit: 'percent', warn: 60,  crit: 80  },
          { title: 'Replication Lag',
            expr:   'max by(instance)(mysql_slave_status_seconds_behind_master)',
            legend: '{{instance}}', unit: 's',       warn: 10,  crit: 30  },
          { title: 'Slow Queries/min',
            expr:   'sum by(instance)(rate(mysql_global_status_slow_queries[5m]))*60',
            legend: '{{instance}}', unit: 'short',   warn: 0.5, crit: 2   },
        ],
      },
      {
        title: 'MySQL Depth',
        stats: [
          { title: 'InnoDB Miss %',
            expr:   'max by(instance)(rate(mysql_global_status_innodb_buffer_pool_reads[5m])/rate(mysql_global_status_innodb_buffer_pool_read_requests[5m]))*100',
            legend: '{{instance}}', unit: 'percent', warn: 0.5, crit: 1   },
          { title: 'Deadlocks/min',
            expr:   'max by(instance)(rate(mysql_global_status_innodb_deadlocks[5m]))*60',
            legend: '{{instance}}', unit: 'short',   warn: 0.1, crit: 1   },
          { title: 'Aborted/min',
            expr:   'max by(instance)(rate(mysql_global_status_aborted_connects[5m]))*60',
            legend: '{{instance}}', unit: 'short',   warn: 2,   crit: 5   },
          { title: 'Zombie Sleep',
            expr:   'max by(instance)(mysql_info_schema_processlist_seconds{command="Sleep"})',
            legend: '{{instance}}', unit: 's',       warn: 300, crit: 1800 },
        ],
      },
      {
        title: 'Rails App',
        stats: [
          { title: '5xx Rate %',
            expr:   'sum(rate(ruby_http_requests_total{status=~"^5.*"}[5m]))/sum(rate(ruby_http_requests_total[5m]))*100',
            legend: '5xx',         unit: 'percent', warn: 1,    crit: 5   },
          { title: 'P95 Latency',
            expr:   'histogram_quantile(0.95,sum by(le)(rate(ruby_http_request_duration_seconds_bucket[5m])))*1000',
            legend: 'P95',         unit: 'ms',      warn: 1000, crit: 3000 },
          { title: 'Puma Threads %',
            expr:   'avg(ruby_puma_busy_threads/ruby_puma_max_threads)*100',
            legend: 'saturation',  unit: 'percent', warn: 70,   crit: 90  },
          { title: 'Web Memory (MB)',
            expr:   'avg(ruby_rss{type=~"web|puma_worker"})/1024/1024',
            legend: 'avg RSS',     unit: 'short',   warn: 400,  crit: 700 },
        ],
      },
      {
        title: 'Sidekiq',
        stats: [
          { title: 'Queue Depth',
            expr:   'max(ruby_sidekiq_stats_enqueued)',
            legend: 'jobs',    unit: 'short', warn: 50,  crit: 200 },
          { title: 'Queue Latency',
            expr:   'max(ruby_sidekiq_queue_latency)',
            legend: 'latency', unit: 's',     warn: 60,  crit: 300 },
          { title: 'Retry Queue',
            expr:   'max(ruby_sidekiq_stats_retry_size)',
            legend: 'jobs',    unit: 'short', warn: 5,   crit: 20  },
          { title: 'Dead Queue',
            expr:   'max(ruby_sidekiq_stats_dead_size)',
            legend: 'jobs',    unit: 'short', warn: 1,   crit: 5   },
        ],
      },
    ]

    sections.each do |section|
      panels << row_panel(id: next_id, title: section[:title], y: y)
      next_id += 1
      y        += 1

      section[:stats].each_with_index do |s, i|
        panels << stat_panel(id: next_id, ds_ref: ds_ref, x: i * 6, y: y, **s)
        next_id += 1
      end
      y += 4
    end

    {
      'uid'           => 'caphive-overview',
      'title'         => 'CapHive Overview',
      'tags'          => ['caphive', 'overview'],
      'timezone'      => 'browser',
      'schemaVersion' => 36,
      'version'       => 1,
      'refresh'       => '30s',  # auto-refresh every 30s — this is a live status board
      'panels'        => panels,
      'time'          => { 'from' => 'now-5m', 'to' => 'now' },
      'timepicker'    => {},
      'templating'    => { 'list' => [] },
      'annotations'   => {
        'list' => [
          # Built-in Grafana alerts annotation (hidden by default)
          {
            'builtIn'    => 1,
            'datasource' => { 'type' => 'grafana', 'uid' => '-- Grafana --' },
            'enable'     => true,
            'hide'       => true,
            'iconColor'  => 'rgba(0, 211, 255, 1)',
            'name'       => 'Annotations & Alerts',
            'type'       => 'dashboard',
          },
          # Deploy markers from Capistrano — shows vertical lines when deploys happened
          {
            'datasource' => { 'type' => 'grafana', 'uid' => '-- Grafana --' },
            'enable'     => true,
            'hide'       => false,
            'iconColor'  => '#5794F2',
            'name'       => 'Deploys',
            'type'       => 'tags',
            'tags'       => ['deploy'],
          },
        ],
      },
    }
  end

  # Builds a Grafana stat panel (single large number, background colour from thresholds).
  # unit is a Grafana unit string: percent, ms, s, short, bytes, etc.
  def stat_panel(id:, title:, expr:, legend:, unit:, warn:, crit:, x:, y:, ds_ref:, w: 6, h: 4)
    {
      'type'        => 'stat',
      'title'       => title,
      'gridPos'     => { 'h' => h, 'w' => w, 'x' => x, 'y' => y },
      'id'          => id,
      'datasource'  => ds_ref,
      'options'     => {
        'reduceOptions' => { 'calcs' => ['lastNotNull'], 'fields' => '', 'values' => false },
        'orientation'   => 'auto',
        'colorMode'     => 'background',
        'graphMode'     => 'none',
        'justifyMode'   => 'auto',
        'textMode'      => 'auto',
      },
      'fieldConfig' => {
        'defaults' => {
          'unit'       => unit,
          'color'      => { 'mode' => 'thresholds' },
          'thresholds' => {
            'mode'  => 'absolute',
            'steps' => [
              { 'color' => 'green',  'value' => nil  },
              { 'color' => 'yellow', 'value' => warn },
              { 'color' => 'red',    'value' => crit },
            ],
          },
          'mappings' => [],
        },
        'overrides' => [],
      },
      'targets' => [
        { 'datasource' => ds_ref, 'expr' => expr,
          'instant' => true, 'legendFormat' => legend, 'refId' => 'A' },
      ],
    }
  end

  # Grafana row panel — collapsible section header spanning the full 24-column width.
  def row_panel(id:, title:, y:)
    {
      'type'      => 'row',
      'title'     => title,
      'gridPos'   => { 'h' => 1, 'w' => 24, 'x' => 0, 'y' => y },
      'id'        => id,
      'collapsed' => false,
      'panels'    => [],
    }
  end

  # Appends two rate-of-change panels at the bottom of the dashboard.
  # Uses subquery syntax: deriv(expr[1h:5m]) * 3600 to get %/hr.
  def add_roc_panels!(board)
    panels  = board['panels'] ||= []
    max_id  = panels.map { |p| p['id'].to_i }.max.to_i
    if panels.any? { |p| p['title'].to_s.include?('Growth Rate') }
      puts "    add_roc_panels: already present, skipping"
      return
    end

    # Reference the dashboard's own $datasource variable so panels use the right datasource.
    # Include instance=~"$node" so panels respect the node filter variable.
    ds_ref = { 'type' => 'prometheus', 'uid' => '${datasource}' }

    disk_panel = {
      'type'        => 'timeseries',
      'title'       => 'Disk Growth Rate (Δ%/hr)',
      'description' => 'Rate of change of disk usage per hour via deriv() subquery. ' \
                       'Values >2%/hr indicate rapid disk consumption.',
      'gridPos'     => { 'h' => 8, 'w' => 12, 'x' => 0, 'y' => 9999 },
      'id'          => max_id + 100,
      'datasource'  => ds_ref,
      'targets'     => [
        {
          'datasource'   => ds_ref,
          'expr'         => 'deriv((max by(instance)(' \
                            '(node_filesystem_size_bytes{fstype!~"tmpfs|overlay",mountpoint!~"/etc/.*",instance=~"$node"}' \
                            '-node_filesystem_free_bytes{fstype!~"tmpfs|overlay",mountpoint!~"/etc/.*",instance=~"$node"})' \
                            '/node_filesystem_size_bytes{fstype!~"tmpfs|overlay",mountpoint!~"/etc/.*",instance=~"$node"}' \
                            '*100))[1h:5m])*3600',
          'legendFormat' => '{{instance}}',
          'refId'        => 'A',
        }
      ],
    }

    mem_panel = disk_panel.merge(
      'title'       => 'Memory Growth Rate (Δ%/hr)',
      'description' => 'Rate of change of memory usage per hour. ' \
                       'Persistent positive trend may indicate a memory leak.',
      'gridPos'     => { 'h' => 8, 'w' => 12, 'x' => 12, 'y' => 9999 },
      'id'          => max_id + 101,
      'targets'     => [
        {
          'datasource'   => ds_ref,
          'expr'         => 'deriv(((node_memory_MemTotal_bytes{instance=~"$node"}' \
                            '-node_memory_MemAvailable_bytes{instance=~"$node"})' \
                            '/node_memory_MemTotal_bytes{instance=~"$node"}' \
                            '*100)[1h:5m])*3600',
          'legendFormat' => '{{instance}}',
          'refId'        => 'A',
        }
      ],
    )

    board['panels'] += [disk_panel, mem_panel]
    puts "    add_roc_panels: appended Disk Growth Rate + Memory Growth Rate panels"
  end

  def each_panel(board, &block)
    (board['panels'] || []).each do |panel|
      # Row panels contain nested panels
      if panel['type'] == 'row'
        (panel['panels'] || []).each(&block)
      else
        block.call(panel)
      end
    end
  end

  # ── Alert rule builder ──────────────────────────────────────────────────────

  def build_alert_rule(rule, folder_uid, ds_uid)
    {
      orgID:      1,
      folderUID:  folder_uid,
      ruleGroup:  (rule[:group] || 'general').to_s,
      title:      rule[:title].to_s,
      condition:  'THRESHOLD',
      data: [
        # Query: evaluate the PromQL expression
        {
          refId:             'A',
          queryType:         '',
          relativeTimeRange: { from: 600, to: 0 },
          datasourceUid:     ds_uid,
          model: {
            datasource:   { type: 'prometheus', uid: ds_uid },
            expr:         rule[:expr].to_s,
            instant:      true,
            legendFormat: '__auto',
            refId:        'A',
          },
        },
        # Threshold expression: last(A) > threshold_gt
        {
          refId:             'THRESHOLD',
          queryType:         '__expr__',
          relativeTimeRange: { from: 0, to: 0 },
          datasourceUid:     '__expr__',
          model: {
            conditions: [
              {
                evaluator: { params: [rule[:threshold_gt]], type: 'gt' },
                operator:  { type: 'and' },
                query:     { params: ['A'] },
                reducer:   { params: [], type: 'last' },
                type:      'query',
              }
            ],
            datasource:  { type: '__expr__', uid: '__expr__' },
            expression:  'A',
            refId:       'THRESHOLD',
            type:        'classic_conditions',
          },
        },
      ],
      noDataState:  'NoData',
      execErrState: 'Error',
      for:          (rule[:for] || '5m').to_s,
      annotations:  { summary: rule[:summary].to_s },
      labels:       (rule[:labels] || {}).transform_keys(&:to_s),
      isPaused:     false,
    }
  end

  # ── Grafana API helpers ─────────────────────────────────────────────────────

  def datasource_uid
    @datasource_uid ||= begin
      sources = get('/api/datasources')
      id      = ENV.fetch('GRAFANA_DS_ID', '1')
      ds      = sources.find { |s| s['id'].to_s == id }
      raise "Datasource id=#{id} not found. Available: #{sources.map { |s| "#{s['id']}:#{s['name']}" }.join(', ')}" unless ds
      ds['uid']
    end
  end

  def ensure_folder(name)
    folders = get('/api/folders')
    if (found = folders.find { |f| f['title'] == name })
      return found['uid']
    end
    result = post('/api/folders', { title: name })
    raise "Failed to create folder '#{name}': #{result.inspect}" unless result['uid']
    puts "  Created folder: #{name} (#{result['uid']})"
    result['uid']
  end

  def get(path)
    req = Net::HTTP::Get.new(uri(path))
    auth!(req)
    res = http.request(req)
    JSON.parse(res.body)
  rescue => e
    warn "  GET #{path} failed: #{e.message}"
    {}
  end

  def post(path, body)
    req = Net::HTTP::Post.new(uri(path))
    auth!(req)
    req['Content-Type'] = 'application/json'
    req.body = body.to_json
    JSON.parse(http.request(req).body)
  rescue => e
    warn "  POST #{path} failed: #{e.message}"
    {}
  end

  def put(path, body)
    req = Net::HTTP::Put.new(uri(path))
    auth!(req)
    req['Content-Type'] = 'application/json'
    req.body = body.to_json
    JSON.parse(http.request(req).body)
  rescue => e
    warn "  PUT #{path} failed: #{e.message}"
    {}
  end

  def delete(path)
    req = Net::HTTP::Delete.new(uri(path))
    auth!(req)
    http.request(req)
  rescue => e
    warn "  DELETE #{path} failed: #{e.message}"
  end

  def uri(path)
    URI("#{@cfg[:url]}#{path}")
  end

  def auth!(req)
    req['Authorization'] = "Basic #{Base64.strict_encode64("#{@cfg[:user]}:#{@cfg[:pass]}")}"
  end

  def http
    @http ||= begin
      u = URI(@cfg[:url])
      h = Net::HTTP.new(u.host, u.port)
      h.use_ssl     = (u.scheme == 'https')
      h.read_timeout = 30
      h
    end
  end
end
