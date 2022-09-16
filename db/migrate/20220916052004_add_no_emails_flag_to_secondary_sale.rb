class AddNoEmailsFlagToSecondarySale < ActiveRecord::Migration[7.0]
  def change
    add_column :secondary_sales, :no_offer_emails, :boolean, default: false
    add_column :secondary_sales, :no_interest_emails, :boolean, default: false
  end
end
