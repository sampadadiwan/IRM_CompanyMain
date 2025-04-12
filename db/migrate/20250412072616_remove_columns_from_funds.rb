class RemoveColumnsFromFunds < ActiveRecord::Migration[8.0]
  def change
    remove_column :funds, :rvpi, :decimal
    remove_column :funds, :dpi, :decimal
    remove_column :funds, :tvpi, :decimal
    remove_column :funds, :moic, :decimal
    remove_column :funds, :xirr, :decimal

    remove_column :funds, :trustee_name, :string
    remove_column :funds, :manager_name, :string
    remove_column :funds, :registration_number, :string
    remove_column :funds, :contact_name, :string
    remove_column :funds, :contact_email, :string
    remove_column :funds, :sponsor_name, :string
    remove_column :funds, :sub_category, :string

    remove_column :funds, :co_invest_call_amount_cents, :bigint
    remove_column :funds, :co_invest_committed_amount_cents, :bigint
    remove_column :funds, :co_invest_distribution_amount_cents, :bigint
    remove_column :funds, :co_invest_collected_amount_cents, :bigint
  end
end
