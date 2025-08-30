class AddValuationToPortfolioInvestment < ActiveRecord::Migration[8.0]
  def change
    add_reference :portfolio_investments, :valuation, null: true, foreign_key: true

    PortfolioInvestment.all.each do |pi|
      pi.update(valuation: pi.valuations.order(valuation_date: :desc, id: :desc).first)
    end
  end
end
