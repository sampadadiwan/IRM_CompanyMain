class CreateCommitmentAdjustments < ActiveRecord::Migration[7.0]
  def change
    create_table :commitment_adjustments do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      t.references :capital_commitment, null: false, foreign_key: true
      t.decimal :pre_adjustment_cents, precision: 20, scale: 2, default: 0
      t.decimal :amount_cents, precision: 20, scale: 2, default: 0
      t.decimal :folio_amount_cents, precision: 20, scale: 2, default: 0
      t.decimal :post_adjustment_cents, precision: 20, scale: 2, default: 0
      t.text :reason
      t.date :as_of

      t.timestamps
    end

    add_column :capital_commitments, :adjustment_amount_cents, :decimal, precision: 20, scale: 2, default: 0
    add_column :capital_commitments, :adjustment_folio_amount_cents, :decimal, precision: 20, scale: 2, default: 0
    add_column :capital_commitments, :orig_committed_amount_cents, :decimal, precision: 20, scale: 2, default: 0
    add_column :capital_commitments, :orig_folio_committed_amount_cents, :decimal, precision: 20, scale: 2, default: 0

    CapitalCommitment.update_all("orig_committed_amount_cents=committed_amount_cents, orig_folio_committed_amount_cents=folio_committed_amount_cents")
  end
end
