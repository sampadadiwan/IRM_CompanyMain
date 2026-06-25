#!/usr/bin/env ruby
# frozen_string_literal: true

# MySQL Load Test Monitor
# Polls the development MySQL every 5s during a load test and produces
# a rich terminal summary with computed ratios, per-interval analysis,
# and actionable recommendations.
#
# Usage: bundle exec ruby scripts/mysql_monitor.rb
#        (run alongside your load test in a separate terminal)
#        Press Ctrl+C to stop and get the report.

require 'mysql2'

DB_CONFIG = {
  host: '127.0.0.1',
  port: 33_066,
  username: 'root',
  password: 'Root1234$',
  database: 'IRM_development',
  reconnect: true
}.freeze

POLL_INTERVAL = 5 # seconds between samples

# Cumulative status variables used for per-second delta computation
KEY_METRICS = %w[
  Threads_connected Threads_running Max_used_connections
  Queries Questions
  Innodb_buffer_pool_read_requests Innodb_buffer_pool_reads
  Innodb_rows_read Innodb_rows_inserted Innodb_rows_updated Innodb_rows_deleted
  Innodb_row_lock_current_waits Innodb_row_lock_time
  Created_tmp_disk_tables Created_tmp_tables
  Select_scan Select_full_join
  Slow_queries Connections
].freeze

# ──────────────────────────────────────────────
# Formatting helpers
# ──────────────────────────────────────────────

def format_duration(seconds)
  mins = (seconds / 60).to_i
  secs = (seconds % 60).to_i
  format('%dm %02ds', mins, secs)
end

def format_number(n)
  n.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
end

def format_float(f, decimals = 1)
  format("%.#{decimals}f", f)
end

def bold(text)
  "\e[1m#{text}\e[22m"
end

def red(text)
  "\e[31m#{text}\e[0m"
end

def yellow(text)
  "\e[33m#{text}\e[0m"
end

def cyan(text)
  "\e[36m#{text}\e[0m"
end

# ──────────────────────────────────────────────
# Metric analysis helpers
# ──────────────────────────────────────────────

# Summarize per-second delta rates across all samples for a given metric.
def summarize_rates(samples, metric)
  rates = samples.filter_map { |s| s[:deltas][metric] }
  return {} if rates.empty?

  {
    avg: (rates.sum / rates.size).round(1),
    peak: rates.max.round(1),
    min: rates.min.round(1)
  }
end

# Summarize snapshot values (not deltas) for a given status variable.
def summarize_values(samples, metric)
  values = samples.map { |s| s[:status][metric].to_i }
  return {} if values.empty?

  {
    avg: (values.sum.to_f / values.size).round(1),
    peak: values.max,
    min: values.min
  }
end

# ──────────────────────────────────────────────
# Report generation
# ──────────────────────────────────────────────

