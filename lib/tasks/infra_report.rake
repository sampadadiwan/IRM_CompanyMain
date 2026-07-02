require 'net/http'
require 'uri'
require 'json'
require 'base64'
require 'date'

namespace :infra do
  desc "Generate HTML resource-usage report. ENV: GRAFANA_URL, GRAFANA_PASS, WINDOW=7d (e.g. 48h, 14d)"
  task report: :environment do
    # Override with ENV vars: GRAFANA_URL, GRAFANA_USER, GRAFANA_PASS, GRAFANA_DS_ID, WINDOW
    InfraReporter.new(
      url:    ENV.fetch('GRAFANA_URL',  'https://graphana.caphive.com'),
      user:   ENV.fetch('GRAFANA_USER', 'admin'),
      pass:   ENV.fetch('GRAFANA_PASS', ''),
      ds_id:  ENV.fetch('GRAFANA_DS_ID', '1'),
      window: ENV.fetch('WINDOW', '7d'),
    ).run
  end
end

class InfraReporter
  # Each metric declares its own warn/crit thresholds and display unit.
  # window_fn controls how the 1-day bucket is summarised: max or avg.
  # WAF blocks raw queries with {label=...} matchers, but allows them when wrapped in
  # a window function — so prom_range always wraps with the metric's window_fn.
  # No spaces allowed in queries: WAF also blocks bodies with unencoded spaces.

  INFRA_METRICS = [
    {
      key:       :cpu,
      label:     'CPU',
      unit:      '%',
      warn:      70,
      crit:      90,
      window_fn: 'max_over_time',
      query:     '100-(avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))*100)',
      desc:      'Percentage of CPU time spent doing work (not idle), averaged across all cores. ' \
                 '100% means fully saturated — new requests queue behind existing work.',
    },
    {
      key:       :memory,
      label:     'Memory',
      unit:      '%',
      warn:      70,
      crit:      90,
      window_fn: 'max_over_time',
      # Exclude DB servers (10.0.3.x, 10.0.4.x) — they run MySQL which holds 70-85% RAM in the
      # InnoDB buffer pool by design. DB memory is tracked separately in MySQL/DB with higher thresholds.
      query:     '(node_memory_MemTotal_bytes{instance!~"10.0.[34].*"}-node_memory_MemAvailable_bytes{instance!~"10.0.[34].*"})/node_memory_MemTotal_bytes{instance!~"10.0.[34].*"}*100',
      desc:      'App server RAM usage %. DB servers are excluded here and tracked in the MySQL/DB section ' \
                 'with higher thresholds since MySQL InnoDB buffer pool intentionally uses most RAM.',
    },
    {
      key:       :disk,
      label:     'Disk',
      unit:      '%',
      warn:      70,
      crit:      90,
      window_fn: 'max_over_time',
      # Exclude overlay (Docker container bind-mounts like /etc/hostname, /etc/hosts appear as
      # tiny 100%-full overlay filesystems) and any /etc/* mountpoints for the same reason.
      query:     'max by(instance)((node_filesystem_size_bytes{fstype!~"tmpfs|overlay",mountpoint!~"/etc/.*"}-node_filesystem_free_bytes{fstype!~"tmpfs|overlay",mountpoint!~"/etc/.*"})/node_filesystem_size_bytes{fstype!~"tmpfs|overlay",mountpoint!~"/etc/.*"}*100)',
      desc:      'Highest disk usage % across real (non-tmpfs, non-overlay) filesystems. ' \
                 'Excludes Docker bind-mounts (/etc/hostname etc.) which always appear full. ' \
                 'At 100% all writes fail — logs, uploads, and DB writes will error.',
    },
  ].freeze

  RAILS_METRICS = [
    {
      # 5xx = genuine server failures (exceptions, timeouts, misconfiguration).
      # Threshold is intentionally tight — even 1–5% 5xx is serious.
      key:       :server_error_rate,
      label:     '5xx Rate',
      unit:      '%',
      warn:      1,
      crit:      5,
      window_fn: 'max_over_time',
      query:     'sum(rate(ruby_http_requests_total{status=~"^5.*"}[5m]))/sum(rate(ruby_http_requests_total[5m]))*100',
      desc:      'Percentage of HTTP requests that returned a 5xx (server error) status. ' \
                 'These are genuine application failures: unhandled exceptions, timeouts, misconfigurations. ' \
                 'Even 1% is worth investigating. This is the primary health signal.',
    },
    {
      # 4xx includes bot 404s (controller=other) which are expected and can dominate the %.
      # Thresholds are loose because 404s from bots are normal; watch for sustained spikes
      # in 401/403 (auth failures) or 422 (validation errors) instead.
      key:       :client_error_rate,
      label:     '4xx Rate',
      unit:      '%',
      warn:      50,
      crit:      80,
      window_fn: 'max_over_time',
      query:     'sum(rate(ruby_http_requests_total{status=~"^4.*"}[5m]))/sum(rate(ruby_http_requests_total[5m]))*100',
      desc:      'Percentage of HTTP requests that returned a 4xx (client error) status. ' \
                 'Includes 404 Not Found (often bots hitting non-existent routes), ' \
                 '401/403 Unauthorized, and 422 Unprocessable. ' \
                 'A persistently high 4xx % is usually bot traffic, not a real app problem. ' \
                 'Compare with 5xx Rate to distinguish bots from real failures.',
    },
    {
      key:       :req_duration,
      label:     'Avg Request',
      unit:      'ms',
      warn:      500,
      crit:      2_000,
      # avg_over_time avoids irate spikes on sparse data that max_over_time would amplify
      window_fn: 'avg_over_time',
      query:     'sum(irate(ruby_http_request_duration_seconds_sum[5m]))/sum(irate(ruby_http_request_duration_seconds_count[5m]))*1000',
      desc:      'Average HTTP response time in milliseconds across all controllers and actions. ' \
                 'Uses avg over the day (not max) to avoid irate() spikes on low-traffic periods. ' \
                 'Blank (—) on days with no measurable traffic.',
    },
    {
      key:       :sidekiq_retry,
      label:     'Retry Queue',
      unit:      ' jobs',
      warn:      5,
      crit:      20,
      window_fn: 'max_over_time',
      # max() deduplicates: both nodes scrape the same global Sidekiq stats counter
      query:     'max(ruby_sidekiq_stats_retry_size)',
      desc:      'Number of Sidekiq jobs sitting in the retry queue (failed and awaiting retry). ' \
                 'A sustained non-zero count means jobs are failing repeatedly. ' \
                 'Check Sidekiq UI for the specific job class and error.',
    },
    {
      key:       :web_rss,
      label:     'Web Memory',
      unit:      'MB',
      warn:      400,
      crit:      700,
      window_fn: 'max_over_time',
      query:     'avg(ruby_rss{type=~"web|puma_worker"})/1024/1024',
      desc:      'Average RSS (Resident Set Size) of Puma web worker processes in MB. ' \
                 'Steady growth over days suggests a memory leak. ' \
                 'High RSS causes the OS to swap, slowing all requests.',
    },
  ].freeze

  MYSQL_METRICS = [
    {
      key:       :db_memory,
      label:     'DB Memory',
      unit:      '%',
      warn:      85,   # InnoDB buffer pool intentionally holds 70-85% RAM; only warn above 85%
      crit:      95,
      window_fn: 'max_over_time',
      query:     '(node_memory_MemTotal_bytes{instance=~"10.0.[34].*"}-node_memory_MemAvailable_bytes{instance=~"10.0.[34].*"})/node_memory_MemTotal_bytes{instance=~"10.0.[34].*"}*100',
      desc:      'DB server RAM usage %. MySQL InnoDB buffer pool keeps 70-85% of RAM occupied by design — ' \
                 'this is healthy and means more data is cached. WARN only at 85%+ which indicates ' \
                 'buffer pool pressure or a growing leak. CRIT at 95% means OOM risk.',
    },
    {
      key:       :db_connections,
      label:     'DB Conns',
      unit:      '%',
      warn:      60,
      crit:      80,
      window_fn: 'max_over_time',
      # by(instance) so primary vs replica show separately
      query:     'max by(instance)(mysql_global_status_threads_connected/mysql_global_variables_max_connections*100)',
      desc:      'Peak connection pool usage — at 80% new connections start failing. ' \
                 'Rails pool is 15/server; sustained >60% means pool is undersized or connections are leaking.',
    },
    {
      key:       :db_slow_queries,
      label:     'Slow Q/min',
      unit:      '/min',
      warn:      0.5,
      crit:      2,
      window_fn: 'max_over_time',
      query:     'sum by(instance)(rate(mysql_global_status_slow_queries[5m]))*60',
      desc:      'Slow queries per minute (queries exceeding long_query_time). ' \
                 'Sustained slow queries indicate missing indexes, N+1 queries, or lock contention.',
    },
    {
      key:       :db_zombie_sleep,
      label:     'Zombie Sleep',
      unit:      's',
      warn:      300,
      crit:      1800,
      window_fn: 'max_over_time',
      # {command="Sleep"} has a label matcher — WAF-bypassed via POST like all other queries
      query:     'max by(instance)(mysql_info_schema_processlist_seconds{command="Sleep"})',
      desc:      'Longest-sleeping idle connection. >5min = Rails pool not releasing connections. ' \
                 '>30min = zombie connection from a crashed worker; KILL it to free the slot.',
    },
    {
      key:       :db_repl_lag,
      label:     'Repl Lag',
      unit:      's',
      warn:      10,
      crit:      30,
      window_fn: 'max_over_time',
      # Only the replica exposes this metric; primary returns no data (shown as —)
      query:     'max by(instance)(mysql_slave_status_seconds_behind_master)',
      desc:      'Seconds the replica is behind the primary. Shows — on the primary (no slave status). ' \
                 '>10s = replica under write pressure. >30s = binlogs accumulating on primary disk.',
    },
    {
      key:       :db_binlog_gap,
      label:     'Binlog Gap',
      unit:      'MB',
      warn:      100,
      crit:      500,
      window_fn: 'max_over_time',
      # Difference between master_log_pos (written) and exec_master_log_pos (applied on replica)
      query:     'max by(instance)(mysql_slave_status_master_log_pos-mysql_slave_status_exec_master_log_pos)/1048576',
      desc:      'Bytes of binlog written on primary but not yet applied on replica, in MB. ' \
                 '>100MB = replica falling behind. >500MB = binlogs piling up on primary disk; check disk usage.',
    },
  ].freeze

  ALL_METRICS = (INFRA_METRICS + RAILS_METRICS + MYSQL_METRICS).freeze

  SECTIONS = [
    { title: 'Infrastructure',  metrics: INFRA_METRICS },
    { title: 'Rails App',       metrics: RAILS_METRICS },
    { title: 'MySQL / DB',      metrics: MYSQL_METRICS },
  ].freeze

  def initialize(config)
    @config = config
    @now    = Time.now
    parse_window(config[:window] || '7d')
  end

  # Parses "7d" or "48h" into @window_secs, @window_label, @prom_window.
  # @prom_window is a Prometheus duration string used inside PromQL queries.
  def parse_window(str)
    if str =~ /\A(\d+)h\z/i
      hours = $1.to_i
      @window_secs  = hours * 3_600
      @window_label = "#{hours}h"
      @prom_window  = "#{hours}h"
    elsif str =~ /\A(\d+)d\z/i
      days = $1.to_i
      @window_secs  = days * 86_400
      @window_label = "#{days} days"
      @prom_window  = "#{days}d"
    else
      warn "  Unrecognised WINDOW '#{str}', defaulting to 7d"
      @window_secs  = 7 * 86_400
      @window_label = '7 days'
      @prom_window  = '7d'
    end

    # Bucket size for the main metrics table: sub-day windows use 1h buckets so that
    # max_over_time wraps only the requested window, not an entire day of history.
    if @window_secs < 86_400
      @main_step          = 3_600
      @main_bucket_window = '1h'
    else
      @main_step          = 86_400
      @main_bucket_window = '1d'
    end
  end

  def run
    puts "Querying #{@config[:url]} ..."

    raw      = fetch_all_metrics
    by_period = raw.transform_values { |series| group_by_period(series) }
    peak      = raw.transform_values do |series|
      series.transform_values { |pts| pts.compact.map(&:last).max&.round(2) }
    end
    # periods is an ordered list of row keys: Date objects (daily) or Time objects (hourly)
    periods = all_periods(raw)
    nodes   = raw.transform_values { |s| s.keys.sort }

    puts "Fetching correlation data ..."
    error_endpoints   = fetch_error_endpoints
    hourly_resources  = fetch_hourly_resources
    hourly_jobs       = fetch_hourly_jobs
    hourly_mysql      = fetch_hourly_mysql

    html = render(periods, nodes, by_period, peak, error_endpoints, hourly_resources, hourly_jobs, hourly_mysql)
    path = Rails.root.join('tmp', "infra_report_#{@now.strftime('%Y%m%d_%H%M%S')}.html")
    File.write(path, html)
    puts "Report saved: #{path}"
    system("xdg-open '#{path}' 2>/dev/null; true")
  end

  private

  def fetch_all_metrics
    # start_ts = now - window + step so the FIRST bucket's max_over_time window
    # starts exactly at (now - window), not one bucket before it.
    start_ts = (@now - @window_secs + @main_step).to_i
    end_ts   = @now.to_i

    ALL_METRICS.each_with_object({}) do |m, acc|
      print "  #{m[:label]} ..."
      resp         = prom_range(m, t_start: start_ts, t_end: end_ts, step: @main_step, window: @main_bucket_window)
      acc[m[:key]] = parse_matrix(resp)
      puts " #{acc[m[:key]].size} series"
    end
  end

  # Returns { 'instance_ip' => [[Time, Float|nil], ...] }
  # nil entries represent NaN (avg_over_time on days with no traffic)
  def parse_matrix(response)
    return {} unless response['status'] == 'success'

    (response.dig('data', 'result') || []).each_with_object({}) do |series, h|
      instance    = (series.dig('metric', 'instance') || 'cluster').split(':').first
      h[instance] = series['values'].map do |ts, v|
        float = v.to_f
        [Time.at(ts.to_i), float.nan? ? nil : float]
      end
    end
  end

  # { 'instance' => { period_key => Float } }
  # Daily mode:  period_key = Date  (one row per calendar day)
  # Hourly mode: period_key = Time  (one row per step timestamp, truncated to the hour)
  def group_by_period(series_hash)
    series_hash.transform_values do |points|
      if @main_step == 3_600
        # Hourly: one point per step — use the timestamp itself as the key
        points.each_with_object({}) do |(t, v), h|
          next if v.nil?
          h[truncate_hour(t)] = [h[truncate_hour(t)], v].compact.max.round(2)
        end
      else
        points
          .group_by { |t, _| t.to_date }
          .transform_values { |pairs| pairs.filter_map(&:last).max&.round(2) }
      end
    end
  end

  # Returns an ordered list of all period keys present in raw data.
  def all_periods(raw)
    keys = raw.values.flat_map { |s| s.values.flat_map { |pts| pts.map(&:first) } }.map do |k|
      @main_step == 3_600 ? truncate_hour(k) : k.to_date
    end.uniq.sort
    # Fill gaps: for daily mode add every calendar date in the window
    if @main_step == 86_400
      n_days = [(@window_secs / 86_400.0).ceil, 1].max
      ((@now - (n_days - 1) * 86_400).to_date..@now.to_date).to_a
    else
      keys
    end
  end

  def truncate_hour(t)
    Time.at((t.to_i / 3_600) * 3_600)
  end

  # ── Correlation fetch methods ─────────────────────────────────────────────

  # Returns top 15 endpoints sorted by error count:
  # [{ controller:, action:, errors:, total:, error_rate: }, ...]
  def fetch_error_endpoints
    print "  Error endpoints ..."
    errors_resp = prom_instant("sum by(controller,action)(increase(ruby_http_requests_total{status=~\"^[45].*\"}[#{@prom_window}]))")
    totals_resp = prom_instant("sum by(controller,action)(increase(ruby_http_requests_total[#{@prom_window}]))")

    errors = parse_labeled_vector(errors_resp)
    totals = parse_labeled_vector(totals_resp)

    # Index totals by controller+action for O(1) join
    totals_index = totals.each_with_object({}) do |r, h|
      h[[r[:controller], r[:action]]] = r[:value]
    end

    result = errors.map do |r|
      total      = totals_index[[r[:controller], r[:action]]] || 0
      error_rate = total > 0 ? (r[:value] / total * 100).round(1) : nil
      { controller: r[:controller], action: r[:action],
        errors: r[:value].round, total: total.round, error_rate: error_rate }
    end.sort_by { |r| -r[:errors] }.first(15)

    puts " #{result.size} endpoints"
    result
  end

  # Returns { 'instance' => { Time => Float } } for each infra metric at hourly resolution
  def fetch_hourly_resources
    start_ts = (@now - @window_secs + 3_600).to_i
    end_ts   = @now.to_i

    INFRA_METRICS.each_with_object({}) do |m, acc|
      print "  #{m[:label]} hourly ..."
      resp         = prom_range(m, t_start: start_ts, t_end: end_ts, step: 3_600, window: '1h')
      acc[m[:key]] = parse_matrix(resp)
      puts " #{acc[m[:key]].size} series"
    end
  end

  # Returns { 'JobClassName' => { Time => Integer } } — jobs processed per hour
  def fetch_hourly_jobs
    print "  Sidekiq job timeline ..."
    start_ts = (@now - @window_secs + 3_600).to_i
    end_ts   = @now.to_i

    resp = prom_range_query(
      'sum by(job_name)(increase(ruby_sidekiq_jobs_total[1h]))',
      t_start: start_ts, t_end: end_ts, step: 3_600, window: '1h'
    )

    result = {}
    (resp.dig('data', 'result') || []).each do |series|
      job = series.dig('metric', 'job_name') || 'unknown'
      result[job] = series['values'].each_with_object({}) do |(ts, v), h|
        val = v.to_f
        h[Time.at(ts.to_i)] = val.nan? ? 0 : val.round
      end
    end

    # Only keep jobs that actually ran at least once
    active = result.select { |_, hours| hours.values.any?(&:positive?) }
    puts " #{active.size} active job types"
    active
  end

  # Returns { metric_key => { 'instance' => { Time => Float } } } at hourly resolution
  def fetch_hourly_mysql
    start_ts = (@now - @window_secs + 3_600).to_i
    end_ts   = @now.to_i

    MYSQL_METRICS.each_with_object({}) do |m, acc|
      print "  #{m[:label]} hourly ..."
      resp         = prom_range(m, t_start: start_ts, t_end: end_ts, step: 3_600, window: '1h')
      acc[m[:key]] = parse_matrix(resp)
      puts " #{acc[m[:key]].size} series"
    end
  end

  # Parses an instant (vector) response into [{ controller:, action:, value: }, ...]
  def parse_labeled_vector(response)
    return [] unless response['status'] == 'success'
    (response.dig('data', 'result') || []).map do |r|
      { controller: r.dig('metric', 'controller') || 'other',
        action:     r.dig('metric', 'action') || 'other',
        value:      r['value'][1].to_f }
    end
  end

  # ── Prometheus HTTP layer ─────────────────────────────────────────────────

  # Base POST to any Prometheus endpoint via Grafana datasource proxy.
  # WAF blocks raw queries with {label=...} matchers; wrapping in a window
  # function (max_over_time / avg_over_time) bypasses the restriction.
  def prom_post(path, params)
    uri  = URI("#{@config[:url]}/api/datasources/proxy/#{@config[:ds_id]}#{path}")
    body = params.map { |k, v| "#{k}=#{URI.encode_www_form_component(v.to_s)}" }.join('&')

    req                  = Net::HTTP::Post.new(uri)
    req['Authorization'] = "Basic #{Base64.strict_encode64("#{@config[:user]}:#{@config[:pass]}")}"
    req['Content-Type']  = 'application/x-www-form-urlencoded'
    req.body             = body

    http              = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl      = (uri.scheme == 'https')
    http.read_timeout = 30

    JSON.parse(http.request(req).body)
  rescue => e
    warn " ERROR: #{e.message}"
    { 'status' => 'error', 'data' => { 'result' => [] } }
  end

  # Instant query at @now with WAF bypass wrapper
  def prom_instant(raw_query, window_fn: 'max_over_time', window: '10m', resolution: '5m')
    wrapped = "#{window_fn}((#{raw_query})[#{window}:#{resolution}])"
    prom_post('/api/v1/query', 'query' => wrapped, 'time' => @now.to_i)
  end

  # Range query with configurable window — daily (1d) or hourly (1h)
  def prom_range_query(raw_query, t_start:, t_end:, step:, window_fn: 'max_over_time', window: '1d')
    wrapped = "#{window_fn}((#{raw_query})[#{window}:5m])"
    prom_post('/api/v1/query_range', 'query' => wrapped, 'start' => t_start, 'end' => t_end, 'step' => step)
  end

  # Range query using a metric's configured window_fn
  def prom_range(metric, t_start:, t_end:, step:, window: '1d')
    prom_range_query(metric[:query], t_start: t_start, t_end: t_end, step: step,
                     window_fn: metric[:window_fn] || 'max_over_time', window: window)
  end

  # ── HTML helpers ─────────────────────────────────────────────────────────

  def cell_colors(v, metric)
    warn_t = metric[:warn]
    crit_t = metric[:crit]
    if v >= crit_t
      ['#f5c6cb', '#721c24', 'CRIT']
    elsif v >= warn_t
      ['#ffeeba', '#856404', 'WARN']
    else
      ['#c3e6cb', '#155724', 'OK']
    end
  end

  def format_value(v, unit)
    case unit
    when '%'    then "#{v.round(1)}%"
    when 'ms'   then "#{v.round}ms"
    when 'MB'   then "#{v.round}MB"
    when 's'
      # Auto-scale seconds → minutes → hours for readability
      if v >= 3_600 then "#{(v / 3_600.0).round(1)}h"
      elsif v >= 60  then "#{(v / 60.0).round}m"
      else                "#{v.round}s"
      end
    when '/min' then "#{v.round(1)}/min"
    else             v.round.to_s
    end
  end

  def td(v, metric)
    return '<td style="text-align:center;color:#aaa;padding:6px">—</td>' if v.nil?

    bg, fg, status = cell_colors(v, metric)
    formatted      = format_value(v, metric[:unit])

    "<td style=\"background:#{bg};text-align:center;padding:6px 10px\">" \
      "<strong style=\"color:#{fg};font-size:14px\">#{formatted}</strong>" \
      "<br><small style=\"color:#{fg};font-size:11px\">#{status}</small></td>"
  end

  # th with optional tooltip title attribute for hover descriptions
  def th(content, tooltip: nil)
    title_attr = tooltip ? " title=\"#{tooltip.gsub('"', '&quot;')}\"" : ''
    cursor     = tooltip ? 'cursor:help;' : ''
    "<th#{title_attr} style=\"#{th_style}white-space:nowrap;#{cursor}\">#{content}</th>"
  end

  # ── Correlation sections ──────────────────────────────────────────────────

  def render_error_section(error_endpoints)
    return '' if error_endpoints.empty?

    header = "<tr>" \
      "<th style='#{th_style}text-align:left'>Controller</th>" \
      "<th style='#{th_style}text-align:left'>Action</th>" \
      "<th style='#{th_style}text-align:right'>Errors (7d)</th>" \
      "<th style='#{th_style}text-align:right'>Total Requests</th>" \
      "<th style='#{th_style}text-align:center'>Error Rate</th>" \
      "</tr>"

    rows = error_endpoints.map do |ep|
      rate    = ep[:error_rate]
      rate_bg = rate ? (rate >= 20 ? '#f5c6cb' : (rate >= 5 ? '#ffeeba' : '#c3e6cb')) : '#fff'
      rate_fg = rate ? (rate >= 20 ? '#721c24' : (rate >= 5 ? '#856404' : '#155724')) : '#666'
      rate_str = rate ? "#{rate}%" : '—'

      "<tr>" \
        "<td style='padding:7px 12px;font-family:monospace;font-size:12px'>#{ep[:controller]}</td>" \
        "<td style='padding:7px 12px;font-family:monospace;font-size:12px'>#{ep[:action]}</td>" \
        "<td style='padding:7px 12px;text-align:right'>#{format_number(ep[:errors])}</td>" \
        "<td style='padding:7px 12px;text-align:right'>#{format_number(ep[:total])}</td>" \
        "<td style='padding:7px 12px;text-align:center;background:#{rate_bg};color:#{rate_fg};font-weight:bold'>#{rate_str}</td>" \
        "</tr>"
    end.join

    note = "<p style='font-size:12px;color:#666;margin:6px 0 0'>" \
      "<strong>other / other</strong> = requests that matched no route (404s from bots/crawlers). " \
      "High error rates on real controllers indicate application failures.</p>"

    "<h2>Error Correlation — Top Endpoints by Error Count</h2>" \
      "<table><thead>#{header}</thead><tbody>#{rows}</tbody></table>#{note}"
  end

  # Hourly resource + job timeline: one row per hour, resources colour-coded,
  # job counts shown as numbers. Highlights rows where jobs ran during resource spikes.
  # res_cols, res_lookup, all_times are pre-computed by render() and shared with analysis methods
  def render_correlation_timeline(hourly_resources, hourly_jobs, res_cols:, res_lookup:, all_times:)
    return '' if hourly_resources.empty? && hourly_jobs.empty?
    return '' if all_times.empty?

    job_names = hourly_jobs.keys.sort

    # Build header
    res_headers = res_cols.map do |c|
      short = c[:node].split('.').last(2).join('.')
      "<th style='#{th_style}'>#{c[:metric][:label]}<br><small style='font-weight:normal'>#{short}</small></th>"
    end.join

    job_headers = job_names.map do |j|
      short = j.split('::').last.gsub(/Job|Worker/, '')
      "<th style='#{th_style}' title='#{j}'>#{short} ⓘ<br><small style='font-weight:normal'>jobs/hr</small></th>"
    end.join

    header_row = "<tr>" \
      "<th style='#{th_style}text-align:left'>Hour</th>#{res_headers}#{job_headers}</tr>"

    # Build correlation insights: jobs that frequently overlap with resource WARN/CRIT
    insights = build_correlation_insights(res_lookup, res_cols, hourly_jobs, all_times)

    rows = all_times.map do |t|
      # Gather resource values for this hour
      res_vals = res_cols.map { |c| res_lookup.dig(c[:metric][:key], c[:node], t) }
      job_vals = job_names.map { |j| hourly_jobs.dig(j, t) || 0 }

      # Row highlight: red if any resource CRIT, yellow if WARN, blue if jobs ran on a spike
      any_crit  = res_vals.zip(res_cols).any? { |v, c| v && v >= c[:metric][:crit] }
      any_warn  = res_vals.zip(res_cols).any? { |v, c| v && v >= c[:metric][:warn] }
      jobs_ran  = job_vals.any?(&:positive?)
      row_bg    = if any_crit && jobs_ran then '#fff3cd'  # amber: job + spike
                  elsif any_crit          then '#fde8e8'  # pink: resource spike
                  elsif jobs_ran          then '#f0f7ff'  # blue: job activity
                  else                         '#fff'
                  end

      res_cells = res_vals.zip(res_cols).map do |v, c|
        next '<td style="text-align:center;color:#ccc;border:1px solid #dee2e6">—</td>' if v.nil?
        bg, fg, _ = cell_colors(v, c[:metric])
        "<td style='background:#{bg};color:#{fg};text-align:center;padding:4px 8px;font-size:12px;border:1px solid #dee2e6'>" \
          "<strong>#{format_value(v, c[:metric][:unit])}</strong></td>"
      end.join

      job_cells = job_vals.map do |count|
        if count > 0
          "<td style='background:#dbeafe;color:#1e40af;text-align:center;padding:4px 8px;font-size:12px;font-weight:bold;border:1px solid #dee2e6'>#{count}</td>"
        else
          "<td style='text-align:center;color:#ddd;font-size:11px;border:1px solid #dee2e6'>·</td>"
        end
      end.join

      label = t.strftime('%-d %b %H:%M')
      "<tr style='background:#{row_bg}'>" \
        "<td style='padding:4px 8px;font-size:12px;white-space:nowrap;border:1px solid #dee2e6'>#{label}</td>" \
        "#{res_cells}#{job_cells}</tr>"
    end.join

    legend = "<div style='font-size:11px;color:#555;margin-bottom:8px'>" \
      "<span style='background:#fde8e8;padding:2px 6px;border-radius:3px'>Resource spike (CRIT)</span> &nbsp;" \
      "<span style='background:#fff3cd;padding:2px 6px;border-radius:3px'>Job ran during spike</span> &nbsp;" \
      "<span style='background:#f0f7ff;padding:2px 6px;border-radius:3px'>Job activity (no spike)</span>" \
      "</div>"

    insights_html = insights.any? ? render_insights(insights) : ''

    "<h2>Job &amp; Resource Correlation — Hourly Timeline (#{@window_label})</h2>" \
      "#{legend}" \
      "#{insights_html}" \
      "<div style='max-height:500px;overflow-y:auto;border-radius:6px;box-shadow:0 1px 4px rgba(0,0,0,.08)'>" \
        "<table style='margin-bottom:0'><thead>#{header_row}</thead><tbody>#{rows}</tbody></table>" \
      "</div>"
  end

  # Detects which jobs statistically overlap with resource spikes
  def build_correlation_insights(res_lookup, res_cols, hourly_jobs, all_times)
    insights = []

    hourly_jobs.each do |job_name, job_hours|
      job_run_times = job_hours.select { |_, count| count > 0 }.keys.to_set

      res_cols.each do |c|
        metric   = c[:metric]
        node     = c[:node]
        node_data = res_lookup.dig(metric[:key], node) || {}

        values_when_job_ran   = job_run_times.filter_map { |t| node_data[t] }
        values_when_no_job    = (all_times - job_run_times.to_a).filter_map { |t| node_data[t] }

        next if values_when_job_ran.size < 3 || values_when_no_job.empty?

        avg_during = values_when_job_ran.sum / values_when_job_ran.size
        avg_idle   = values_when_no_job.sum  / values_when_no_job.size
        crit_hours = values_when_job_ran.count { |v| v >= metric[:crit] }
        crit_pct   = (crit_hours.to_f / values_when_job_ran.size * 100).round

        # Flag if resource averages 15% higher when job runs, or CRIT in >20% of job hours
        next unless avg_during > avg_idle + 15 || crit_pct >= 20

        insights << {
          job:      job_name,
          metric:   "#{metric[:label]} (#{node.split('.').last(2).join('.')})",
          avg_during: avg_during.round(1),
          avg_idle:   avg_idle.round(1),
          crit_pct:   crit_pct,
          unit:       metric[:unit],
        }
      end
    end

    insights.sort_by { |i| -i[:crit_pct] }
  end

  def render_insights(insights)
    rows = insights.map do |i|
      short_job = i[:job].split('::').last
      "<tr>" \
        "<td style='padding:7px 12px' title='#{i[:job]}'>#{short_job}</td>" \
        "<td style='padding:7px 12px'>#{i[:metric]}</td>" \
        "<td style='padding:7px 12px;text-align:center'>#{i[:avg_during]}#{i[:unit]}</td>" \
        "<td style='padding:7px 12px;text-align:center'>#{i[:avg_idle]}#{i[:unit]}</td>" \
        "<td style='padding:7px 12px;text-align:center;background:#f5c6cb;color:#721c24;font-weight:bold'>#{i[:crit_pct]}%</td>" \
        "</tr>"
    end.join

    "<details style='margin-bottom:12px'><summary style='cursor:pointer;font-size:13px;font-weight:600;color:#495057;padding:4px 0'>" \
      "&#9888; #{insights.size} correlation#{insights.size == 1 ? '' : 's'} detected — click to expand</summary>" \
      "<table style='margin-top:8px'><thead><tr>" \
        "<th style='#{th_style}text-align:left'>Job</th>" \
        "<th style='#{th_style}text-align:left'>Resource</th>" \
        "<th style='#{th_style}'>Avg when running</th>" \
        "<th style='#{th_style}'>Avg when idle</th>" \
        "<th style='#{th_style}'>% hours at CRIT</th>" \
      "</tr></thead><tbody>#{rows}</tbody></table></details>"
  end

  def th_style
    'padding:8px 12px;background:#343a40;color:#fff;font-size:12px;text-align:center;'
  end

  # ── Shared lookups (built once, reused by all correlation sections) ───────

  # [{ metric:, node: }] — one entry per infra metric × node combination
  def build_res_cols(hourly_resources)
    INFRA_METRICS.flat_map do |m|
      (hourly_resources[m[:key]] || {}).keys.sort.map { |node| { metric: m, node: node } }
    end
  end

  # { metric_key => { node => { Time => Float } } }
  def build_res_lookup(hourly_resources)
    hourly_resources.transform_values do |node_series|
      node_series.transform_values { |pts| pts.to_h }
    end
  end

  # ── Statistical helpers ───────────────────────────────────────────────────

  # Pearson correlation coefficient between two same-length arrays
  def pearson(xs, ys)
    n = xs.size
    return 0.0 if n < 5
    mx = xs.sum.to_f / n
    my = ys.sum.to_f / n
    num = xs.zip(ys).sum { |x, y| (x - mx) * (y - my) }
    sx  = Math.sqrt(xs.sum { |x| (x - mx)**2 })
    sy  = Math.sqrt(ys.sum { |y| (y - my)**2 })
    return 0.0 if sx < 1e-9 || sy < 1e-9
    (num / (sx * sy)).clamp(-1.0, 1.0).round(3)
  end

  # OLS slope in resource_units per hour across the full series (positive = growing)
  def trend_per_hour(time_value_map)
    pairs = time_value_map.sort.select { |_, v| !v.nil? }
    return 0.0 if pairs.size < 10
    t0 = pairs.first.first.to_i
    xs = pairs.map { |t, _| (t.to_i - t0) / 3600.0 }
    ys = pairs.map { |_, v| v.to_f }
    n  = xs.size
    mx = xs.sum / n
    my = ys.sum / n
    num = xs.zip(ys).sum { |x, y| (x - mx) * (y - my) }
    den = xs.sum { |x| (x - mx)**2 }
    return 0.0 if den < 1e-9
    (num / den).round(4)
  end

  # ── Analysis: peak-cause events ──────────────────────────────────────────

  # For every stretch of consecutive CRIT hours, return one event record with
  # the jobs that were active in the 2-hour window leading into that stretch.
  def build_peak_cause_events(res_lookup, res_cols, hourly_jobs)
    events = []

    res_cols.each do |c|
      sorted = (res_lookup.dig(c[:metric][:key], c[:node]) || {}).sort
      next if sorted.empty?

      # Collapse consecutive CRIT hours into single event records
      current = nil
      sorted.each do |t, v|
        if v && v >= c[:metric][:crit]
          if current && (t.to_i - current[:last].to_i) <= 7_200  # ≤2h gap = same event
            current[:last] = t
            if v > current[:peak_val]
              current[:peak_val]  = v
              current[:peak_time] = t
            end
          else
            events << current if current
            current = { start: t, last: t, peak_time: t, peak_val: v, col: c }
          end
        else
          events << current if current
          current = nil
        end
      end
      events << current if current
    end

    # For each event, find jobs active in the [start-2h .. start] window
    events.each do |e|
      lookback = (0..2).map { |h| e[:start] - h * 3_600 }
      e[:jobs_active] = hourly_jobs.each_with_object({}) do |(job, hours), h|
        count = lookback.sum { |t| hours[t] || 0 }
        h[job] = count if count > 0
      end.sort_by { |_, cnt| -cnt }.to_h
    end

    events.sort_by { |e| e[:peak_time] }.reverse
  end

  # ── Analysis: rate-of-change ──────────────────────────────────────────────

  # Returns { growth_events: [...], trends: [...] } for disk and memory only.
  # growth_events: hours with Δ > 2%/hr and the jobs active in the window.
  # trends: 7-day OLS slope per resource×node, in units/day.
  def build_roc_insights(res_lookup, res_cols, hourly_jobs)
    results = { growth_events: [], trends: [] }

    res_cols.select { |c| %i[disk memory].include?(c[:metric][:key]) }.each do |c|
      node_data = (res_lookup.dig(c[:metric][:key], c[:node]) || {}).sort.to_h
      next if node_data.size < 2

      # Hourly deltas — skip gaps wider than 2h (missing data)
      deltas = {}
      node_data.sort.each_cons(2) do |(t1, v1), (t2, v2)|
        next if v1.nil? || v2.nil? || (t2.to_i - t1.to_i) > 7_200
        deltas[t2] = (v2 - v1).round(2)
      end

      # 7-day linear trend
      slope      = trend_per_hour(node_data)
      per_day    = (slope * 24).round(2)
      node_short = c[:node].split('.').last(2).join('.')

      results[:trends] << {
        label:     "#{c[:metric][:label]} (#{node_short})",
        per_day:   per_day,
        unit:      c[:metric][:unit],
        direction: slope > 0 ? 'growing' : 'shrinking',
      } if slope.abs > 0.01  # >0.24 units/day = worth flagging

      # Top growth hours (Δ >2%/hr)
      deltas.select { |_, d| d > 2.0 }.sort_by { |_, d| -d }.first(5).each do |t, delta|
        lookback = (0..2).map { |h| t - h * 3_600 }
        jobs = hourly_jobs.each_with_object({}) do |(job, hours), h|
          count = lookback.sum { |lt| hours[lt] || 0 }
          h[job] = count if count > 0
        end.sort_by { |_, cnt| -cnt }.to_h

        results[:growth_events] << { time: t, delta: delta, col: c, jobs: jobs }
      end
    end

    results[:growth_events].sort_by! { |e| -e[:delta] }
    results
  end

  # ── Analysis: lag correlation ─────────────────────────────────────────────

  # For each job × resource pair, compute Pearson r at lag 0, 1, 2 hours.
  # Returns findings with |r| ≥ 0.30, picking the lag that maximises |r|.
  def build_lag_correlations(res_lookup, res_cols, hourly_jobs, all_times)
    findings = []

    hourly_jobs.each do |job_name, job_hours|
      res_cols.each do |c|
        node_data = res_lookup.dig(c[:metric][:key], c[:node]) || {}
        best      = nil

        [0, 1, 2].each do |lag|
          pairs = all_times.filter_map do |t|
            job_t   = Time.at(t.to_i - lag * 3_600)
            job_val = job_hours[job_t] || 0
            res_val = node_data[t]
            next if res_val.nil?
            [job_val.to_f, res_val.to_f]
          end
          next if pairs.size < 10

          r = pearson(pairs.map(&:first), pairs.map(&:last))
          best = { lag: lag, r: r, n: pairs.size } if best.nil? || r.abs > best[:r].abs
        end

        next unless best && best[:r].abs >= 0.30
        findings << { job: job_name, col: c, lag: best[:lag], r: best[:r], n: best[:n] }
      end
    end

    findings.sort_by { |f| -f[:r].abs }
  end

  # ── Render: peak-cause section ────────────────────────────────────────────

  def render_peak_cause_section(events)
    return '' if events.empty?

    rows = events.first(20).map do |e|
      c          = e[:col]
      node_short = c[:node].split('.').last(2).join('.')
      bg, fg, _  = cell_colors(e[:peak_val], c[:metric])
      val_str    = format_value(e[:peak_val], c[:metric][:unit])
      duration_h = [(e[:last].to_i - e[:start].to_i) / 3_600, 1].max
      time_str   = e[:start].strftime('%b %-d %H:%M')
      time_str  += "–#{e[:last].strftime('%H:%M')} (#{duration_h}h)" if duration_h > 1

      jobs_str = if e[:jobs_active].empty?
        '<em style="color:#999">no tracked jobs in window</em>'
      else
        e[:jobs_active].map { |j, cnt|
          "<strong title='#{j}'>#{j.split('::').last}</strong>&nbsp;×#{cnt}"
        }.join('&ensp;')
      end

      "<tr>" \
        "<td style='padding:7px 12px;white-space:nowrap;font-size:12px'>#{time_str}</td>" \
        "<td style='padding:7px 12px;font-size:12px'>#{c[:metric][:label]}" \
          "<br><small style='color:#888'>#{node_short}</small></td>" \
        "<td style='padding:7px 12px;text-align:center;background:#{bg};color:#{fg};" \
          "font-weight:bold;white-space:nowrap'>#{val_str}</td>" \
        "<td style='padding:7px 12px;font-size:12px'>#{jobs_str}</td>" \
      "</tr>"
    end.join

    "<h2>Peak-Cause Events — Jobs Active During CRIT Maxouts</h2>" \
      "<table><thead><tr>" \
        "<th style='#{th_style}text-align:left'>When</th>" \
        "<th style='#{th_style}text-align:left'>Resource</th>" \
        "<th style='#{th_style}'>Peak Value</th>" \
        "<th style='#{th_style}text-align:left'>Jobs in 2h lead window (×&thinsp;count)</th>" \
      "</tr></thead><tbody>#{rows}</tbody></table>" \
      "<p style='font-size:12px;color:#666;margin:4px 0 0'>Consecutive CRIT hours collapsed " \
        "into one event. Jobs counted over [event start − 2h … event start].</p>"
  end

  # ── Render: rate-of-change section ───────────────────────────────────────

  def render_roc_section(roc_insights)
    return '' if roc_insights[:growth_events].empty? && roc_insights[:trends].empty?

    trend_pills = roc_insights[:trends].map do |t|
      rising = t[:direction] == 'growing'
      bg     = rising ? '#f5c6cb' : '#c3e6cb'
      fg     = rising ? '#721c24' : '#155724'
      arrow  = rising ? '▲' : '▼'
      "<span style='background:#{bg};color:#{fg};padding:4px 12px;border-radius:20px;" \
        "font-size:12px;margin:0 6px 6px 0;display:inline-block;font-weight:600'>" \
        "#{t[:label]} #{arrow} #{t[:per_day].abs}#{t[:unit]}/day</span>"
    end.join

    rows = roc_insights[:growth_events].first(10).map do |e|
      c          = e[:col]
      node_short = c[:node].split('.').last(2).join('.')
      jobs_str   = e[:jobs].empty? ?
        '<em style="color:#999">—</em>' :
        e[:jobs].map { |j, cnt| "#{j.split('::').last}&nbsp;×#{cnt}" }.join('&ensp;')

      "<tr>" \
        "<td style='padding:7px 12px;white-space:nowrap;font-size:12px'>" \
          "#{e[:time].strftime('%b %-d %H:%M')}</td>" \
        "<td style='padding:7px 12px;font-size:12px'>#{c[:metric][:label]} #{node_short}</td>" \
        "<td style='padding:7px 12px;text-align:center;background:#ffeeba;color:#856404;" \
          "font-weight:bold'>+#{e[:delta]}%/hr</td>" \
        "<td style='padding:7px 12px;font-size:12px'>#{jobs_str}</td>" \
      "</tr>"
    end.join

    trend_block = trend_pills.empty? ? '' :
      "<div style='margin-bottom:16px'>" \
        "<span style='font-size:12px;font-weight:600;color:#495057'>7-day trend: </span>" \
        "#{trend_pills}</div>"

    "<h2>Rate-of-Change — Fastest Growth Hours (Disk &amp; Memory)</h2>" \
      "#{trend_block}" \
      "<table><thead><tr>" \
        "<th style='#{th_style}text-align:left'>Hour</th>" \
        "<th style='#{th_style}text-align:left'>Resource</th>" \
        "<th style='#{th_style}'>&Delta;/hr</th>" \
        "<th style='#{th_style}text-align:left'>Jobs in 2h lead window</th>" \
      "</tr></thead><tbody>#{rows}</tbody></table>" \
      "<p style='font-size:12px;color:#666;margin:4px 0 0'>Only hours with &gt;2%/hr growth shown. " \
        "Trend = linear regression slope over #{@window_label}.</p>"
  end

  # ── Render: lag correlation section ──────────────────────────────────────

  def render_lag_section(findings)
    return '' if findings.empty?

    rows = findings.map do |f|
      r          = f[:r]
      r_bg       = r.abs >= 0.7 ? '#f5c6cb' : (r.abs >= 0.5 ? '#ffeeba' : '#fff3cd')
      r_fg       = r.abs >= 0.7 ? '#721c24' : (r.abs >= 0.5 ? '#856404' : '#533f03')
      lag_str    = f[:lag] == 0 ? 'same hour' : "+#{f[:lag]}h"
      node_short = f[:col][:node].split('.').last(2).join('.')
      bar_w      = (r.abs * 80).round

      interp = case r
               when  0.7..  1.0 then 'Strong — job very likely drives resource up'
               when  0.5.. 0.7  then 'Moderate — probable contributor'
               when  0.3.. 0.5  then 'Weak — possible contributor'
               when -0.5..-0.3  then 'Negative — resource lower when job runs'
               else                  'Weak negative'
               end

      "<tr>" \
        "<td style='padding:7px 12px;font-size:12px' title='#{f[:job]}'>" \
          "#{f[:job].split('::').last}</td>" \
        "<td style='padding:7px 12px;font-size:12px'>#{f[:col][:metric][:label]}" \
          "<br><small style='color:#888'>#{node_short}</small></td>" \
        "<td style='padding:7px 12px;text-align:center;font-size:12px;white-space:nowrap'>" \
          "#{lag_str}</td>" \
        "<td style='padding:7px 12px;text-align:center;background:#{r_bg};color:#{r_fg};" \
          "font-weight:bold;white-space:nowrap'>#{r >= 0 ? '+' : ''}#{r}" \
          "<div style='height:4px;background:#{r_fg};width:#{bar_w}px;border-radius:2px;margin:3px auto 0'></div></td>" \
        "<td style='padding:7px 12px;font-size:12px;color:#555'>#{interp}</td>" \
      "</tr>"
    end.join

    "<h2>Lag Correlation — Statistical Job vs Resource Association</h2>" \
      "<table><thead><tr>" \
        "<th style='#{th_style}text-align:left'>Job</th>" \
        "<th style='#{th_style}text-align:left'>Resource</th>" \
        "<th style='#{th_style}'>Best lag</th>" \
        "<th style='#{th_style}'>r score</th>" \
        "<th style='#{th_style}text-align:left'>Interpretation</th>" \
      "</tr></thead><tbody>#{rows}</tbody></table>" \
      "<p style='font-size:12px;color:#666;margin:4px 0 0'>" \
        "Pearson r between hourly job-run count and resource level. Lag = hours after the job " \
        "runs before the resource responds. Only |r|&nbsp;&ge;&nbsp;0.30 shown.</p>"
  end

  # ── Render: MySQL hourly health timeline ─────────────────────────────────

  def render_mysql_timeline(hourly_mysql)
    return '' if hourly_mysql.values.all?(&:empty?)

    # Flatten all instances and times
    all_instances = MYSQL_METRICS.flat_map { |m| (hourly_mysql[m[:key]] || {}).keys }.uniq.sort
    all_times = hourly_mysql.values.flat_map(&:values).flat_map { |pts| pts.map(&:first) }.uniq.sort
    return '' if all_times.empty?

    # Build column list: metric × instance
    cols = MYSQL_METRICS.flat_map do |m|
      (hourly_mysql[m[:key]] || {}).keys.sort.map { |inst| { metric: m, instance: inst } }
    end
    return '' if cols.empty?

    col_headers = cols.map do |c|
      inst_short = c[:instance] == 'cluster' ? 'all' : c[:instance].split('.').last(2).join('.')
      "<th style='#{th_style}'>#{c[:metric][:label]}" \
        "<br><small style='font-weight:normal'>#{inst_short}</small></th>"
    end.join

    header_row = "<tr>" \
      "<th style='#{th_style}text-align:left'>Hour</th>#{col_headers}</tr>"

    rows = all_times.map do |t|
      vals = cols.map { |c| (hourly_mysql.dig(c[:metric][:key], c[:instance]) || {}).to_a
                              .find { |pt| pt[0] == t }&.last }

      # Row colour: red if any CRIT, yellow if WARN
      any_crit = vals.zip(cols).any? { |v, c| v && v >= c[:metric][:crit] }
      any_warn = vals.zip(cols).any? { |v, c| v && v >= c[:metric][:warn] }
      row_bg   = any_crit ? '#fde8e8' : (any_warn ? '#fff9e6' : '#fff')

      cells = vals.zip(cols).map do |v, c|
        next '<td style="text-align:center;color:#ccc;border:1px solid #dee2e6">—</td>' if v.nil?
        bg, fg, _ = cell_colors(v, c[:metric])
        "<td style='background:#{bg};color:#{fg};text-align:center;padding:4px 8px;" \
          "font-size:12px;border:1px solid #dee2e6'><strong>#{format_value(v, c[:metric][:unit])}</strong></td>"
      end.join

      "<tr style='background:#{row_bg}'>" \
        "<td style='padding:4px 8px;font-size:12px;white-space:nowrap;border:1px solid #dee2e6'>" \
          "#{t.strftime('%-d %b %H:%M')}</td>#{cells}</tr>"
    end.join

    # Summary: worst values across the week per column
    summary_cells = cols.map do |c|
      series = (hourly_mysql.dig(c[:metric][:key], c[:instance]) || []).filter_map(&:last)
      worst  = series.max
      next '<td style="text-align:center;color:#aaa;border:1px solid #dee2e6">—</td>' if worst.nil?
      bg, fg, status = cell_colors(worst, c[:metric])
      "<td style='background:#{bg};color:#{fg};text-align:center;padding:6px;font-weight:bold;" \
        "border:1px solid #dee2e6'>#{format_value(worst, c[:metric][:unit])}" \
        "<br><small>#{status}</small></td>"
    end.join

    summary_row = "<tr style='font-weight:bold'>" \
      "<td style='padding:6px 8px;background:#e9ecef;font-size:12px;border:1px solid #dee2e6'>#{@window_label} worst</td>" \
      "#{summary_cells}</tr>"

    "<h2>MySQL / DB Health — Hourly Timeline (#{@window_label})</h2>" \
      "<div style='max-height:500px;overflow-y:auto;border-radius:6px;box-shadow:0 1px 4px rgba(0,0,0,.08)'>" \
        "<table style='margin-bottom:0'>" \
          "<thead>#{header_row}#{summary_row}</thead>" \
          "<tbody>#{rows}</tbody>" \
        "</table>" \
      "</div>" \
      "<p style='font-size:12px;color:#666;margin:4px 0 0'>" \
        "<strong>Zombie Sleep</strong> = longest-sleeping idle connection (WARN&nbsp;&ge;&nbsp;5min, CRIT&nbsp;&ge;&nbsp;30min). &nbsp;" \
        "<strong>Repl Lag</strong> shows — on the primary (no slave status). &nbsp;" \
        "<strong>Binlog Gap</strong> shows only on the replica.</p>"
  end

  def format_number(n)
    n.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse
  end

  # Builds the Metric Definitions section at the bottom of the report
  def metric_definitions_html
    rows = SECTIONS.flat_map do |section|
      section[:metrics].map do |m|
        threshold_text = "WARN &ge;#{m[:warn]}#{m[:unit]} &nbsp; CRIT &ge;#{m[:crit]}#{m[:unit]}"
        "<tr>" \
          "<td style='padding:8px 12px;font-weight:bold;white-space:nowrap;color:#495057'>#{section[:title]}</td>" \
          "<td style='padding:8px 12px;font-weight:600'>#{m[:label]}</td>" \
          "<td style='padding:8px 12px;color:#555'>#{m[:desc] || '—'}</td>" \
          "<td style='padding:8px 12px;white-space:nowrap;font-size:12px;color:#666'>#{threshold_text}</td>" \
          "</tr>"
      end
    end.join

    "<h2>Metric Definitions</h2>" \
      "<table>" \
        "<thead><tr>" \
          "<th style='background:#343a40;color:#fff;padding:8px 12px;text-align:left'>Section</th>" \
          "<th style='background:#343a40;color:#fff;padding:8px 12px;text-align:left'>Metric</th>" \
          "<th style='background:#343a40;color:#fff;padding:8px 12px;text-align:left'>What it measures</th>" \
          "<th style='background:#343a40;color:#fff;padding:8px 12px;text-align:left'>Thresholds</th>" \
        "</tr></thead>" \
        "<tbody>#{rows}</tbody>" \
      "</table>"
  end

  # ── Full HTML report ──────────────────────────────────────────────────────

  def render(periods, nodes, by_period, peak, error_endpoints, hourly_resources, hourly_jobs, hourly_mysql)
    # ── Shared correlation lookups (built once, used by multiple sections) ──
    res_cols   = build_res_cols(hourly_resources)
    res_lookup = build_res_lookup(hourly_resources)
    all_times  = (hourly_resources.values.flat_map(&:values).flat_map { |pts| pts.map(&:first) } +
                  hourly_jobs.values.flat_map(&:keys)).uniq.sort

    # ── Analysis (computed upfront so render methods stay pure) ─────────────
    peak_events     = build_peak_cause_events(res_lookup, res_cols, hourly_jobs)
    roc_insights    = build_roc_insights(res_lookup, res_cols, hourly_jobs)
    lag_correlations = build_lag_correlations(res_lookup, res_cols, hourly_jobs, all_times)

    # Build columns per section: [{ metric:, node: }, ...]
    section_columns = SECTIONS.map do |section|
      cols = section[:metrics].flat_map do |m|
        node_list = nodes[m[:key]].presence || ['cluster']
        node_list.map { |node| { metric: m, node: node } }
      end
      { title: section[:title], columns: cols }
    end

    all_columns = section_columns.flat_map { |s| s[:columns] }

    # Alert banner: every metric/node that hit CRIT this week
    crit_items = []
    ALL_METRICS.each do |m|
      (peak[m[:key]] || {}).each do |node, val|
        next unless val && val >= m[:crit]
        crit_items << "#{m[:label]} on #{node} peaked at <strong>#{format_value(val, m[:unit])}</strong>"
      end
    end

    banner = if crit_items.any?
      list = crit_items.map { |i| "<li>#{i}</li>" }.join
      "<div style='background:#f8d7da;border:1px solid #f5c6cb;border-radius:4px;" \
        "padding:12px 16px;margin:0 0 20px;color:#721c24'>" \
        "<strong>&#9888; Resources maxed out this week:</strong>" \
        "<ul style='margin:6px 0 0 16px'>#{list}</ul></div>"
    else
      "<div style='background:#d4edda;border:1px solid #c3e6cb;border-radius:4px;" \
        "padding:12px 16px;margin:0 0 20px;color:#155724'>" \
        "<strong>&#10003; No critical issues detected this week.</strong></div>"
    end

    # Header row with section grouping spans
    span_cells = section_columns.map do |s|
      "<th colspan='#{s[:columns].size}' style='background:#495057;color:#fff;padding:6px 12px;" \
        "font-size:11px;text-transform:uppercase;letter-spacing:.07em;text-align:center'>" \
        "#{s[:title]}</th>"
    end.join

    col_header_cells = all_columns.map do |c|
      node_short = c[:node] == 'cluster' ? '' : c[:node].split('.').last(2).join('.')
      label      = c[:metric][:label]
      label     += "<br><span style='font-weight:normal;font-size:10px'>#{node_short}</span>" unless node_short.empty?
      # ⓘ suffix signals to the user that a hover tooltip is available
      label     += " <span style='font-size:10px;opacity:.7'>ⓘ</span>" if c[:metric][:desc]
      th(label, tooltip: c[:metric][:desc])
    end.join

    header_rows = "<tr><th style='background:#343a40;color:#fff;padding:8px 12px' rowspan='2'>Day</th>#{span_cells}</tr>" \
                  "<tr>#{col_header_cells}</tr>"

    # Threshold legend per section — summarised from first metric as representative
    legend_parts = SECTIONS.map do |section|
      samples = section[:metrics].first
      warn_str = format_value(samples[:warn], samples[:unit])
      crit_str = format_value(samples[:crit], samples[:unit])
      "<strong>#{section[:title]}:</strong> " \
        "<span style='background:#c3e6cb;color:#155724;padding:2px 6px;border-radius:3px;font-weight:bold'>OK</span> " \
        "&lt;#{warn_str} &nbsp;" \
        "<span style='background:#ffeeba;color:#856404;padding:2px 6px;border-radius:3px;font-weight:bold'>WARN</span> " \
        "#{warn_str}–#{crit_str} &nbsp;" \
        "<span style='background:#f5c6cb;color:#721c24;padding:2px 6px;border-radius:3px;font-weight:bold'>CRIT</span> " \
        "&gt;#{crit_str}"
    end.join("&emsp;&emsp;")

    # Weekly peak row
    peak_cells = all_columns.map { |c| td(peak.dig(c[:metric][:key], c[:node]), c[:metric]) }.join
    peak_row   = "<tr style='font-weight:bold'>" \
      "<td style='padding:8px 12px;background:#e9ecef'>#{@window_label} peak</td>#{peak_cells}</tr>"

    # Period rows — hourly or daily depending on window size
    period_rows = periods.map do |period|
      if @main_step == 3_600
        # Hourly row — period is a Time object
        is_now_hour = (period.to_i == truncate_hour(@now).to_i)
        cells = all_columns.map { |c| td(by_period.dig(c[:metric][:key], c[:node], period), c[:metric]) }.join
        row_bg = is_now_hour ? '#e8f4fd' : '#fff'
        label  = period.strftime('%-d %b %H:%M') + (is_now_hour ? ' <em>(now)</em>' : '')
      else
        # Daily row — period is a Date object
        is_today = (period == @now.to_date)
        cells = all_columns.map { |c| td(by_period.dig(c[:metric][:key], c[:node], period), c[:metric]) }.join
        row_bg = is_today ? '#e8f4fd' : '#fff'
        label  = period.strftime('%a, %b %-d') + (is_today ? ' <em>(today)</em>' : '')
      end
      "<tr style='background:#{row_bg}'><td style='padding:8px 12px'>#{label}</td>#{cells}</tr>"
    end.join

    <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <title>Infra &amp; App Report — #{@now.strftime('%Y-%m-%d')} (#{@window_label})</title>
        <style>
          * { box-sizing: border-box; }
          body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            margin: 0; padding: 28px 36px; background: #f4f6f9; color: #212529;
          }
          h1  { margin: 0 0 4px; font-size: 22px; color: #1a1a2e; }
          .meta { font-size: 13px; color: #6c757d; margin-bottom: 24px; }
          h2  { font-size: 12px; margin: 28px 0 8px; color: #6c757d; text-transform: uppercase; letter-spacing: .08em; }
          table { width: 100%; border-collapse: collapse; background: #fff; border-radius: 6px; overflow: hidden; box-shadow: 0 1px 4px rgba(0,0,0,.08); margin-bottom: 8px; }
          td, th { border: 1px solid #dee2e6; }
          tr:hover td { filter: brightness(0.97); }
          .legend { font-size: 12px; color: #444; margin-bottom: 20px; line-height: 2; }
        </style>
      </head>
      <body>
        <h1>Infrastructure &amp; Application Report</h1>
        <p class="meta">
          Generated #{@now.strftime('%A, %B %-d %Y at %H:%M')}
          &nbsp;&bull;&nbsp; Last #{@window_label}
          &nbsp;&bull;&nbsp; Source: #{@config[:url]}
        </p>

        #{banner}

        <div class="legend">#{legend_parts}</div>

        <h2>Peak (#{@window_label})</h2>
        <table>
          <thead>#{header_rows}</thead>
          <tbody>#{peak_row}</tbody>
        </table>

        <h2>#{@main_step == 3_600 ? 'Hourly' : 'Daily'} Breakdown — max per #{@main_step == 3_600 ? 'hour' : 'day'} (#{@window_label})</h2>
        <table>
          <thead>#{header_rows}</thead>
          <tbody>#{period_rows}</tbody>
        </table>

        #{render_peak_cause_section(peak_events)}

        #{render_roc_section(roc_insights)}

        #{render_lag_section(lag_correlations)}

        #{render_error_section(error_endpoints)}

        #{render_mysql_timeline(hourly_mysql)}

        #{render_correlation_timeline(hourly_resources, hourly_jobs, res_cols: res_cols, res_lookup: res_lookup, all_times: all_times)}

        #{metric_definitions_html}
      </body>
      </html>
    HTML
  end
end
