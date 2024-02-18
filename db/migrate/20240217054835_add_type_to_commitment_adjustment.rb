class AddTypeToCommitmentAdjustment < ActiveRecord::Migration[7.1]
  def change
    add_column :commitment_adjustments, :adjustment_type, :string, limit: 20, default: 'Top Up', null: false
    add_column :commitment_adjustments, :deleted_at, :datetime
    add_index :commitment_adjustments, :deleted_at
    add_column :capital_commitments, :arrear_amount_cents, :decimal, precision: 20, scale: 2, default: 0.0
    add_column :capital_commitments, :arrear_folio_amount_cents, :decimal, precision: 20, scale: 2, default: 0.0
  end
end
