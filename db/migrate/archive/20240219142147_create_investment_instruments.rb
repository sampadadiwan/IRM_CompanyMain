class CreateInvestmentInstruments < ActiveRecord::Migration[7.1]
  def change
    create_table :investment_instruments do |t|
      t.string :name
      t.string :category, limit: 15
      t.string :sub_category, limit: 100
      t.string :sector, limit: 100
      t.references :entity, null: false, foreign_key: true
      t.references :portfolio_company, null: false, foreign_key: {to_table: :investors}
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :investment_instruments, :deleted_at
  end
end
