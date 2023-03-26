class AddFolioToPortfolioInvestment < ActiveRecord::Migration[7.0]
  def change
    add_column :aggregate_portfolio_investments, :commitment_type, :string, limit: 10, default: "Pool"
    add_column :portfolio_investments, :commitment_type, :string, limit: 10, default: "Pool"
    add_column :portfolio_investments, :folio_id, :string, limit: 20
    add_reference :portfolio_investments, :capital_commitment, null: true, foreign_key: true

    PortfolioInvestment.update_all(commitment_type: "Pool")
    AggregatePortfolioInvestment.update_all(commitment_type: "Pool")
  end
end
