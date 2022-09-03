class AddVerifiedToCapitalRemittance < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_remittances, :verified, :boolean, default: false
  end
end
