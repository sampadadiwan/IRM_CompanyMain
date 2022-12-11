class AddCategoryToInvestorNotice < ActiveRecord::Migration[7.0]
  def change
    add_column :investor_notices, :category, :string, limit: 30
  end
end
