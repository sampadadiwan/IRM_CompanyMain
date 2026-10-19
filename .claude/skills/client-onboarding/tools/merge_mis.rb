# Merges a client's several MIS files for one month into ONE workbook, one sheet per statement (importer-behaviour.md
# › "KPI workbooks": a KPI report takes one "KPIs" workbook and the reader reads every visible sheet of it).
# Each sheet is copied cell for cell at the same row/column positions — dates as dates, numbers as numbers, formulas as
# their computed values — so a verdict ref such as "P&L!C8" points at the same cell as in the client's sheet. After
# writing, every non-blank cell is compared with its source; any difference fails the run.
#
# Usage: ruby merge_mis.rb OUT.xlsx "P&L=path/to/pl.xlsx|Summary" "Cash Flow=path/to/cf.xlsx|Cashflow FY25-26"
#   each argument: <sheet name in OUT>=<source file>|<source sheet>
require "roo"
require "caxlsx"

out = ARGV.shift
abort File.read(__FILE__).lines.grep(/^# Usage/).join if out.nil? || ARGV.empty?
specs = ARGV.map do |arg|
  m = arg.match(/\A(.+?)=(.+)\|(.+)\z/) or abort "bad spec #{arg.inspect} — expected \"Sheet=file|source sheet\""
  m.captures
end

# ① Copy each source sheet into its own sheet of OUT
Axlsx::Package.new do |p|
  date_style = p.workbook.styles.add_style(format_code: "dd-mmm-yyyy")
  specs.each do |name, file, sheet|
    src = Roo::Spreadsheet.open(file).sheet(sheet)
    p.workbook.add_worksheet(name:) do |ws|
      # Every row from 1 and every column from A, so positions match the source exactly
      (1..src.last_row.to_i).each do |r|
        values = (1..src.last_column.to_i).map { |c| src.cell(r, c) }
        types = values.map { |v| v.is_a?(Date) ? :date : (v.is_a?(Numeric) ? :float : :string) }
        ws.add_row values, types:, style: values.map { |v| v.is_a?(Date) ? date_style : nil }
      end
    end
  end
  p.serialize(out)
end

# ② Prove the copy: every non-blank cell of each source sheet equals the same cell of OUT
merged = Roo::Spreadsheet.open(out)
failed = false
specs.each do |name, file, sheet|
  src = Roo::Spreadsheet.open(file).sheet(sheet)
  copy = merged.sheet(name)
  compared = 0
  diffs = []
  (1..src.last_row.to_i).each do |r|
    (1..src.last_column.to_i).each do |c|
      a, b = src.cell(r, c), copy.cell(r, c)
      next if a.nil? && b.nil?

      compared += 1
      same = a.is_a?(Numeric) && b.is_a?(Numeric) ? (a - b).abs < 1e-6 : a.to_s == b.to_s
      diffs << "#{name}!r#{r}c#{c}: #{a.inspect} vs #{b.inspect}" unless same
    end
  end
  failed ||= diffs.any?
  puts "#{name.ljust(12)} ← #{File.basename(file)} / #{sheet}: #{compared} cells compared, #{diffs.size} differ"
  diffs.first(5).each { puts "    ✗ #{_1}" }
end
puts "→ #{out}"
exit(failed ? 1 : 0)
