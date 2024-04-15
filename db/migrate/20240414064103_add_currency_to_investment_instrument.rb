class AddCurrencyToInvestmentInstrument < ActiveRecord::Migration[7.1]
  def change
    add_column :investment_instruments, :currency, :string, limit: 5
    add_column :portfolio_investments, :base_amount_cents, :decimal, precision: 20, scale: 2
    add_reference :portfolio_investments, :exchange_rate, foreign_key: true, null: true
    add_column :valuations, :base_amount_cents, :decimal, precision: 20, scale: 2

    puts "Updating InvestmentInstruments with currency"
    InvestmentInstrument.all.each do |instrument|
      json_fields = instrument.json_fields || {}
      currency = instrument.portfolio_investments.first&.fund&.currency || instrument.entity&.currency
      instrument.update!(currency:, json_fields: )
    end

    puts "Updating PortfolioInvestments with base_amount_cents"
    PortfolioInvestment.all.each do |investment|
      # Ensure the base_amount_cents is set
      investment.update!(base_amount_cents: investment.amount_cents)
    end
  end
end
