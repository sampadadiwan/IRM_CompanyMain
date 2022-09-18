class AddOwnerToMessage < ActiveRecord::Migration[7.0]
  def change
    add_reference :messages, :owner, polymorphic: true, null: false
    remove_column :messages, :deal_investor_id
  end
end
