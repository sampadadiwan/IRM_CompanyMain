class AddValuationToPortfolioInvestment < ActiveRecord::Migration[8.0]
  def change
    add_reference :portfolio_investments, :valuation, null: true, foreign_key: true

    PortfolioInvestment.all.each do |pi|
      pi.update_columns(valuation_id: pi.valuations.order(valuation_date: :desc, id: :desc).first&.id)
    end
  end
end
