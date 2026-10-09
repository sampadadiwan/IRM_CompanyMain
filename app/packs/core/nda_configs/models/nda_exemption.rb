# frozen_string_literal: true

# Records a user-level exemption from an NDA requirement.
# A GP grants an exemption so that a specific user bypasses the NDA gate
# and accesses folder contents without signing. Exemptions are per-user,
# not per-investor — independent of stakeholder-level NdaAcceptance records.
#
# @see NdaConfig
# @see NdaAcceptance
# @see DocumentsController#ensure_nda_accepted
class NdaExemption < ApplicationRecord
  # The NDA config this exemption applies to
  belongs_to :nda_config

  # The user who is exempted from the NDA requirement
  belongs_to :user

  # The GP user who granted the exemption
  belongs_to :exempted_by, class_name: "User"

  # One exemption per user per NDA config — mirrors the unique DB index
  validates :user_id, uniqueness: { scope: :nda_config_id, message: "is already exempt from this NDA" }

  # Reason limit matches the DB column limit (500 chars)
  validates :reason, length: { maximum: 500 }
end
