class AddIncomeToCapitalDistribution < ActiveRecord::Migration[7.2]
  def change
    # Curr gross - reinvestment = net_amount
    add_column :capital_distributions, :income_cents, :decimal, precision: 20, scale: 2, default: 0.0, null: false
    add_column :distribution_fees, :fee_type, :string, limit: 20

    CapitalDistribution.update_all("income_cents = gross_amount_cents - cost_of_investment_cents")
  end
end
