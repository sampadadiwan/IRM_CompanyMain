# Pretty-prints models/collections/hashes as terminal tables in cucumber
# step definitions, replacing raw `puts x.to_json` / `ap x` debug output.
#
# Usage:
#   print_table(@user)                 # single record -> one-row wide table
#   print_table(@user, title: "User")  # same, with a header line above it
#   print_table(Fund.all)              # collection of records -> grid, one row per record
#   print_table(@investor, @investor2) # two+ records -> side-by-side comparison
#   print_table(some_hash)             # Key | Value table
#   print_table(doc.pluck(:status))    # array of scalars -> single-column table

MAX_TABLE_ROWS = 20 # cap grid/comparison output so a huge collection doesn't flood the log
WIDE_TABLE_MAX_COLS = 8 # above this, a single-row wide table becomes an unreadable one-liner

def print_table(*objs, title: nil)
  puts "\n#### #{title} ####\n" if title

  if objs.size > 1
    # Multiple args: only meaningful as a side-by-side comparison of records.
    if objs.all? { |o| o.is_a?(ActiveRecord::Base) }
      print_table_comparison(objs)
    else
      objs.each { |o| print_table(o) } # fall back to printing each one separately
    end
    return
  end

  obj = objs.first
  case obj
  when ActiveRecord::Relation, Array
    if obj.first.is_a?(ActiveRecord::Base)
      print_table_grid(obj.to_a)
    else
      print_table_scalars(obj)
    end
  when Hash
    print_table_hash(obj)
  when ActiveRecord::Base
    print_table_wide(obj)
  else
    ap obj # not a shape we know how to tableize, fall back to awesome_print
  end
end

# Renders a table cell value; nested structures are compacted to JSON so the
# table doesn't grow extra rows/columns for a single field.
def format_table_cell(value)
  case value
  when Hash, Array
    value.to_json
  when nil
    "nil"
  else
    value.to_s
  end
end

# Single record: one column per attribute, one row of values.
# Falls back to the tall Attribute|Value layout once there are too many
# attributes for a single row to stay readable (e.g. User has 53 columns).
def print_table_wide(record)
  data = record.as_json
  if data.size > WIDE_TABLE_MAX_COLS
    print_table_hash(data)
    return
  end

  table = Terminal::Table.new(headings: data.keys, rows: [data.values.map { |v| format_table_cell(v) }])
  puts table
end

# Collection of records: one row per record, columns = attributes of the first record.
def print_table_grid(records)
  if records.empty?
    puts "(empty)"
    return
  end

  visible = records.first(MAX_TABLE_ROWS)
  headings = visible.first.as_json.keys
  rows = visible.map { |r| headings.map { |h| format_table_cell(r.as_json[h]) } }
  table = Terminal::Table.new(headings: headings, rows: rows)
  puts table
  puts "... #{records.size - MAX_TABLE_ROWS} more rows omitted" if records.size > MAX_TABLE_ROWS
end

# Two or more records: attributes as rows, one column per record, for diffing side by side.
def print_table_comparison(records)
  visible = records.first(MAX_TABLE_ROWS)
  labels = visible.map.with_index { |r, i| "#{r.class.name}##{r.id || i}" }
  keys = visible.first.as_json.keys
  rows = keys.map { |k| [k] + visible.map { |r| format_table_cell(r.as_json[k]) } }
  table = Terminal::Table.new(headings: ["Attribute"] + labels, rows: rows)
  puts table
  puts "... #{records.size - MAX_TABLE_ROWS} more records omitted" if records.size > MAX_TABLE_ROWS
end

def print_table_hash(hash)
  rows = hash.map { |k, v| [k, format_table_cell(v)] }
  table = Terminal::Table.new(headings: %w[Key Value], rows: rows)
  puts table
end

def print_table_scalars(values)
  visible = values.first(MAX_TABLE_ROWS)
  table = Terminal::Table.new(headings: ["Value"], rows: visible.map { |v| [format_table_cell(v)] })
  puts table
  puts "... #{values.size - MAX_TABLE_ROWS} more values omitted" if values.size > MAX_TABLE_ROWS
end
