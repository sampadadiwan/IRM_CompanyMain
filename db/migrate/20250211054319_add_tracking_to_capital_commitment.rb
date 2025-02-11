class AddTrackingToCapitalCommitment < ActiveRecord::Migration[7.2]
  def change
    add_column :funds, :tracking_committed_amount_cents, :decimal, precision: 20, scale: 4, default: 0.0
    add_column :capital_commitments, :tracking_committed_amount_cents, :decimal, precision: 20, scale: 4, default: 0.0
    add_column :capital_commitments, :tracking_orig_committed_amount_cents, :decimal, precision: 20, scale: 4, default: 0.0
    add_column :capital_commitments, :tracking_adjustment_amount_cents, :decimal, precision: 20, scale: 4, default: 0.0
    add_column :commitment_adjustments, :tracking_amount_cents, :decimal, precision: 20, scale: 4, default: 0.0

    Fund.where(tracking_currency: nil).update_all("tracking_currency=currency")
  end
end
