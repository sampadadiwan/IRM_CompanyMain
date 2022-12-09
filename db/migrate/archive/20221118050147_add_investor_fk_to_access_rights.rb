class AddInvestorFkToAccessRights < ActiveRecord::Migration[7.0]
  def change
    change_column :access_rights, :access_to_investor_id, :bigint
    add_foreign_key :access_rights, :investors, column: :access_to_investor_id
  end
end
