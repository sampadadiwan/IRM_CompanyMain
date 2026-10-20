# frozen_string_literal: true

# Run with: bin/rails runner support_console/probes/build_join_map.rb
# The checker's inputs, built exactly as publish_code builds them (SupportConsoleCodeArchive):
# the entity_id table list and the link list (join_map.json).
require Rails.root.join("lib/support_console_code_archive").to_s

schema = Rails.root.join("db/schema.rb").to_s
map = SupportConsoleCodeArchive.join_map(schema)
File.write("support_console/probes/out/join_map.json", JSON.pretty_generate(map))
File.write("support_console/probes/out/tables_with_entity_id.json",
           JSON.pretty_generate(SupportConsoleCodeArchive.tables_with_entity_id(schema)))
puts "#{map['links'].size} tables with links, #{map['links'].values.sum(&:size)} links"
