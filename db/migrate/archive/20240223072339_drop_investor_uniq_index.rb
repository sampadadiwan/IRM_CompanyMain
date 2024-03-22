class DropInvestorUniqIndex < ActiveRecord::Migration[7.1]
  def change
    remove_index :investors, name: "index_investors_on_investor_entity_id_and_entity_id"
    add_index :investors, %i[investor_entity_id entity_id deleted_at], unique: true
  end
end
