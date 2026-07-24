# frozen_string_literal: true

# One-time script to generate Excel test fixtures for KPI parser cucumber tests.
# Run: ruby script/generate_kpi_test_fixtures.rb
#
# Generates 4 fixture files in public/sample_uploads/kpi_extraction/:
#   1. tag_columns.xlsx       — ACT/BUDGET/IC tag row below date header
#   2. indent_children.xlsx   — Parent-child via cell indent formatting
#   3. column_children.xlsx   — Parent-child via column A/B layout
#   4. apostrophe_dates.xlsx  — Apr'25 style date headers

require 'rubyXL'
require 'rubyXL/convenience_methods'

OUTPUT_DIR = File.expand_path('../../public/sample_uploads/kpi_extraction', __FILE__)

# Helper: write a value to a cell, creating it if needed
def write_cell(ws, row, col, value)
  ws.add_cell(row, col, value)
end

# Helper: set indent on a cell (cell must already exist)
def set_indent(ws, row, col, indent_level)
  cell = ws[row]&.[](col)
  return unless cell

  cell.change_horizontal_alignment('left')
  xf = cell.get_cell_xf
  xf.alignment ||= RubyXL::Alignment.new
  xf.alignment.indent = indent_level
  xf.apply_alignment = true
end

# ---------------------------------------------------------------------------
# Fixture 1: tag_columns.xlsx
# Single sheet with ACT/BUDGET/IC tag row below the date header.
# Row 0: Header labels (KPI name + dates)
# Row 1: Tag row (ACT, ACT, ACT, BUDGET, BUDGET, BUDGET, IC, IC, IC)
# Row 2+: Data rows
# ---------------------------------------------------------------------------
def generate_tag_columns
  wb = RubyXL::Workbook.new
  ws = wb.worksheets[0]
  ws.sheet_name = 'P&L'

  months = ['Apr 25', 'May 25', 'Jun 25']
  tags = ['ACT', 'BUDGET', 'IC']

  # Row 0: header — KPI label + 9 date columns (3 months × 3 tags)
  write_cell(ws, 0, 0, 'KPI')
  col = 1
  tags.each do |_tag|
    months.each do |month|
      write_cell(ws, 0, col, month)
      col += 1
    end
  end

  # Row 1: tag row
  write_cell(ws, 1, 0, nil)
  col = 1
  tags.each do |tag|
    months.size.times do
      write_cell(ws, 1, col, tag)
      col += 1
    end
  end

  # Row 2+: KPI data
  kpis = {
    'Revenue'  => [100, 110, 120, 95, 105, 115, 90, 100, 110],
    'EBITDA'   => [20, 22, 25, 18, 20, 23, 17, 19, 22],
    'Net Profit' => [10, 12, 14, 8, 10, 12, 7, 9, 11]
  }

  kpis.each_with_index do |(name, values), idx|
    row = idx + 2
    write_cell(ws, row, 0, name)
    values.each_with_index do |val, ci|
      write_cell(ws, row, ci + 1, val)
    end
  end

  path = File.join(OUTPUT_DIR, 'tag_columns.xlsx')
  wb.write(path)
  puts "Created: #{path}"
end

# ---------------------------------------------------------------------------
# Fixture 2: indent_children.xlsx
# Parent-child KPIs using cell indent formatting.
# Net Sales (indent 0)
#   Enterprise (indent 1)
#   Mid-Market (indent 1)
#   SMB (indent 1)
# Operating Cost (indent 0)
#   Enterprise (indent 1)    ← duplicate child name under different parent
#   Mid-Market (indent 1)
# ---------------------------------------------------------------------------
def generate_indent_children
  wb = RubyXL::Workbook.new
  ws = wb.worksheets[0]
  ws.sheet_name = 'P&L'

  months = ['Apr 25', 'May 25', 'Jun 25']

  # Row 0: header
  write_cell(ws, 0, 0, 'KPI')
  months.each_with_index { |m, i| write_cell(ws, 0, i + 1, m) }

  # Row 1+: KPI data with indentation
  rows = [
    # [name, indent, values]
    ['Net Sales',      0, [1000, 1100, 1200]],
    ['Enterprise',     1, [500, 550, 600]],
    ['Mid-Market',     1, [300, 330, 360]],
    ['SMB',            1, [200, 220, 240]],
    ['Operating Cost', 0, [800, 850, 900]],
    ['Enterprise',     1, [400, 420, 440]],
    ['Mid-Market',     1, [400, 430, 460]]
  ]

  rows.each_with_index do |(name, indent, values), idx|
    row = idx + 1
    write_cell(ws, row, 0, name)
    values.each_with_index { |val, ci| write_cell(ws, row, ci + 1, val) }
    set_indent(ws, row, 0, indent) if indent.positive?
  end

  path = File.join(OUTPUT_DIR, 'indent_children.xlsx')
  wb.write(path)
  puts "Created: #{path}"
