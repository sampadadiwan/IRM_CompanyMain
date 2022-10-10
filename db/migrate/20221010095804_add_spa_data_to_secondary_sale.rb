class AddSpaDataToSecondarySale < ActiveRecord::Migration[7.0]
  def change
    add_column :secondary_sales, :spa_data, :text
  end
end
