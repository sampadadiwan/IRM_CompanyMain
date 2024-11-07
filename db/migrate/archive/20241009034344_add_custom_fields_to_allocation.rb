class AddCustomFieldsToAllocation < ActiveRecord::Migration[7.1]
  def change
    add_column :allocations, :json_fields, :json
  end
end
