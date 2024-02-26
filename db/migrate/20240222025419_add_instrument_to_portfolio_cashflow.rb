class AddInstrumentToPortfolioCashflow < ActiveRecord::Migration[7.1]
  def change
    add_reference :portfolio_cashflows, :investment_instrument, null: true, foreign_key: true
    PortfolioCashflow.joins(:aggregate_portfolio_investment).update_all("portfolio_cashflows.investment_instrument_id=aggregate_portfolio_investments.investment_instrument_id") 
    change_column_null :portfolio_cashflows, :investment_instrument_id, false
  end
end
