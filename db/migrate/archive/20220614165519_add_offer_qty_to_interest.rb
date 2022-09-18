class AddOfferQtyToInterest < ActiveRecord::Migration[7.0]
  def change
    add_column :interests, :offer_quantity, :integer, default: 0
  end
end
