class AddIndexesToAccessRights < ActiveRecord::Migration[7.1]
  def change
    # Supports cache-free employee/advisor policy checks: WHERE entity_id=? AND user_id=?
    add_index :access_rights, [:entity_id, :user_id], name: "index_access_rights_on_entity_id_and_user_id"
    # Supports cache-free category-based lookups for investor policy checks
    add_index :access_rights, [:entity_id, :access_to_category], name: "index_access_rights_on_entity_id_and_category"
    # Covers the policy point-lookup: owner_type + owner_id + user_id
    add_index :access_rights, [:owner_type, :owner_id, :user_id], name: "index_access_rights_on_owner_and_user"
    # Covers the investor policy point-lookup: owner_type + owner_id + investor_id
    add_index :access_rights, [:owner_type, :owner_id, :access_to_investor_id], name: "index_access_rights_on_owner_and_investor"
  end
end
