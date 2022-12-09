class AddGenerateToInvestorNotice < ActiveRecord::Migration[7.0]
  def change
    add_column :investor_notices, :generate, :boolean, default: false
  end
end
