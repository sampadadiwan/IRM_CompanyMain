# frozen_string_literal: true

# Rework deal_ingest_addresses for the one-address-per-deal model.
#
# Changes from the 2026-08-27 architecture decision:
#   - Drop user_id: address identifies the deal, not the user
#   - Drop revoked_at: no per-user revocation; address lives with the deal
#   - Replace unique index (deal_id, user_id) with unique index (deal_id)
#   - Widen address column: was 16-char hex, now deal ID or custom string
class ReworkDealIngestAddressesOnePerDeal < ActiveRecord::Migration[8.1]
  def up
    # Add the new unique index on deal_id BEFORE dropping the compound
    # index — MySQL's FK on deal_id needs at least one index covering
    # that column, so the new index must exist first
    add_index :deal_ingest_addresses, :deal_id, unique: true

    # Now safe to remove the old compound index
    remove_index :deal_ingest_addresses, %i[deal_id user_id]

    # Remove the standalone user_id index (from t.references)
    remove_index :deal_ingest_addresses, :user_id, if_exists: true

    # Drop columns no longer needed
    remove_column :deal_ingest_addresses, :user_id, :bigint
    remove_column :deal_ingest_addresses, :revoked_at, :datetime

    # Widen address column — was limit: 16 (hex), now needs to hold
    # deal IDs and user-chosen strings (e.g. "fund-ii-2026")
    change_column :deal_ingest_addresses, :address, :string, null: false, limit: 100
  end

  def down
    remove_index :deal_ingest_addresses, :deal_id

    change_column :deal_ingest_addresses, :address, :string, null: false, limit: 16

    add_column :deal_ingest_addresses, :revoked_at, :datetime
    add_column :deal_ingest_addresses, :user_id, :bigint, null: false
    add_index :deal_ingest_addresses, %i[deal_id user_id], unique: true
  end
end
