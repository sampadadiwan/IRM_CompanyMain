# Checks a dry-run verdict's ok cells against the source workbook (read-only, no API): the value the reader would store
# must equal the source cell at its ref, and each column header is listed with the period the reader made of it — read
# that list; a verdict can say ok and still be wrong (a quarter read as a month, a year range read as a month).
#
# Usage: ruby check_dryrun_cells.rb --verdict V.json --file X.xlsx
require "json"
require "roo"
require "optparse"

opts = {}
OptionParser.new do |o|
  o.on("--verdict PATH") { opts[:verdict] = _1 }
  o.on("--file PATH") { opts[:file] = _1 }
end.parse!(ARGV)
abort File.read(__FILE__).lines.grep(/^# Usage/).join unless opts[:verdict] && opts[:file]

verdict = JSON.parse(File.read(opts[:verdict]))
book = Roo::Spreadsheet.open(opts[:file])
col_index = ->(letters) { letters.chars.reduce(0) { |a, ch| (a * 26) + ch.ord - 64 } }

ok = verdict["cells"].select { _1["status"] == "ok" }
bad = ok.filter_map do |c|
  sheet, ref = c["ref"].split("!")
  letters, row = ref.match(/\A([A-Z]+)(\d+)\z/).captures
  src = book.sheet(sheet).cell(row.to_i, col_index.(letters))
  # Value: the stored figure equals the source cell, to the paisa
  "#{c['ref']} #{c['kpi']}: source #{src.inspect} vs stored #{c['stored']}" unless src.is_a?(Numeric) && (src - c["stored"].to_f).abs < 0.01
end

puts "#{File.basename(opts[:file])}: #{ok.size} ok cells, #{bad.size} value mismatches"
bad.first(10).each { puts "  ✖ #{_1}" }
puts "  KPIs: #{ok.map { _1['standard_kpi'] }.uniq.size} — #{ok.group_by { _1['standard_kpi'] }.map { |k, v| "#{k}(#{v.size})" }.join(', ')}"
puts "  headers → periods:"
ok.map { [_1["sheet"], _1["period"].to_s.gsub(/\s+/, " "), _1["period_type"], _1["parsed_period"]] }.uniq
  .each { |s, h, t, p| puts "    #{s} | #{h[0, 40].ljust(40)} → #{t} #{p}" }
exit(bad.empty? ? 0 : 1)
