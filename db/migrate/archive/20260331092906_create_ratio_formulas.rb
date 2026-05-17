class CreateRatioFormulas < ActiveRecord::Migration[8.1]
  def change
    create_table :ratio_formulas do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      t.string :level
      t.json :ratios
      t.string :action
      t.json :account_entry_names
      t.string :period
      t.datetime :deleted_at

      t.timestamps
    end
    add_index :ratio_formulas, :deleted_at
  end
end
