#!/usr/bin/env ruby
# frozen_string_literal: true

# Sync db/schema_test.rb from db/schema.rb
#
# Transforms the MySQL-generated schema.rb into a SQLite3-compatible schema_test.rb:
#   - Strips MySQL-specific options (charset, collation, partitions, primary_key arrays)
#   - Converts virtual columns to real columns following established patterns
#   - Fixes check constraint quoting for SQLite
#   - Preserves manually-added SQLite customizations (e.g. collation: "NOCASE")
#
# Usage: ruby bin/sync_schema_test.rb

SCHEMA_PATH = File.join(__dir__, '..', 'db', 'schema.rb')
TEST_SCHEMA_PATH = File.join(__dir__, '..', 'db', 'schema_test.rb')
CACHE_SCHEMA_PATH = File.join(__dir__, '..', 'db', 'cache_schema.rb')

# ──────────────────────────────────────────────
# 1. Read files
# ──────────────────────────────────────────────

source = File.read(SCHEMA_PATH)
existing_test = File.read(TEST_SCHEMA_PATH)

# ──────────────────────────────────────────────
# 2. Extract version from schema.rb
# ──────────────────────────────────────────────

VERSION_REGEX = /ActiveRecord::Schema\[\d+\.\d+\]\.define\(version:\s*(\d[\d_]*)\)/

def extract_version(content)
  match = content.match(VERSION_REGEX)
  match ? match[1] : nil
end

version = extract_version(source)
raise "Could not find schema version in #{SCHEMA_PATH}" unless version

puts "Syncing schema_test.rb to version #{version}..."

# ──────────────────────────────────────────────
# 3. Parse schema.rb into blocks
# ──────────────────────────────────────────────

