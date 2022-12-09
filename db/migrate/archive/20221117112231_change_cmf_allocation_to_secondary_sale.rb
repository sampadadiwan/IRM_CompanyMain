class ChangeCmfAllocationToSecondarySale < ActiveRecord::Migration[7.0]
  def change
    change_column :offers, :custom_matching_vals, :string
    add_index :offers, :custom_matching_vals
    change_column :interests, :custom_matching_vals, :string
    add_index :interests, :custom_matching_vals
  end
end
