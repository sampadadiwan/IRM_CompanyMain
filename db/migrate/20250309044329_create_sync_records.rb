class CreateSyncRecords < ActiveRecord::Migration[7.2]
  def change
    create_table :sync_records do |t|
      t.references :syncable, polymorphic: true, null: false, index: true
      t.string :openwebui_id, index: true
      t.datetime :synced_at
      t.timestamps
    end
  end
end
