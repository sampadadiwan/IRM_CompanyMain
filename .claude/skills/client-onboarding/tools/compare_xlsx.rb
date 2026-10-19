# Compares two upload workbooks the way the importer reads them: sheet by sheet, columns matched by header NAME
# (case, spacing and "*" ignored — the importer titleizes headers), rows compared as a multiset on the shared columns
# (row order does not matter). Numbers equal to 1e-6, dates as dates, blank = nil = "". Read-only.
# Use it to prove a rebuilt file equals one already imported and reconciled.
#
# Usage: ruby compare_xlsx.rb EXPECTED.xlsx ACTUAL.xlsx      (exit 0 = same content)
require "roo"

a_path, b_path = ARGV
abort File.read(__FILE__).lines.grep(/^# Usage/).join unless a_path && b_path
norm = ->(h) { h.to_s.delete("*").gsub(/[[:space:]]+/, " ").strip.downcase }
cell = lambda do |v|
  case v
  when nil then ""
  when Numeric then v.to_f.round(6)
  when Date then v.iso8601
  else v.to_s.strip
  end
end

a, b = Roo::Spreadsheet.open(a_path), Roo::Spreadsheet.open(b_path)
same = true
a.sheets.each do |sheet|
  unless b.sheets.include?(sheet)
    puts "✖ sheet #{sheet.inspect} missing in #{File.basename(b_path)}"
    same = false
    next
  end
  sa, sb = a.sheet(sheet), b.sheet(sheet)
  ha, hb = sa.row(1).map(&norm), sb.row(1).map(&norm)
  common = ha & hb
  rows = lambda do |s, h|
    idx = common.map { h.index(_1) }
    ((2..s.last_row.to_i).map { |r| idx.map { |i| cell.(s.cell(r, i + 1)) } }).reject { _1.all?("") }.tally
  end
  ra, rb = rows.(sa, ha), rows.(sb, hb)
  only_a, only_b = ra.to_a - rb.to_a, rb.to_a - ra.to_a
  ok = only_a.empty? && only_b.empty?
  same &&= ok
  puts "#{ok ? '✔' : '✖'} #{sheet}: #{ra.values.sum} vs #{rb.values.sum} rows on #{common.size} shared columns" \
       "#{" · only in expected: #{(ha - hb).join(', ')}" if (ha - hb).any?}#{" · only in actual: #{(hb - ha).join(', ')}" if (hb - ha).any?}"
  (only_a.first(3).map { "    expected only: #{common.zip(_1.first).to_h.reject { |_, v| v == '' }}" } +
   only_b.first(3).map { "    actual only:   #{common.zip(_1.first).to_h.reject { |_, v| v == '' }}" }).each { puts _1 }
end
exit(same ? 0 : 1)
