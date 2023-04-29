class CreateFundUnitSettings < ActiveRecord::Migration[7.0]
  def change
    create_table :fund_unit_settings do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      t.string :name, limit: 15
      t.decimal :management_fee, precision: 20, scale: 2, default: "0.0"
      t.decimal :setup_fee, precision: 20, scale: 2, default: "0.0"
      t.references :form_type, null: true, foreign_key: true
      t.text :properties
      t.text :notes
      t.timestamps
    end
  end
end