end

# ---------------------------------------------------------------------------
# Fixture 3: column_children.xlsx
# Column-based parent-child: parents in column A, children in column B.
# When a parent row has a value in A, column B is blank.
# When a child row has a value in B, column A is blank.
# Values start from column C.
# ---------------------------------------------------------------------------
def generate_column_children
  wb = RubyXL::Workbook.new
  ws = wb.worksheets[0]
  ws.sheet_name = 'P&L'

  months = ['Apr 25', 'May 25', 'Jun 25']

  # Row 0: header — col A = parent label, col B = child label, col C+ = dates
  write_cell(ws, 0, 0, 'KPI')
  write_cell(ws, 0, 1, nil)
  months.each_with_index { |m, i| write_cell(ws, 0, i + 2, m) }

  # Rows: parent/child layout
  # [col_a, col_b, values...]
  rows = [
    ['Net Sales',      nil,          [1000, 1100, 1200]],
    [nil,              'Enterprise', [500, 550, 600]],
    [nil,              'Mid-Market', [300, 330, 360]],
    [nil,              'SMB',        [200, 220, 240]],
    ['Operating Cost', nil,          [800, 850, 900]],
    [nil,              'Enterprise', [400, 420, 440]],
    [nil,              'Mid-Market', [400, 430, 460]]
  ]

  rows.each_with_index do |(col_a, col_b, values), idx|
    row = idx + 1
    write_cell(ws, row, 0, col_a) if col_a
    write_cell(ws, row, 1, col_b) if col_b
    values.each_with_index { |val, ci| write_cell(ws, row, ci + 2, val) }
  end

  path = File.join(OUTPUT_DIR, 'column_children.xlsx')
  wb.write(path)
  puts "Created: #{path}"
end

# ---------------------------------------------------------------------------
# Fixture 4: apostrophe_dates.xlsx
# Header row uses apostrophe-delimited date format: Apr'25, May'25, Jun'25
# ---------------------------------------------------------------------------
def generate_apostrophe_dates
  wb = RubyXL::Workbook.new
  ws = wb.worksheets[0]
  ws.sheet_name = 'MIS'

  months = ["Apr'25", "May'25", "Jun'25"]

  # Row 0: header
  write_cell(ws, 0, 0, 'KPI')
  months.each_with_index { |m, i| write_cell(ws, 0, i + 1, m) }

  # Row 1+: data
  kpis = {
    'Revenue'    => [100, 110, 120],
    'EBITDA'     => [20, 22, 25],
    'Net Profit' => [10, 12, 14]
  }

  kpis.each_with_index do |(name, values), idx|
    row = idx + 1
    write_cell(ws, row, 0, name)
    values.each_with_index { |val, ci| write_cell(ws, row, ci + 1, val) }
  end

  path = File.join(OUTPUT_DIR, 'apostrophe_dates.xlsx')
  wb.write(path)
  puts "Created: #{path}"
end

# ---------------------------------------------------------------------------
# Run all generators
# ---------------------------------------------------------------------------
puts "Generating KPI test fixtures in #{OUTPUT_DIR}..."
generate_tag_columns
generate_indent_children
generate_column_children
generate_apostrophe_dates
puts "Done! 4 fixture files created."
