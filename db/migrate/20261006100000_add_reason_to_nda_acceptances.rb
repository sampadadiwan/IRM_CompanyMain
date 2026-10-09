# frozen_string_literal: true

# Adds a nullable reason column to nda_acceptances for revocation audit trail.
# Why: Module 8 revocation feature — when a GP revokes an accepted NDA, they can
#   optionally record a reason (e.g. "Deal terminated"). Only populated for
#   status=revoked rows; accepted/declined rows keep NULL.
#   text type (not string) because reason may be multi-sentence.
#   Nullable, no default — instant metadata-only ADD COLUMN in MySQL 8+.
#
# @see NdaAcceptance
class AddReasonToNdaAcceptances < ActiveRecord::Migration[8.0]
  def change
    # Changed: Add reason text column for revocation audit trail.
    # Why: GP needs to record optional free-text reason when revoking an investor's NDA.
    add_column :nda_acceptances, :reason, :text, null: true
  end
end
