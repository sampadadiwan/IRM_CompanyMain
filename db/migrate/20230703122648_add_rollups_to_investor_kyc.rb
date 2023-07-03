class AddRollupsToInvestorKyc < ActiveRecord::Migration[7.0]
  def change
    add_column :investor_kycs, :committed_amount_cents, :decimal, precision: 20, scale: 2, default: "0.0"
    add_column :investor_kycs, :call_amount_cents, :decimal, precision: 20, scale: 2, default: "0.0"
    add_column :investor_kycs, :collected_amount_cents, :decimal, precision: 20, scale: 2, default: "0.0"
    add_column :investor_kycs, :distribution_amount_cents, :decimal, precision: 20, scale: 2, default: "0.0"
  end
end
