class CreateRmMappings < ActiveRecord::Migration[7.1]
  def change
    create_table :rm_mappings do |t|
      t.references :rm, null: false, foreign_key: {to_table: :investors}
      t.references :investor, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.references :rm_entity, null: false, foreign_key: {to_table: :entities}
      t.integer :permissions, default: 0
      t.boolean :approved, default: false

      t.timestamps
    end
  end
end
