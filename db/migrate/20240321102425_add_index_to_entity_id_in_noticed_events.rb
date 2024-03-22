class AddIndexToEntityIdInNoticedEvents < ActiveRecord::Migration[7.1]
  def up
    execute 'ALTER TABLE noticed_events ADD COLUMN entity_id BIGINT GENERATED ALWAYS AS (params->"$.entity_id");'
    add_index :noticed_events, :entity_id
  end

  def down
    remove_column :noticed_events, :entity_id
  end
end
