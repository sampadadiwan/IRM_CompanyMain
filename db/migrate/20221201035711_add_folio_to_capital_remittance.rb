class AddFolioToCapitalRemittance < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_remittances, :folio_id, :string, limit: 20
    add_column :capital_distribution_payments, :folio_id, :string, limit: 20
  end
end
