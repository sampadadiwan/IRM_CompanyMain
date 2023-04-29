class CreateAccountEntries < ActiveRecord::Migration[7.0]
  def change
    create_table :account_entries do |t|
      t.references :capital_commitment, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      t.references :investor, null: false, foreign_key: true
      t.references :form_type, null: true, foreign_key: true
      t.string :folio_id, limit: 20
      t.date :reporting_date
      t.string :entry_type, limit: 10
      t.string :name, limit: 50
      t.decimal :amount_cents, precision: 20, scale: 2, default: "0.0"
      t.text :notes
      t.text :properties
      t.timestamps
    end
  end
end