def generate_report(samples, start_time, global_max_connections, slow_query_log_was_off)
  puts
  puts bold('═' * 55)
  puts bold('        MySQL Load Test Report — IRM_development')
  puts bold('═' * 55)
  puts

  if samples.empty?
    puts yellow('  No samples collected (test was too short).')
    puts
    return
  end

  elapsed = samples.last[:timestamp] - start_time
  first = samples.first
  last = samples.last

  # ── Pre-compute all analysis values ──

  # Connections
  conn_connected = summarize_values(samples, 'Threads_connected')
  conn_running = summarize_values(samples, 'Threads_running')
  max_used = last[:status]['Max_used_connections'].to_i
  conn_util = global_max_connections.positive? ? (max_used.to_f / global_max_connections * 100).round(1) : 0

  # Throughput
  queries_rate = summarize_rates(samples, 'Queries')
  questions_rate = summarize_rates(samples, 'Questions')
  rows_read = summarize_rates(samples, 'Innodb_rows_read')
  rows_inserted = summarize_rates(samples, 'Innodb_rows_inserted')
  rows_updated = summarize_rates(samples, 'Innodb_rows_updated')
  rows_deleted = summarize_rates(samples, 'Innodb_rows_deleted')
  total_queries = last[:status]['Queries'].to_i - first[:status]['Queries'].to_i

  # Buffer pool
  hit_rates = samples.filter_map { |s| s[:buffer_pool_hit_rate] }
  avg_hit = hit_rates.any? ? (hit_rates.sum / hit_rates.size).round(1) : 0
  min_hit = hit_rates.any? ? hit_rates.min.round(1) : 0
  max_hit = hit_rates.any? ? hit_rates.max.round(1) : 0

  total_read_requests = last[:status]['Innodb_buffer_pool_read_requests'].to_i -
                        first[:status]['Innodb_buffer_pool_read_requests'].to_i
  total_reads = last[:status]['Innodb_buffer_pool_reads'].to_i -
                first[:status]['Innodb_buffer_pool_reads'].to_i
  disk_pct = total_read_requests.positive? ? (total_reads.to_f / total_read_requests * 100).round(1) : 0

  pool_data = last[:status]['Innodb_buffer_pool_pages_data'].to_i
  pool_total = last[:status]['Innodb_buffer_pool_pages_total'].to_i
  pool_util = pool_total.positive? ? (pool_data.to_f / pool_total * 100).round(1) : 0

  # Row locks
  lock_waits = summarize_rates(samples, 'Innodb_row_lock_current_waits')
  lock_waits_total = last[:status]['Innodb_row_lock_current_waits'].to_i -
                     first[:status]['Innodb_row_lock_current_waits'].to_i
  lock_time_total = last[:status]['Innodb_row_lock_time'].to_i -
                    first[:status]['Innodb_row_lock_time'].to_i

  # Temp tables
  total_disk_tmp = last[:status]['Created_tmp_disk_tables'].to_i -
                   first[:status]['Created_tmp_disk_tables'].to_i
  total_mem_tmp = last[:status]['Created_tmp_tables'].to_i -
                  first[:status]['Created_tmp_tables'].to_i
  disk_tmp_rate = summarize_rates(samples, 'Created_tmp_disk_tables')
  mem_tmp_rate = summarize_rates(samples, 'Created_tmp_tables')
  disk_ratio = total_mem_tmp.positive? ? (total_disk_tmp.to_f / total_mem_tmp * 100).round(1) : 0

  # Full scans
  scans = summarize_rates(samples, 'Select_scan')
  joins = summarize_rates(samples, 'Select_full_join')

  # Slow queries
  slow_total = last[:status]['Slow_queries'].to_i - first[:status]['Slow_queries'].to_i
  slow_pct = total_queries.positive? ? (slow_total.to_f / total_queries * 100).round(2) : 0

  # History list length
  hll_values = samples.filter_map { |s| s[:history_list_length] }
  initial_hll = hll_values.first || 0
  final_hll = hll_values.last || 0

  # ── Render sections ──

  # Run Overview
  puts bold('  📋 Run Overview')
  puts "     Duration:       #{format_duration(elapsed)}"
  puts "     Samples:        #{samples.size}  (poll interval: #{POLL_INTERVAL}s)"
  puts "     Start:          #{first[:timestamp].strftime('%H:%M:%S')}"
  puts "     End:            #{last[:timestamp].strftime('%H:%M:%S')}"
  puts

  # Connections
  puts bold('  🔌 Connections')
  puts "     Threads Connected:   avg #{conn_connected[:avg]}, peak #{conn_connected[:peak]}, min #{conn_connected[:min]}"
  puts "     Threads Running:     avg #{conn_running[:avg]}, peak #{conn_running[:peak]}, min #{conn_running[:min]}"
  puts "     Max Used:           #{max_used}  (#{conn_util}% of #{global_max_connections} max_connections)"
  puts

  # Query Throughput
  puts bold('  ⚡ Query Throughput')
  puts "     Queries/sec:       #{format_rate_row(queries_rate)}"
  puts "     Questions/sec:     #{format_rate_row(questions_rate)}"
  puts "     Rows Read/sec:     #{format_rate_row(rows_read)}"
  puts "     Rows Inserted/sec: #{format_rate_row(rows_inserted)}"
  puts "     Rows Updated/sec:  #{format_rate_row(rows_updated)}"
  puts "     Rows Deleted/sec:  #{format_rate_row(rows_deleted)}"
  puts "     Total Queries:     #{format_number(total_queries)}"
  puts

  # InnoDB Buffer Pool
  if hit_rates.any?
    puts bold('  💾 InnoDB Buffer Pool')
    puts "     Hit Rate:          #{format('%6s', format_float(avg_hit))}% avg  " \
         "#{format('%6s', format_float(min_hit))}% min  #{format('%6s', format_float(max_hit))}% max"
    puts "     Total Requests:   #{format_number(total_read_requests)}"
    puts "     Disk Reads:       #{format_number(total_reads)}  (#{disk_pct}% of requests)"
    if pool_total.positive?
      puts "     Pool Pages:       #{format_number(pool_data)} / #{format_number(pool_total)} used  " \
           "(#{pool_util}% utilized)"
    end
    puts
  end

  # Row Locks
  if lock_waits.any? && lock_waits[:avg].positive?
    puts bold('  🔒 Row Locks')
    puts "     Lock Waits/sec:   #{format('%10s', format_float(lock_waits[:avg]))} avg  " \
         "#{format('%10s', format_float(lock_waits[:peak]))} peak  total #{lock_waits_total}"
    puts "     Lock Time:        #{format_number(lock_time_total)} ms total"
    puts
  end

  # Temp Tables
  if mem_tmp_rate.any? && mem_tmp_rate[:avg].positive?
    warn = disk_ratio > 20 ? yellow(' ⚠️') : ''
    puts bold('  📊 Temp Tables')
    puts "     Disk Temp Tables/s:   #{'%8s' % format_float(disk_tmp_rate[:avg])} avg  " \
         "#{'%8s' % format_float(disk_tmp_rate[:peak])} peak  total #{format_number(total_disk_tmp)}"
    puts "     Memory Temp Tables/s: #{'%8s' % format_float(mem_tmp_rate[:avg])} avg  " \
         "#{'%8s' % format_float(mem_tmp_rate[:peak])} peak"
    puts "     Disk Ratio:           #{format_float(disk_ratio)}%#{warn}"
    puts
  end

  # Full Scans
  if scans.any?
    puts bold('  🔍 Full Scans')
    puts "     Select_scan/sec:       #{'%8s' % format_float(scans[:avg])} avg  " \
         "#{'%8s' % format_float(scans[:peak])} peak"
    if joins[:avg]&.positive?
      puts "     Select_full_join/sec:  #{'%8s' % format_float(joins[:avg])} avg  " \
           "#{'%8s' % format_float(joins[:peak])} peak"
    end
    puts
  end

  # Slow Queries
  if slow_total.positive?
    slow_rate = (slow_total.to_f / elapsed).round(2)
    puts bold('  🐌 Slow Queries')
    puts "     Total: #{slow_total}  (#{slow_pct}% of all queries)  Rate: #{slow_rate}/s"
    puts
  end

  # Process State Distribution
  all_states = Hash.new(0)
  samples.each do |sample|
    sample[:processlist_states].each do |state, count|
      next if state == 'Total'

      all_states[state] += count
    end
  end

  if all_states.any?
    grand_total = all_states.values.sum.to_f
    puts bold('  📋 Process State Distribution (avg across samples)')
    if grand_total.positive?
      all_states.sort_by { |_, v| -v }.each do |state, count|
        pct = (count / grand_total * 100).round(1)
        puts "     #{'%-22s' % state}: #{'%5.1f' % pct}%"
      end
    end
    puts
  end

  # ── Bottlenecks & Recommendations ──
  puts bold('═' * 55)
  puts bold('  ⚠️  Bottlenecks & Recommendations')
  puts bold('═' * 55)
  puts

  had_warnings = false

  # Buffer pool
  if hit_rates.any? && min_hit < 95
    puts red("  🔴 CRITICAL: Buffer pool hit rate dropped to #{min_hit}%")
    puts '     → Increase innodb_buffer_pool_size from 128MB to at least 1GB.'
    puts
    had_warnings = true
  elsif hit_rates.any? && min_hit < 99
    puts yellow("  🟡 WARNING: Buffer pool hit rate dropped to #{min_hit}% (avg #{avg_hit}%)")
    puts '     → Consider increasing innodb_buffer_pool_size.'
    puts
    had_warnings = true
  end

  # Row locks
  if lock_waits[:avg]&.positive?
    puts yellow("  🟡 WARNING: Row lock waits detected (avg #{lock_waits[:avg]}/s, peak #{lock_waits[:peak]}/s)")
    puts '     → Review long-running transactions during load.'
    puts '     → Check for missing indexes on foreign key columns.'
    puts
    had_warnings = true
  end

  # Temp table disk ratio
  if disk_ratio > 20
    puts yellow("  🟡 WARNING: #{disk_ratio}% of temp tables written to disk (threshold: 20%)")
    puts '     → Review queries generating large temp tables (GROUP BY, DISTINCT, UNION).'
    puts '     → Consider increasing tmp_table_size / max_heap_table_size.'
    puts
    had_warnings = true
  end

  # Full scans
  if scans[:avg] && scans[:avg] > 10
    puts yellow("  🟡 WARNING: Full table scans averaging #{scans[:avg]}/s")
    puts '     → Query performance_schema.events_statements_summary_by_digest'
    puts '       to find top-scanned tables, or enable slow query log with'
    puts '       log_queries_not_using_indexes=ON.'
    puts
    had_warnings = true
  end

  if joins[:avg] && joins[:avg] > 1
    puts yellow("  🟡 WARNING: Full joins averaging #{joins[:avg]}/s")
    puts '     → Check join columns for missing indexes.'
    puts
    had_warnings = true
  end

  # Slow queries
  if slow_total.positive?
    puts yellow("  🟡 WARNING: #{slow_total} slow queries detected (#{slow_pct}% of all queries)")
    puts '     → Analyze slow query log to identify problematic queries.'
    puts
    had_warnings = true
  end

  # History list length
  if final_hll > 1000 || (final_hll - initial_hll) > 500
    puts yellow("  🟡 WARNING: InnoDB history list length is #{final_hll} " \
                "(started at #{initial_hll})")
    puts '     → Long-running transactions may be blocking undo purge.'
    puts '     → Check for uncommitted transactions with SHOW PROCESSLIST.'
    puts
    had_warnings = true
  end

  # Slow query log off
  if slow_query_log_was_off
    puts cyan('  💡 INFO: Slow query log was OFF during this test.')
    puts '     → Can enable dynamically:'
    puts '       SET GLOBAL slow_query_log = ON;'
    puts '       SET GLOBAL long_query_time = 1;'
    puts '       SET GLOBAL log_queries_not_using_indexes = ON;'
    puts '     → Run load test again to capture individual slow queries.'
    puts
  end

  unless had_warnings
    puts '  ✅ No significant bottlenecks detected.'
    puts
  end

  puts bold('═' * 55)
  puts
