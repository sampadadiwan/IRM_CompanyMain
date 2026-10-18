# Duplicate entity_settings rows (funds-json-api-hardening P5 — Orios trial, worked example H25).
#
# A PATCH of entity_setting_attributes without an id built a second settings row for the entity;
# has_one then read one of them. This keeps the row the app reads TODAY (entity.entity_setting), so no
# entity's effective settings change, lists every other row with the values that differ, and — only
# with EXECUTE=1 — deletes those extra rows (hard delete: soft-deleted rows would still break the
# unique index) and adds the unique index on entity_settings.entity_id.
#
#   bundle exec rake entities:dedupe_settings            # dry run: report only
#   EXECUTE=1 bundle exec rake entities:dedupe_settings  # delete the extras, add the index
#
# Run per environment (production.in and production.us are independent).
namespace :entities do
  desc "Report (and with EXECUTE=1 remove) duplicate entity_settings rows; then add the unique index"
  task dedupe_settings: :environment do
    execute = ENV["EXECUTE"] == "1"
    index_name = "index_entity_settings_on_entity_id_unique"
    # Includes soft-deleted rows: they would also break the unique index
    dup_entity_ids = EntitySetting.unscoped.group(:entity_id).having("COUNT(*) > 1").pluck(:entity_id)
    puts "#{dup_entity_ids.size} entities with duplicate settings rows#{' (dry run)' unless execute}"

    dup_entity_ids.each do |entity_id|
      entity = Entity.find_by(id: entity_id)
      # The row the app reads today; an entity that no longer exists keeps its lowest-id row
      kept = entity&.entity_setting || EntitySetting.unscoped.where(entity_id:).order(:id).first
      extras = EntitySetting.unscoped.where(entity_id:).where.not(id: kept.id).order(:id)

      extras.each do |extra|
        # The values support should review before the extra row goes
        differing = extra.attributes.except("id", "created_at", "updated_at", "deleted_at")
                         .reject { |k, v| kept.attributes[k] == v }
        soft = extra.deleted_at ? " (soft-deleted)" : ""
        puts "entity #{entity_id}: keep #{kept.id}, #{execute ? 'delete' : 'would delete'} #{extra.id}#{soft} " \
             "— differs in #{differing.keys.join(', ').presence || 'nothing'}"
        differing.each { |k, v| puts "    #{k}: kept=#{kept.attributes[k].inspect} extra=#{v.inspect}" }
      end

      # Hard delete, in one statement per entity, only when asked
      extras.delete_all if execute
    end

    next unless execute

    # Once no duplicates remain, the unique index the migration skipped can go on
    conn = ActiveRecord::Base.connection
    if conn.index_exists?(:entity_settings, :entity_id, name: index_name)
      puts "Unique index already present."
    else
      conn.add_index :entity_settings, :entity_id, unique: true, name: index_name
      puts "Unique index #{index_name} added."
    end
  end
end
