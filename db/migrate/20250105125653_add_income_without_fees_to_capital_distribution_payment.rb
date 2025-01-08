class AddIncomeWithoutFeesToCapitalDistributionPayment < ActiveRecord::Migration[7.2]
  def change
    add_column :capital_distribution_payments, :income_with_fees_cents, :decimal, precision: 20, scale: 2, default: 0
    add_column :capital_distribution_payments, :cost_of_investment_with_fees_cents, :decimal, precision: 20, scale: 2, default: 0

    CapitalDistributionPayment.update_all("income_with_fees_cents = income_cents, cost_of_investment_with_fees_cents = cost_of_investment_cents")

    # set to income_cents and cost_of_investment_cents
     
    # CapitalDistributionPayment.joins(:capital_distribution).where.not("distribution_on = ?", ["Upload"]).each do |cdp|
    #   cdp.setup_distribution_fees
    #   cdp.save(validate: false)
    # end
  end
end