# Returns array of { type: :header|:footer, lines: [...] }
#              or { type: :table, name:, header_lines:, body_lines:, end_line: }
def parse_schema_blocks(lines)
  blocks = []

  # Header: everything before first "  create_table"
  table_start = lines.index { |l| l.match?(/^\s{2}create_table "/) }
  raise "No create_table found in schema.rb" unless table_start

  blocks << { type: :header, lines: lines[0...table_start] }

  # Process each create_table block
  i = table_start
  while i < lines.length
    # Skip blank lines between tables
    i += 1 while i < lines.length && lines[i].strip.empty?
    break if i >= lines.length
    break unless lines[i].match?(/^\s{2}create_table "/)
    # Find the create_table header (may span multiple lines due to options:)
    header_start = i
    i += 1 while i < lines.length && !lines[i].include?("do |t|")
    raise "Could not find 'do |t|' for create_table starting at line #{header_start + 1}" unless i < lines.length

    header_lines = lines[header_start..i]

    # Body starts after "do |t|" line
    i += 1
    body_start = i

    # Find closing "end" at 2-space indent
    while i < lines.length
      break if lines[i].match?(/^\s{2}end\s*$/)
      i += 1
    end
    raise "Could not find closing 'end' for create_table starting at line #{header_start + 1}" unless i < lines.length

    body_lines = lines[body_start...i]
    end_line = lines[i]

    # Extract table name from create_table line
    name_match = header_lines.first.match(/create_table "([^"]+)"/)
    table_name = name_match ? name_match[1] : "unknown"

    blocks << {
      type: :table,
      name: table_name,
      header_lines: header_lines,
      body_lines: body_lines,
      end_line: end_line
    }

    i += 1
  end

  # Footer: everything after last table end
  blocks << { type: :footer, lines: lines[i..] } if i < lines.length

  blocks
end

source_lines = source.lines
blocks = parse_schema_blocks(source_lines)

# ──────────────────────────────────────────────
# 4. Extract customizations from old schema_test.rb
# ──────────────────────────────────────────────

# Build a map: table_name => { column_index => original_line }
# to preserve manual SQLite-specific tweaks
def parse_table_bodies(content)
  tables = {}
  lines = content.lines
  i = 0

  while i < lines.length
    if lines[i].match?(/^\s{2}create_table "/)
      name_match = lines[i].match(/create_table "([^"]+)"/)
      table_name = name_match ? name_match[1] : "unknown"

      # Find "do |t|"
      i += 1 while i < lines.length && !lines[i].include?("do |t|")
      i += 1 if i < lines.length
      body_start = i

      # Find closing "end"
      while i < lines.length
        break if lines[i].match?(/^\s{2}end\s*$/)
        i += 1
      end

      body_lines = lines[body_start...i]
      tables[table_name] = body_lines
      i += 1 if i < lines.length
    else
      i += 1
    end
  end

  tables
end

existing_tables = parse_table_bodies(existing_test)

# Extract customizations from existing body lines
# For each column line in old schema_test.rb, extract extra options not in schema.rb
def extract_column_customizations(table_bodies)
  customizations = {} # table_name => { "col_name" => extra_options_string }

  table_bodies.each do |table_name, body_lines|
    customizations[table_name] = {}

    body_lines.each do |line|
      # Match lines like: t.type "col_name", opt1: val1, opt2: val2
      # We care about extra modifiers like collation: "NOCASE"
      match = line.match(/^\s{4}t\.\w+\s+"([^"]+)"(.*)$/)
      next unless match

      col_name = match[1]
      options_str = match[2].strip.chomp(",")

      next if options_str.empty?

      # Extract non-standard options (those not typically in schema.rb)
      # Specifically look for collation: "NOCASE" which is the main SQLite customization
      extra_opts = []
      extra_opts << "collation: \"NOCASE\"" if options_str.include?('collation: "NOCASE"')

      # Check for any collation that differs from what schema.rb would produce
      # (schema.rb may have collation: "utf8mb4_bin" which should become collation: "NOCASE")
      if options_str.match?(/collation: "NOCASE"/)
        customizations[table_name][col_name] = extra_opts
      end
    end
  end

  customizations
end

column_customizations = extract_column_customizations(existing_tables)
nocase_count = column_customizations.sum { |_, cols| cols.length }
puts "  Found #{nocase_count} NOCASE collation customizations to preserve" if nocase_count > 0

# ──────────────────────────────────────────────
# 5. Normalize table blocks
# ──────────────────────────────────────────────

def normalize_create_table_header(header_lines)
  text = header_lines.join("")

  # Check if we need id: false (tables with composite primary_key stripped)
  had_composite_pk = text.match?(/primary_key:\s*\[/)

  # Remove options: "..." (multi-line string, may span several lines)
  text = text.gsub(/,\s*options: "[^"]*"/m, "")

  # Remove primary_key: [...] or primary_key: :symbol
  text = text.gsub(/,\s*primary_key: (\[[^\]]*\]|:\w+)/, "")

  # Remove charset: "..."
  text = text.gsub(/,\s*charset: "[^"]+"/, "")

  # Remove collation: "..."
  text = text.gsub(/,\s*collation: "[^"]*"/, "")

  # Clean up double/multiple commas
  text = text.gsub(/,\s*,/, ",")

  # Restore single line (remove extra newlines introduced by multi-line options)
  text = text.gsub(/\n\s*/, " ")

  # Ensure clean spacing around do |t|
  text = text.gsub(/\s+do \|t\|/, " do |t|")

  # Ensure trailing newline
  text = text.sub(/\n*\z/, "") << "\n"

  # Return composite_pk flag and the single header line
  [had_composite_pk, text]
end

def normalize_body_line(line)
  # Skip empty lines
  return line if line.strip.empty?

  # ── Handle virtual columns ──

  # Pattern 1: generated_deleted virtual columns
  #   t.virtual "generated_deleted", type: :datetime, ..., as: "ifnull(`col`,_utf8mb4'DEFAULT')"
  # → t.datetime "generated_deleted", default: "DEFAULT", ...
  if line =~ /t\.virtual "generated_deleted"/
    # Extract the type
    type_match = line.match(/type:\s*:(\w+)/)
    col_type = type_match ? type_match[1] : "datetime"

    # Extract null: false if present
    has_null = line.include?("null: false")

    # Extract default from as: "ifnull(`col`,_utf8mb4'DEFAULT')"
    default_match = line.match(/_utf8mb4'([^']+)'\)"/)
    default_value = default_match ? default_match[1] : "1900-01-01 00:00:00"

    # Extract precision: nil if present
    has_precision = line.include?("precision: nil")

    parts = ["t.#{col_type} \"generated_deleted\""]
    parts << "precision: nil" if has_precision
    parts << "default: \"#{default_value}\""
    parts << "null: false" if has_null

    return "    #{parts.join(', ')}\n"
  end

  # Pattern 2: Other virtual columns (like entity_id with json_extract)
  #   t.virtual "entity_id", type: :bigint, as: "json_extract(...)"
  # → t.virtual "entity_id", type: :bigint  (strip as: clause)
  if line =~ /t\.virtual/
    line = line.gsub(/,\s*as: "[^"]*"/, "")
    return line
  end

  # ── Strip column-level MySQL collation ──
  # e.g., t.string "ancestry", collation: "utf8mb4_bin" → t.string "ancestry"
  line = line.gsub(/,\s*collation: "utf8mb[^"]*"/, "")

  # ── Strip auto_increment (MySQL-specific, not valid in SQLite) ──
  line = line.gsub(/,\s*auto_increment: true/, "")

  # ── Strip null: false from boolean columns ──
  # Boolean columns with null: false can cause issues in SQLite; strip it
  # but preserve other options like default:
  if line =~ /t\.boolean/
    line = line.gsub(/,\s*null:\s*false/, "")
  end

  # ── Strip size: option (MySQL-specific for text/binary types) ──
  # e.g., t.text "body", size: :long → t.text "body"
  line = line.gsub(/,\s*size:\s*:\w+/, "")

  # ── Fix check constraints ──

  # Convert backtick-quoted identifiers to single-quoted: `col` → 'col'
  line = line.gsub("`", "'")

  # Remove MySQL charset prefix from string literals: _utf8mb4'val' → 'val'
  line = line.gsub(/_utf8mb4'/, "'")

  # ── Fix MySQL-only index options ──
  if line =~ /t\.index/
    # Strip type: :fulltext (MySQL FULLTEXT index, not supported in SQLite)
    line = line.gsub(/,\s*type:\s*:fulltext/, "")
    # Strip length: {...} (MySQL prefix index, not supported in SQLite)
    line = line.gsub(/,\s*length:\s*\{[^}]*\}/, "")
  end

  line
