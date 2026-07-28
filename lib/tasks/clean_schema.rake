# frozen_string_literal: true

# Strips MySQL-specific syntax from schema.rb after migrations so that
# schema_test.rb (loaded by SQLite test DB) contains portable SQL.
namespace :db do
  task :clean_schema do
    schema_path = Rails.root.join("db/schema.rb")
    content = File.read(schema_path)

    # Remove _utf8mb4 charset introducers: _utf8mb4'value' → 'value'
    content.gsub!(/_utf8mb4'/, "'")

    # Remove backtick-quoted identifiers in check_constraint strings
    content.gsub!(/check_constraint\s+"(.*?)"/) do |match|
      match.gsub('`', '')
    end

    # Remove charset/collation from create_table options
    content.gsub!(/,?\s*charset:\s*"[^"]*"/, '')
    content.gsub!(/,?\s*collation:\s*"[^"]*"/, '')

    # Remove size: option from column definitions (MySQL-specific :medium, :long etc.)
    content.gsub!(/,?\s*size:\s*:\w+/, '')

    # Remove type: :fulltext from index definitions (MySQL-specific)
    content.gsub!(/,?\s*type:\s*:fulltext/, '')

    # Remove options: from create_table (MySQL engine/partition definitions)
    content.gsub!(/,?\s*options:\s*"[^"]*"/, '')

    # Remove auto_increment: from column definitions (MySQL-specific)
    content.gsub!(/,?\s*auto_increment:\s*\w+/, '')

    File.write(schema_path, content)

    # Keep schema_test.rb in sync, with SQLite-only rewrites on top:
    # MySQL partitioned tables use a composite primary key (eg ["id", "reporting_date"])
    # with an auto_increment id. SQLite cannot autoincrement a column inside a composite
    # primary key, so rewrite those tables back to the default autoincrementing id pk.
    test_content = content.gsub(/primary_key: \[[^\]]*"id"[^\]]*\],\s*/, "")
    test_content = test_content.gsub(/^\s*t\.bigint "id", null: false\n/, "")

    # SQLite string comparisons are case-sensitive by default, unlike MySQL's default
    # collation. Restore NOCASE on columns the app queries with different casing
    # (eg account_entries.name is stored as "Cash in Hand" but queried as "Cash In Hand").
    test_content = test_content.sub(/(create_table "account_entries".*?t\.string "name", limit: 125)/m) { "#{Regexp.last_match(1)}, collation: \"NOCASE\"" }
    test_content = test_content.sub(/(create_table "investor_kpi_mappings".*?t\.string "ancestry")/m) { "#{Regexp.last_match(1)}, collation: \"NOCASE\"" }
    File.write(Rails.root.join("db/schema_test.rb"), test_content)
  end
end

# Run automatically after every db:migrate
Rake::Task["db:migrate"].enhance do
  Rake::Task["db:clean_schema"].invoke
end
