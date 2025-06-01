class InvreaseFolioIdLimitEverywhere < ActiveRecord::Migration[8.0]
  def change
    change_column :capital_distribution_payments, :folio_id, :string, limit: 40
    change_column :capital_remittances, :folio_id, :string, limit: 40
    change_column :portfolio_investments, :folio_id, :string, limit: 40
    change_column :account_entries, :folio_id, :string, limit: 40
    change_column :fund_unit_settings, :name, :string, limit: 40
    change_column :fund_units, :unit_type, :string, limit: 40
  end
end
