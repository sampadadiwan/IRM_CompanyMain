class AddOtherFeesToInvestorKyc < ActiveRecord::Migration[7.1]
  def change
    add_column :investor_kycs, :other_fee_cents, :decimal, precision: 12, scale: 2, default: 0.0
  end
end
