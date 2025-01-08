class AddReinvestmentToCapitalDistributionPayment < ActiveRecord::Migration[7.2]
  def change
    add_column :capital_distribution_payments, :reinvestment_cents, :decimal, precision: 20, scale: 2, default: 0.0
    add_column :capital_distribution_payments, :reinvestment_with_fees_cents, :decimal, precision: 20, scale: 2, default: 0.0

    CapitalDistributionPayment.update_all("reinvestment_cents = 0, reinvestment_with_fees_cents = 0")

    
    # CapitalDistributionPayment.joins(:capital_distribution).where.not("distribution_on = ?", ["Upload"]).each do |cdp|
    #   percentage = cdp.capital_distribution.distribution_percentage(cdp.capital_commitment)
    #   reinvestment_cents = cdp.reinvestment_cents * percentage
    #   cdp.update_columns(reinvestment_cents:  , reinvestment_with_fees_cents: reinvestment_cents)
    #   cdp.setup_distribution_fees
    #   cdp.save(validate: false)      
    # end
  end
end
