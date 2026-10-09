# frozen_string_literal: true

# Module 5 — NDA Inheritance: Adds nda_inheritance_mode to folders.
#
# Each folder declares how it resolves its effective NDA:
#   - "inherit" (default) — uses parent folder's NDA config (or none if parent has none)
#   - "own"     — folder has its own NdaConfig (set automatically when config is created)
#   - "opt_out" — explicitly no NDA, even if parent has one
#
# Column is NOT NULL with default "inherit" so every existing folder starts
# in the correct state — they have no NDA config and should look upward.
# Folders that already have an NdaConfig are backfilled to "own" in a
# separate data migration (Task 2.1).
#
# @see Folder#nda_inheritance_mode
# @see Folder#effective_nda_config
class AddNdaInheritanceModeToFolders < ActiveRecord::Migration[8.1]
  def change
    add_column :folders, :nda_inheritance_mode, :string, limit: 10, null: false, default: "inherit"
    add_index  :folders, :nda_inheritance_mode, name: "idx_folders_nda_inheritance_mode"
  end
end
