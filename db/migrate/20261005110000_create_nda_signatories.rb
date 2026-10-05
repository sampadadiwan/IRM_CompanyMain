# frozen_string_literal: true

# Creates the nda_signatories table for per-NDA signatory designations.
# A GP can tag specific users as designated NDA signatories for a given
# folder's NDA config. Unlike the InvestorAccess tag_list (entity-wide),
# this is scoped per NDA config — different folders can have different
# designated signatories.
#
# @see NdaSignatory
# @see NdaConfig
# @see NdaExemption — mirrors this table's pattern
class CreateNdaSignatories < ActiveRecord::Migration[8.0]
  def change
    create_table :nda_signatories do |t|
      # The NDA config this signatory designation applies to
      t.bigint :nda_config_id, null: false

      # The user designated as an NDA signatory
      t.bigint :user_id, null: false

      # The GP user who tagged this user as a signatory
      t.bigint :tagged_by_id, null: false

      t.timestamps
    end

    # Enforces one signatory tag per user per NDA config
    add_index :nda_signatories, %i[nda_config_id user_id],
              unique: true,
              name: "idx_nda_signatories_config_user"

    # Lookup queries: "which NDAs is this user a signatory for?"
    add_index :nda_signatories, :user_id,
              name: "idx_nda_signatories_user"

    add_foreign_key :nda_signatories, :nda_configs
    add_foreign_key :nda_signatories, :users
    add_foreign_key :nda_signatories, :users, column: :tagged_by_id
  end
end
