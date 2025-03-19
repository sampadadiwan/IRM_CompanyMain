class AddInvestmentDateToPortfolioAttribution < ActiveRecord::Migration[8.0]
  def change
    add_column :portfolio_attributions, :investment_date, :date

    PortfolioAttribution.all.each do |pa|
      pa.update_columns(investment_date: pa.sold_pi.investment_date)
    end
  end
end
