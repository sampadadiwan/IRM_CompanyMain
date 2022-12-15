class AddGrantLetterToHolding < ActiveRecord::Migration[7.0]
  def change
    add_column :holdings, :grant_letter_data, :text
    add_column :option_pools, :grant_letter_data, :text
  end
end
