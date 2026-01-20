# Usage: bin/rails runner script/analyze_queries.rb

require 'csv'

log_file = 'log/sql_queries.log'
output_file = 'log/query_analysis.md'

# 1. Parse the log to find queries and their execution times
query_stats = {}

puts "Reading logs..."
File.open(log_file, 'r') do |f|
  f.each_line do |line|
    next unless line.include?('SELECT')

    # Extract time and SQL
    time_match = line.match(/\((\d+\.\d+)ms\)/)
    # Get everything from SELECT onwards, but handle potential junk at the end
    sql_match = line.match(/SELECT.*/i)

    next unless time_match && sql_match

    time = time_match[1].to_f
    sql = sql_match[0].strip

    # Clean up: Remove Rails-added comments and terminal escape codes
    sql = sql.gsub(%r{/\*.*?\*/}, '')
    sql = sql.gsub(/\e\[[0-9;]*m/, '') # Remove ANSI color codes
    sql = sql.split("\e").first # Cut off anything after an escape char if it missed
    sql = sql.strip

    # Grouping template
    template = sql.gsub(/IN\s*\([^)]+\)/i, 'IN (?)').gsub(/\b\d+\b/, '?').gsub(/'[^']*'/, '?')

    query_stats[template] ||= { count: 0, total_time: 0, max_time: 0, examples: [] }
    query_stats[template][:count] += 1
    query_stats[template][:total_time] += time
    query_stats[template][:max_time] = [query_stats[template][:max_time], time].max
    query_stats[template][:examples] << sql if query_stats[template][:examples].empty?
  end
end

# 2. Sort by total time
sorted_stats = query_stats.sort_by { |_k, v| -v[:total_time] }.first(20)

puts "Analyzing top #{sorted_stats.size} query patterns..."

File.open(output_file, 'w') do |f|
  f.puts "# SQL Query Performance Analysis"
  f.puts "\nGenerated on: #{Time.zone.now}"
  f.puts "\n| Rank | Avg Time (ms) | Total Time (ms) | Count | Query Template | Analysis |"
  f.puts "| --- | --- | --- | --- | --- | --- |"

  sorted_stats.each_with_index do |(template, stats), index|
    example_sql = stats[:examples].first
    avg_time = (stats[:total_time] / stats[:count]).round(2)

    # Run EXPLAIN
    begin
      explanation = ActiveRecord::Base.connection.execute("EXPLAIN #{example_sql}").to_a

      bad_signals = []
      explanation.each do |row|
        # MySQL columns: id, select_type, table, partitions, type, possible_keys, key, key_len, ref, rows, filtered, Extra
        type = row.is_a?(Hash) ? row['type'] : row[4]
        extra = row.is_a?(Hash) ? row['Extra'] : row[11]
        rows = row.is_a?(Hash) ? row['rows'] : row[9]
        key = row.is_a?(Hash) ? row['key'] : row[6]

        bad_signals << "Full Table Scan (type: ALL)" if type == 'ALL'
        bad_signals << "Using Temporary" if extra&.include?('Using temporary')
        bad_signals << "Using Filesort" if extra&.include?('Using filesort')
        bad_signals << "High row count (#{rows})" if rows.to_i > 5000
        bad_signals << "No index used" if key.nil? || key == ''
      end

      reason = bad_signals.uniq.join(", ")
      reason = "Optimized (Index: #{explanation.first.is_a?(Hash) ? explanation.first['key'] : explanation.first[6]})" if reason.empty?
    rescue StandardError => e
      reason = "Error: #{e.message[0..50]}"
    end

    # Clean template for markdown
    clean_template = template.delete('`')[0..150]
    f.puts "| #{index + 1} | #{avg_time} | #{stats[:total_time].round(2)} | #{stats[:count]} | `#{clean_template}...` | #{reason} |"
  end
end

puts "Analysis complete. Results written to #{output_file}"
