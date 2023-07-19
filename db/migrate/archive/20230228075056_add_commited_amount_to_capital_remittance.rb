class AddCommitedAmountToCapitalRemittance < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_remittances, :committed_amount_cents, :decimal, precision: 20, scale: 2, default: "0.0"

    CapitalRemittance.all.each do |cr|
      cr.committed_amount_cents = cr.capital_commitment.committed_amount_cents
      cr.save
    end
  end
end
