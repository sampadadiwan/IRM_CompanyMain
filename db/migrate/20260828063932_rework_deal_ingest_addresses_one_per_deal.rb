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
    # Idempotent guards (if_exists / unless index_exists?) let this
    # re-run safely after a partial failure on staging.

    # 1. Swap the non-unique deal_id index for a unique one.
    #    Drop non-unique first, deduplicate data, then add unique.
    remove_index :deal_ingest_addresses, :deal_id, if_exists: true

    execute <<~SQL.squish
      DELETE a FROM deal_ingest_addresses a
      INNER JOIN (
        SELECT deal_id, MAX(id) AS keep_id
        FROM deal_ingest_addresses
        GROUP BY deal_id
        HAVING COUNT(*) > 1
      ) dupes ON a.deal_id = dupes.deal_id AND a.id != dupes.keep_id
    SQL

    unless index_exists?(:deal_ingest_addresses, :deal_id)
      add_index :deal_ingest_addresses, :deal_id, unique: true
    end

    # 2. Drop the old compound index (unique index now covers the FK)
    remove_index :deal_ingest_addresses, %i[deal_id user_id], if_exists: true

    # 3. Drop user_id column — MySQL auto-drops its FK and index
    remove_column :deal_ingest_addresses, :user_id, if_exists: true

    # 4. Drop revoked_at column
    remove_column :deal_ingest_addresses, :revoked_at, if_exists: true

    # 5. Widen address column
    change_column :deal_ingest_addresses, :address, :string, null: false, limit: 100
  end

  def down
    remove_index :deal_ingest_addresses, :deal_id

    change_column :deal_ingest_addresses, :address, :string, null: false, limit: 16

    add_column :deal_ingest_addresses, :revoked_at, :datetime
    add_column :deal_ingest_addresses, :user_id, :bigint, null: false
    add_index :deal_ingest_addresses, %i[deal_id user_id], unique: true
    add_index :deal_ingest_addresses, :deal_id
  end
end
