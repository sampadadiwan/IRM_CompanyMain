class AddOtherFeesToCapitalCommitment < ActiveRecord::Migration[7.1]
  def change
    add_column :capital_commitments, :other_fee_cents, :decimal, precision: 20, scale: 2, default: 0.0
    CapitalRemittance.counter_culture_fix_counts
  end
end
