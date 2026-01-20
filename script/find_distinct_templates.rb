log_file = 'log/sql_queries.log'
output_file = 'log/distinct_queries_templated.log'

distinct_templates = Set.new

# Pattern to strip Rails metadata and get the SQL
sql_start_pattern = /(SELECT|INSERT|UPDATE|DELETE).*/i

File.open(log_file, 'r') do |f|
  f.each_line do |line|
    match = line.match(sql_start_pattern)
    next unless match

    sql = match[0].strip
    # Remove comments
    sql = sql.gsub(%r{/\*.*?\*/}, '').strip

    # Template it:
    # 1. Replace IN (...) with IN (?)
    sql = sql.gsub(/IN\s*\([^)]+\)/i, 'IN (?)')
    # 2. Replace numbers with ?
    sql = sql.gsub(/\b\d+\b/, '?')
    # 3. Replace single quoted strings with ?
    sql = sql.gsub(/'[^']*'/, '?')

    distinct_templates.add(sql)
  end
end

File.open(output_file, 'w') do |f|
  distinct_templates.sort.each { |query| f.puts query }
end

puts "Processed #{File.size(log_file)} bytes."
puts "Found #{distinct_templates.size} unique query templates."
puts "Results written to #{output_file}."
