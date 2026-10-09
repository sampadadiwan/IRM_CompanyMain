# frozen_string_literal: true

# @description Records a stakeholder-level NDA accept or decline decision on an NdaConfig.
#   One user accepts on behalf of their investor (stakeholder), and all users under that
#   investor are unlocked. Append-only audit trail — each action creates a new row, never
#   updates an existing one. The gate query uses the latest record by [nda_config_id, investor_id,
#   created_at] to determine current stakeholder access.
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
  STATUSES = %w[accepted declined].freeze

  belongs_to :nda_config
  belongs_to :investor
  belongs_to :user
  belongs_to :entity

  validates :status, inclusion: { in: STATUSES }

  # @return [Boolean] true if this record represents an accepted NDA
  def accepted?
    status == "accepted"
  end
end