end

# Format an avg / peak rate row with consistent alignment
def format_rate_row(summary)
  avg = summary[:avg] ? format_float(summary[:avg]) : '-'
  peak = summary[:peak] ? format_float(summary[:peak]) : '-'
  min = summary[:min] ? format_float(summary[:min]) : '-'
  "#{'%10s' % avg} avg  #{'%10s' % peak} peak  #{'%10s' % min} min"
end

# ──────────────────────────────────────────────
# Connection setup
# ──────────────────────────────────────────────

client = Mysql2::Client.new(DB_CONFIG)
puts "Connected to MySQL #{DB_CONFIG[:host]}:#{DB_CONFIG[:port]} / #{DB_CONFIG[:database]}"
puts "Polling every #{POLL_INTERVAL}s — press Ctrl+C to stop and generate report"
puts

# Capture global max_connections for utilization analysis
global_max_connections = 151
begin
  result = client.query("SHOW VARIABLES LIKE 'max_connections'")
  global_max_connections = result.first['Value'].to_i
rescue Mysql2::Error => e
  puts "  (could not determine max_connections: #{e.message})"
end

# Check if slow query log is on (for recommendation context)
slow_query_log_was_off = true
begin
  result = client.query("SHOW VARIABLES LIKE 'slow_query_log'")
  slow_query_log_was_off = result.first['Value'] != 'ON'
