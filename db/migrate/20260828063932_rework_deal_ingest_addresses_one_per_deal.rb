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
    # All steps use if_exists/idempotent guards so a partial prior run
    # (staging failed midway twice) can be re-run safely.

    # 1. Drop the standalone deal_id index (compound index still covers FK)
    remove_index :deal_ingest_addresses, :deal_id, if_exists: true

    # 2. Keep only the newest row per deal (old model allowed one per user)
    execute <<~SQL.squish
      DELETE a FROM deal_ingest_addresses a
      INNER JOIN (
        SELECT deal_id, MAX(id) AS keep_id
        FROM deal_ingest_addresses
        GROUP BY deal_id
        HAVING COUNT(*) > 1
      ) dupes ON a.deal_id = dupes.deal_id AND a.id != dupes.keep_id
    SQL

    # 3. Add unique deal_id index
    unless index_exists?(:deal_ingest_addresses, :deal_id)
      add_index :deal_ingest_addresses, :deal_id, unique: true
    end

    # 4. Drop the compound index
    remove_index :deal_ingest_addresses, %i[deal_id user_id], if_exists: true

    # 5. Drop the user_id FK constraint, then its index, then the column.
    #    MySQL requires the FK to be dropped before its covering index.
    if foreign_key_exists?(:deal_ingest_addresses, :users)
      remove_foreign_key :deal_ingest_addresses, :users
    end
    remove_index :deal_ingest_addresses, :user_id, if_exists: true
    remove_column :deal_ingest_addresses, :user_id, :bigint, if_exists: true

    remove_column :deal_ingest_addresses, :revoked_at, :datetime, if_exists: true

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
    add_index :deal_ingest_addresses, :deal_id
  end
end
