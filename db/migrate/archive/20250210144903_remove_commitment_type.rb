class RemoveCommitmentType < ActiveRecord::Migration[7.2]
  def change
    remove_column :account_entries, :commitment_type
    remove_column :aggregate_portfolio_investments, :commitment_type
    remove_column :capital_calls, :commitment_type
    remove_column :capital_commitments, :commitment_type
    remove_column :capital_distributions, :commitment_type
    remove_column :fund_formulas, :commitment_type
    remove_column :portfolio_investments, :commitment_type
  end
end
