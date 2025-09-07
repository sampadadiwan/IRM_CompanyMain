class AddUserSyncFields < ActiveRecord::Migration[8.0]
  def up
    # USERS
    add_index  :users, :regions

    # Single combined canonical fingerprint (hex-encoded SHA-256 => 64 chars)
    add_column :users, :last_synced_ccf_hex, :string, limit: 64
    add_column :users, :last_synced_at, :datetime, precision: 6
    add_column :users, :primary_region_id, :integer
    add_index  :users, :last_synced_ccf_hex
    # Change null true and default nil
    change_column_null :users, :regions, true, nil
    change_column_default :users, :regions, nil
    change_column_null :users, :primary_region, true, nil
    change_column_default :users, :primary_region, nil

    # ENTITIES
    add_column :entities, :primary_region_id, :integer
  end

  def down
    # USERS
    remove_index  :users, :regions

    remove_column :users, :last_synced_ccf_hex
    remove_column :users, :last_synced_at
    remove_column :users, :primary_region_id
    remove_index  :users, :last_synced_ccf_hex
    # Revert null and default changes
    change_column_null :users, :regions, false, ""
    change_column_default :users, :regions, ""
    change_column_null :users, :primary_region, false, ""
    change_column_default :users, :primary_region, ""

    # ENTITIES
    remove_column :entities, :primary_region_id
  end
end
