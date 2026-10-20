# frozen_string_literal: true

# The link list (join_map.json) — features/support_console/tenant_scope.feature H7, E6.
# The SQL rules themselves are node tests, run with "the support machine tests matching … run".

# H7 — built the way publish_code builds it, from the app's own schema
When("the link list is built from the app's schema") do
  @join_map = SupportConsoleCodeArchive.join_map(Rails.root.join("db/schema.rb").to_s)
end

# E6 — a schema that gained a table, as after a migration
When('the link list is built from a schema where {string} has a foreign key to {string}') do |child_column, parent|
  table, column = child_column.split(".")
  schema = Rails.root.join("tmp/schema_links_#{ENV.fetch('TEST_ENV_NUMBER', '')}_#{SecureRandom.hex(4)}.rb")
  File.write(schema, <<~RUBY)
    ActiveRecord::Schema[8.0].define(version: 1) do
      create_table "#{parent}", force: :cascade do |t|
        t.bigint "entity_id"
      end

      create_table "#{table}", force: :cascade do |t|
        t.bigint "#{column}"
        t.text "body"
      end

      add_foreign_key "#{table}", "#{parent}"
    end
  RUBY
  @join_map = SupportConsoleCodeArchive.join_map(schema.to_s)
ensure
  FileUtils.rm_f(schema) if schema
end

Then('the link list joins {string} to {string}') do |child_column, parent|
  table, column = child_column.split(".")
  expect(@join_map["links"][table]).to include({ "column" => column, "to" => parent })
end

Then('the link list joins {string} by its type {string}') do |child_column, type_column|
  table, column = child_column.split(".")
  expect(@join_map["links"][table]).to include({ "column" => column, "polymorphic" => type_column })
end

Then('the link list names the class of {string} as {string}') do |table, class_name|
  expect(@join_map["classes"][table]).to eq(class_name)
end
