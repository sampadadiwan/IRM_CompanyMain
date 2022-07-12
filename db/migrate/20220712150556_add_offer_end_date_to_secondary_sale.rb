class AddOfferEndDateToSecondarySale < ActiveRecord::Migration[7.0]
  def change
    add_column :secondary_sales, :offer_end_date, :date
  end
end
