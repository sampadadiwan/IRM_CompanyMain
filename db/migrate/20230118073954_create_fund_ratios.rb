class CreateFundRatios < ActiveRecord::Migration[7.0]
  def change
    create_table :fund_ratios do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      t.references :valuation, null: false, foreign_key: true
      t.string :name, limit: 30
      t.decimal :value
      t.string :display_value, limit: 20
      t.text :notes

      t.timestamps
      t.datetime :deleted_at
      t.index :deleted_at    
    end
  end
end
