class AddFieldsToExcercises < ActiveRecord::Migration[7.0]
  def change
    add_column :excercises, :cashless, :boolean
    add_column :excercises, :shares_to_sell, :integer
    add_column :excercises, :shares_to_allot, :integer
  end
end
