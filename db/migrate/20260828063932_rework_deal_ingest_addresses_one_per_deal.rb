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
    # Deduplicate FIRST: keep only the newest row per deal. This must happen
    # before any index/column changes — MySQL shrinks a composite index when
    # one of its columns is dropped, so dropping user_id would turn the unique
    # (deal_id, user_id) index into a unique (deal_id) index and fail on
    # duplicate deal_ids before we ever got to dedupe.
    execute <<~SQL.squish
      DELETE a FROM deal_ingest_addresses a
      INNER JOIN (
        SELECT deal_id, MAX(id) AS keep_id
        FROM deal_ingest_addresses
        GROUP BY deal_id
        HAVING COUNT(*) > 1
      ) dupes ON a.deal_id = dupes.deal_id AND a.id != dupes.keep_id
    SQL

    # Drop the composite unique index explicitly rather than letting the
    # user_id column drop mutate it (MySQL keeps the index, minus the column).
    remove_index :deal_ingest_addresses, column: %i[deal_id user_id],
                 if_exists: true

    remove_column :deal_ingest_addresses, :user_id, if_exists: true
    remove_column :deal_ingest_addresses, :revoked_at, if_exists: true

    # Replace the deal_id index with a unique one (one address per deal).
    # Add the new unique index BEFORE dropping the old one: the deals FK
    # needs at least one index starting with deal_id at all times, so
    # dropping first fails with "needed in a foreign key constraint".
    unless index_exists?(:deal_ingest_addresses, :deal_id, unique: true)
      add_index :deal_ingest_addresses, :deal_id, unique: true,
                name: "index_deal_ingest_addresses_on_deal_id_unique"
      remove_index :deal_ingest_addresses,
                   name: "index_deal_ingest_addresses_on_deal_id",
                   if_exists: true
      rename_index :deal_ingest_addresses,
                   "index_deal_ingest_addresses_on_deal_id_unique",
                   "index_deal_ingest_addresses_on_deal_id"
    end

    # Widen address column
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
