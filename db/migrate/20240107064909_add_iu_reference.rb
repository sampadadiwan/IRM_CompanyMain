class AddIuReference < ActiveRecord::Migration[7.1]
  def change
    add_column :account_entries, :import_upload_id, :bigint, null: true
    add_column :capital_commitments, :import_upload_id, :bigint, null: true
    add_column :capital_remittances, :import_upload_id, :bigint, null: true
    add_column :capital_remittance_payments, :import_upload_id, :bigint, null: true    
    add_column :capital_calls, :import_upload_id, :bigint, null: true
    add_column :capital_distributions, :import_upload_id, :bigint, null: true
    add_column :capital_distribution_payments, :import_upload_id, :bigint, null: true
    add_column :investors, :import_upload_id, :bigint, null: true
    add_column :investor_kycs, :import_upload_id, :bigint, null: true
    add_column :investor_advisors, :import_upload_id, :bigint, null: true
    add_column :investor_accesses, :import_upload_id, :bigint, null: true
    # add_column :holdings, :import_upload_id, :bigint, null: true
    add_column :offers, :import_upload_id, :bigint, null: true
    add_column :documents, :import_upload_id, :bigint, null: true
    add_column :portfolio_investments, :import_upload_id, :bigint, null: true
    add_column :portfolio_cashflows, :import_upload_id, :bigint, null: true
    add_column :valuations, :import_upload_id, :bigint, null: true
    add_column :option_pools, :import_upload_id, :bigint, null: true
    add_column :fund_unit_settings, :import_upload_id, :bigint, null: true
    add_column :fund_units, :import_upload_id, :bigint, null: true
    add_column :kpi_reports, :import_upload_id, :bigint, null: true
    add_column :kpis, :import_upload_id, :bigint, null: true
  end
end
