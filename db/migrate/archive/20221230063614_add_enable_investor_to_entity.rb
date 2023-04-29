class AddEnableInvestorToEntity < ActiveRecord::Migration[7.0]
  def change
    add_column :entities, :enable_investors, :boolean, default: true
  end
end
