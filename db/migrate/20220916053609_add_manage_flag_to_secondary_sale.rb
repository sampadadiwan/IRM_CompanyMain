class AddManageFlagToSecondarySale < ActiveRecord::Migration[7.0]
  def change
    add_column :secondary_sales, :manage_offers, :boolean, default: false
    add_column :secondary_sales, :manage_interests, :boolean, default: false
  end
end
