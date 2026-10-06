# frozen_string_literal: true

# @description Records a stakeholder-level NDA accept, decline, or revoke decision on an NdaConfig.
#   One user accepts on behalf of their investor (stakeholder), and all users under that
#   investor are unlocked. Append-only audit trail — each action creates a new row, never
#   updates an existing one. The gate query uses the latest record by [nda_config_id, investor_id,
#   created_at] to determine current stakeholder access.
#
# Changed: Module 8 — added "revoked" status and nullable reason column.
# Why: GP can revoke an accepted NDA from the dashboard. Revocation creates a new
#   append-only row with status=revoked and an optional reason. The gate treats a
#   revoked investor the same as Pending (must re-accept).
#
# @note investor_id identifies the stakeholder on whose behalf the NDA is signed.
#   user_id records who physically signed — for audit, not for gate decisions.
# @note Owner-agnostic: tied to NdaConfig (polymorphic), not to any specific owner type
#   (Folder, Deal, InvestmentOpportunity, etc.). Works for any model that includes WithNda.
#
# @see NdaConfig
# @see WithNda
# @see InvestorAccess — resolves which investor a user represents for a given entity
class NdaAcceptance < ApplicationRecord
  # Changed: Added "revoked" to STATUSES.
  # Why: Module 8 revocation — GP can revoke an accepted NDA, creating an audit row
  #   with status=revoked. Append-only model preserved (no updates to existing rows).
  STATUSES = %w[accepted declined revoked].freeze

  belongs_to :nda_config
  belongs_to :investor
  belongs_to :user
  belongs_to :entity

  validates :status, inclusion: { in: STATUSES }

  # @return [Boolean] true if this record represents an accepted NDA
  def accepted?
    status == "accepted"
  end

  # @return [Boolean] true if this record represents a declined NDA
  def declined?
    status == "declined"
  end

  # Changed: Added revoked? convenience method for Module 8 revocation.
  # Why: Matches accepted?/declined? pattern. Used by NdaStatusResolver and the NDA gate
  #   to detect revoked investors (treated same as Pending — must re-accept).
  #
  # @return [Boolean] true if this record represents a GP-revoked NDA
  def revoked?
    status == "revoked"
  end
end
