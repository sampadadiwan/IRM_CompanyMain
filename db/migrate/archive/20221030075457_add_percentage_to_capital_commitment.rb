class AddPercentageToCapitalCommitment < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_commitments, :percentage, :decimal, precision: 5, scale: 2, default: "0.0"
    add_column :capital_distribution_payments, :percentage, :decimal, precision: 5, scale: 2, default: "0.0"
  end
end
