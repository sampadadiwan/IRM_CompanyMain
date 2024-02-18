class DropPropertiesForCustomFields < ActiveRecord::Migration[7.1]
  def change
    remove_column :account_entries, :properties
    remove_column :approvals, :properties
    remove_column :capital_calls, :properties
    remove_column :capital_commitments, :properties
    remove_column :capital_distribution_payments, :properties
    remove_column :capital_distributions, :properties
    remove_column :capital_remittance_payments, :properties
    remove_column :capital_remittances, :properties
    remove_column :deals, :properties
    remove_column :documents, :properties
    remove_column :expression_of_interests, :properties
    remove_column :fund_unit_settings, :properties
    remove_column :funds, :properties
    remove_column :holdings, :properties
    remove_column :interests, :properties
    remove_column :investment_opportunities, :properties
    remove_column :investor_kycs, :properties
    remove_column :investors, :properties
    remove_column :kpi_reports, :properties
    remove_column :kpis, :properties
    remove_column :offers, :properties
    remove_column :portfolio_investments, :properties
    remove_column :secondary_sales, :properties
    remove_column :valuations, :properties

  end
end
