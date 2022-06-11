class AddFinalizedToSecondarySale < ActiveRecord::Migration[7.0]
  def change
    add_column :secondary_sales, :finalized, :boolean, default: false
  end
end
