# frozen_string_literal: true

# @description Records an LP's accept or decline decision on an NdaConfig.
#   Append-only audit trail — each action creates a new row, never updates an existing one.
#   The gate query uses the latest record by created_at to determine current access.
#
# @note Owner-agnostic: tied to NdaConfig (polymorphic), not to any specific owner type
#   (Folder, Deal, InvestmentOpportunity, etc.). Works for any model that includes WithNda.
#
# @see NdaConfig
# @see WithNda
class NdaAcceptance < ApplicationRecord
  STATUSES = %w[accepted declined].freeze

  belongs_to :nda_config
  belongs_to :user
  belongs_to :entity

  validates :status, inclusion: { in: STATUSES }

  # @return [Boolean] true if this record represents an accepted NDA
  def accepted?
    status == "accepted"
  end
end
