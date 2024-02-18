class RemoveNullFromEntityIdInvestors < ActiveRecord::Migration[7.1]
  def change
    change_column_null :investors, :entity_id, false
    change_column_null :investors, :investor_entity_id, false
  end
end
