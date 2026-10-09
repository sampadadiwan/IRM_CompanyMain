# frozen_string_literal: true

# Creates the nda_exemptions table for user-level NDA bypasses.
# A GP can exempt a specific user from an NDA requirement so that
# the user accesses the Data Room folder without signing.
# Exemptions are per-user, not per-investor — independent of
# stakeholder-level NdaAcceptance records.
#
# @see NdaExemption
# @see NdaConfig
class CreateNdaExemptions < ActiveRecord::Migration[8.0]
  def change
    create_table :nda_exemptions do |t|
      # The NDA config this exemption applies to
      t.bigint :nda_config_id, null: false

      # The user who is exempted from the NDA requirement
      t.bigint :user_id, null: false

      # The GP user who granted the exemption
      t.bigint :exempted_by_id, null: false

      # Optional free-text justification (e.g. "NDA signed offline")
      t.string :reason, limit: 500

      t.timestamps
    end

    # Enforces one exemption per user per NDA config; also serves
    # the gate query NdaExemption.exists?(nda_config_id:, user_id:)
    add_index :nda_exemptions, %i[nda_config_id user_id],
              unique: true,
              name: "idx_nda_exemptions_config_user"

    # Audit queries: "which NDAs is this user exempt from?"
    add_index :nda_exemptions, :user_id,
              name: "idx_nda_exemptions_user"

    add_foreign_key :nda_exemptions, :nda_configs
    add_foreign_key :nda_exemptions, :users
    add_foreign_key :nda_exemptions, :users, column: :exempted_by_id
  end
end