end

def normalize_table_block(block)
  had_composite_pk, normalized_header = normalize_create_table_header(block[:header_lines])
  normalized_body = block[:body_lines].map { |line| normalize_body_line(line) }

  # When a composite primary key was stripped, remove the explicit t.bigint "id"
  # column from the body. Rails auto-creates id as the primary key (alias for
  # rowid in SQLite, which auto-increments). Having both causes a conflict.
  if had_composite_pk
    normalized_body.reject! { |line| line.match?(/t\.(bigint|integer)\s+"id"/) }
  end

  {
    type: :table,
    name: block[:name],
    header_lines: [normalized_header],
    body_lines: normalized_body,
    end_line: block[:end_line]
  }
end

# ──────────────────────────────────────────────
# 6. Merge SQLite customizations
# ──────────────────────────────────────────────

def merge_customizations(block, column_customizations)
  return block unless column_customizations[block[:name]]

  table_customizations = column_customizations[block[:name]]
  return block if table_customizations.empty?

  body_lines = block[:body_lines].map do |line|
    next line unless line =~ /^\s{4}t\.\w+\s+"([^"]+)"/

    col_name = Regexp.last_match(1)
    custom_opts = table_customizations[col_name]
    next line unless custom_opts&.any?

    # Remove trailing newline for processing, add it back at the end
    modified = line.sub(/\n\z/, "")

    custom_opts.each do |opt|
      key = opt.split(":").first.strip
      # Don't add if already present
      next if modified.include?("#{key}:")

      modified << ", #{opt}"
    end

    modified << "\n"
  end

  block.merge(body_lines: body_lines)
end

# ──────────────────────────────────────────────
# 7. Assemble output
# ──────────────────────────────────────────────

def assemble_output(blocks, version, column_customizations)
  output_lines = []

  blocks.each do |block|
    case block[:type]
    when :header
      # Update version in the define line
      block[:lines].each do |line|
        if line =~ VERSION_REGEX
          output_lines << line.sub(/(version:\s*)\d[\d_]*/, "\\1#{version}")
        else
          output_lines << line
        end
      end

    when :table
      normalized = normalize_table_block(block)
      merged = merge_customizations(normalized, column_customizations)

      output_lines.concat(merged[:header_lines])
      output_lines.concat(merged[:body_lines])
      output_lines << merged[:end_line]

    when :footer
      output_lines.concat(block[:lines])
    end
  end

  output_lines.join("")
end

output = assemble_output(blocks, version, column_customizations)

# ──────────────────────────────────────────────
# 8. Write output
# ──────────────────────────────────────────────

File.write(TEST_SCHEMA_PATH, output)
puts "✅ Updated #{TEST_SCHEMA_PATH} to version #{version}"
