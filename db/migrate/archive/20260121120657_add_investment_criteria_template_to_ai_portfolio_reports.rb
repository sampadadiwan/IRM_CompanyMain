class AddInvestmentCriteriaTemplateToAiPortfolioReports < ActiveRecord::Migration[8.1]
  def change
    add_reference :ai_portfolio_reports, :investment_criteria_template, 
                  foreign_key: true, null: true
  end
end
