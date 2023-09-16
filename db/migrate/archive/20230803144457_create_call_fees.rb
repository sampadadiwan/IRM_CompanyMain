class CreateCallFees < ActiveRecord::Migration[7.0]
  def change
    create_table :call_fees do |t|
      t.string :name, limit: 50
      t.date :start_date
      t.date :end_date
      t.string :notes
      t.string :fee_type, limit: 20
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      t.references :capital_call, null: false, foreign_key: true

      t.timestamps
    end
  end
end
