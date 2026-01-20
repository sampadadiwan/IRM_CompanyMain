log_file = 'log/sql_queries.log'
output_file = 'log/distinct_queries.log'

distinct_queries = Set.new

# Pattern to strip Rails metadata and get the SQL
# Examples:
# [ActiveJob] ... SELECT `users`.* FROM `users` ...
# Fund Load (1.1ms) SELECT `funds`.* FROM `funds` ...
sql_start_pattern = /(SELECT|INSERT|UPDATE|DELETE).*/i

File.open(log_file, 'r') do |f|
  f.each_line do |line|
    match = line.match(sql_start_pattern)
    next unless match

    sql = match[0].strip
    # Optional: Remove comments like /*application:CapHive...*/
    sql = sql.gsub(%r{/\*.*?\*/}, '').strip
    distinct_queries.add(sql)
  end
end

File.open(output_file, 'w') do |f|
  distinct_queries.sort.each { |query| f.puts query }
end

puts "Processed #{File.size(log_file)} bytes."
puts "Found #{distinct_queries.size} unique queries."
puts "Results written to #{output_file}."
