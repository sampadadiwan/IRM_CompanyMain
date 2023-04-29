class CreateFundFormulas < ActiveRecord::Migration[7.0]
  def change
    create_table :fund_formulas do |t|
      t.references :fund, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.string :name, limit: 50
      t.text :description
      t.text :formula

      t.timestamps
    end
  end
end
