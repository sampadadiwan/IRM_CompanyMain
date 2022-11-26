class CreateCapitalCommitments < ActiveRecord::Migration[7.0]
  def change
    create_table :capital_commitments do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :investor, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      t.decimal :committed_amount_cents, precision: 20, scale: 2, default: "0.0"
      t.decimal :collected_amount_cents, precision: 20, scale: 2, default: "0.0"
      t.text :notes

      t.timestamps
    end
  end
end
