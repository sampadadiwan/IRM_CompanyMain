# frozen_string_literal: true

# Creates the nda_config_versions table to store a versioned snapshot of each
# NDA PDF upload. Each row records the version number, the Shrine file
# reference, the GP's resign decision, and who uploaded it.
#
# @see NdaConfigVersion
# @see NdaConfig#nda_config_versions
class CreateNdaConfigVersions < ActiveRecord::Migration[8.0]
  def change
    create_table :nda_config_versions do |t|
      # Changed: New table for NDA version audit trail.
      # Why: Every PDF upload gets a unique version number. The resign_required
      #   flag controls whether that bump invalidates existing acceptances.
      t.references :nda_config, null: false, foreign_key: { on_delete: :cascade }
      t.integer    :version, null: false
      t.text       :nda_document_data, null: false
      t.boolean    :resign_required, null: false, default: true
      t.references :uploaded_by, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end

    # Changed: Unique composite index on [nda_config_id, version].
    # Why: Prevents duplicate version records per NDA config and serves as
    #   the primary lookup for version history queries.
    add_index :nda_config_versions, [:nda_config_id, :version],
              unique: true,
              name: "idx_nda_config_versions_config_version"

    # Changed: Composite index on [nda_config_id, resign_required, version].
    # Why: Covers the acceptance gate query — find resign-required versions
    #   in a range for a given config. Avoids a full table scan.
    add_index :nda_config_versions, [:nda_config_id, :resign_required, :version],
              name: "idx_nda_config_versions_resign_lookup"
  end
end
