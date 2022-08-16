class AddDeptToHolding < ActiveRecord::Migration[7.0]
  def change
    add_column :holdings, :department, :string, limit: 25
  end
end
