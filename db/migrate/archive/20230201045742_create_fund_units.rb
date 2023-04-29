class CreateFundUnits < ActiveRecord::Migration[7.0]
  def change
    create_table :fund_units do |t|
      t.references :fund, null: false, foreign_key: true
      t.references :capital_commitment, null: false, foreign_key: true
      t.references :investor, null: false, foreign_key: true
      t.string :unit_type, limit: 10
      t.integer :quantity
      t.text :reason

      t.timestamps
    end
  end
end
