# One settings row per entity (funds-json-api-hardening P5 — Orios trial). A PATCH without an id used to
# build a second row; `update_only` stops new duplicates, this index makes them impossible.
#
# Deploy-safe: if duplicates already exist the index is NOT added (the deploy must not fail) and the
# migration says so. Clean them with `bundle exec rake entities:dedupe_settings` (dry run, then
# EXECUTE=1), which adds this index once none remain. Worked example H25.
class AddUniqueIndexToEntitySettings < ActiveRecord::Migration[8.1]
  INDEX = "index_entity_settings_on_entity_id_unique".freeze

  def up
    duplicates = select_value(<<~SQL.squish).to_i
      SELECT COUNT(*) FROM (SELECT entity_id FROM entity_settings GROUP BY entity_id HAVING COUNT(*) > 1) d
    SQL
    if duplicates.positive?
      say "#{duplicates} entities have more than one entity_settings row — unique index NOT added. " \
          "Run `bundle exec rake entities:dedupe_settings` (then EXECUTE=1); it adds the index."
      return
    end

    add_index :entity_settings, :entity_id, unique: true, name: INDEX unless index_exists?(:entity_settings, :entity_id, name: INDEX)
  end

  def down
    remove_index :entity_settings, name: INDEX if index_exists?(:entity_settings, :entity_id, name: INDEX)
  end
end
