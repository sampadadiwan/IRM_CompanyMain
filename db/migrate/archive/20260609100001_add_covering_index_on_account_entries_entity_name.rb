class AddCoveringIndexOnAccountEntriesEntityName < ActiveRecord::Migration[7.1]
  def change
    # Covers SELECT DISTINCT name WHERE entity_id = ? AND deleted_at IS NULL
    # without touching row data across all partitions
    add_index :account_entries, [:entity_id, :deleted_at, :name],
              name: "idx_ae_entity_deleted_name"
  end
end
