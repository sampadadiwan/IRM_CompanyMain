class AddCreationToCapitalRemittance < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_remittances, :created_by, :string, limit: 10
  end
end