rescue Mysql2::Error
  # non-critical
end

samples = []
previous = nil
start_time = Time.now

# ──────────────────────────────────────────────
# Signal handler — prints report on Ctrl+C
# ──────────────────────────────────────────────

trap('INT') do
  puts "\n\n"
  generate_report(samples, start_time, global_max_connections, slow_query_log_was_off)
  exit 0
end

# ──────────────────────────────────────────────
# Polling loop
# ──────────────────────────────────────────────

loop do
  # Capture current snapshot
  raw_status = client.query('SHOW GLOBAL STATUS')
  status = {}
  raw_status.each { |row| status[row['Variable_name']] = row['Value'] }

  # Fetch processlist summary (count by state)
  raw_processlist = client.query('SHOW PROCESSLIST')
  processlist_states = Hash.new(0)
  raw_processlist.each { |row| processlist_states[row['State'] || 'NULL'] += 1 }
  processlist_states['Total'] = raw_processlist.count

  # Fetch InnoDB history list length
  raw_innodb = client.query('SHOW ENGINE INNODB STATUS')
  innodb_text = raw_innodb.first['Status']
  history_list_length = innodb_text[/History list length (\d+)/, 1].to_i

  current = {
    timestamp: Time.now,
    status: status,
    processlist_states: processlist_states,
    history_list_length: history_list_length
  }

  if previous
    delta_time = current[:timestamp] - previous[:timestamp]
    delta_secs = delta_time.positive? ? delta_time : 1

    deltas = {}
    KEY_METRICS.each do |metric|
      prev_val = previous[:status][metric].to_i
      curr_val = current[:status][metric].to_i
      diff = curr_val - prev_val
      deltas[metric] = diff >= 0 ? (diff / delta_secs).round(1) : 0
    end
    current[:deltas] = deltas

    # Per-interval InnoDB buffer pool hit rate
    req_delta = current[:status]['Innodb_buffer_pool_read_requests'].to_i -
                previous[:status]['Innodb_buffer_pool_read_requests'].to_i
    reads_delta = current[:status]['Innodb_buffer_pool_reads'].to_i -
                  previous[:status]['Innodb_buffer_pool_reads'].to_i
    current[:buffer_pool_hit_rate] = ((1.0 - (reads_delta.to_f / req_delta)) * 100).round(1) if req_delta.positive?

    samples << current
  end

  previous = current

  # Progress indicator
  elapsed = Time.now - start_time
  running = samples.last&.dig(:processlist_states, 'Total') || 0
  print "\r\e[KCollected #{samples.size} samples | #{format_duration(elapsed)} elapsed | #{running} connections"
  $stdout.flush

  sleep POLL_INTERVAL
end
