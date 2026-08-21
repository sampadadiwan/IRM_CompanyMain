# frozen_string_literal: true

# Per-(deal, user) unguessable email address for the Deal Update Agent.
#
# A team member sends a plain-language email to their personal deal address
# (e.g. d7f3a91c2b8e4406@updates.caphive.com) and the agent parses it into
# a meeting note or task on the deal board.
#
# The address IS the credential: possession proves identity and deal access.
# There is no password, no token — so the address must be cryptographically
# random (16 hex chars = 8 bytes = 2^64 possibilities) and never guessable.
#
# Lifecycle:
#   - Created automatically when a deal is created (for all access-right users)
#     or when a user is granted access to an existing deal.
#   - Revoked (revoked_at set, never deleted) when access is removed — same
#     transaction, per security rule FR-5.
#   - Revoked addresses are invisible to the inbound pipeline (the lookup
#     scope filters on revoked_at IS NULL).
class CreateDealIngestAddresses < ActiveRecord::Migration[8.1]
  def change
    create_table :deal_ingest_addresses do |t|
      t.references :deal, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      # 16 hex characters generated via SecureRandom.hex(8).
      # This is the left-hand side of the email address — the full address
      # is "#{address}@updates.caphive.com". Unique index because every
      # inbound email is resolved by looking up this column.
      t.string :address, null: false, limit: 16

      # Soft-revoke timestamp. Null = active. Set = revoked.
      # We never delete rows — revoked addresses stay for audit trail.
      # The inbound pipeline filters WHERE revoked_at IS NULL.
      t.datetime :revoked_at

      t.timestamps
    end

    # Primary lookup: inbound email arrives → find the address row.
    # Must be unique to prevent two deals from sharing an address.
    add_index :deal_ingest_addresses, :address, unique: true

    # One active address per (deal, user) pair. Prevents duplicates when
    # callbacks fire more than once (idempotent find_or_create_by).
    add_index :deal_ingest_addresses, %i[deal_id user_id], unique: true
  end
end
