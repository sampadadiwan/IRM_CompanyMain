class CreateEvent < ActiveRecord::Migration[7.1]
  def change
    create_table :events do |t|
      t.string :title, null: false
      t.text :description

      t.datetime :start_time, null: false
      t.datetime :end_time, null: false

      t.references :owner, polymorphic: true, null: false
      t.references :entity, null: false, foreign_key: true

      t.timestamps
    end

    add_index :events, [:owner_type, :owner_id], name: "index_events_on_owner_type_and_owner_id"
  end

  def down
    remove_index :events, name: "index_events_on_owner_type_and_owner_id"
    drop_table :events
  end
end
