class AddEnableFundsToEntity < ActiveRecord::Migration[7.0]
  def change
    add_column :entities, :enable_funds, :boolean, default: false
    add_column :entities, :enable_inv_opportunities, :boolean, default: false
  end
end
