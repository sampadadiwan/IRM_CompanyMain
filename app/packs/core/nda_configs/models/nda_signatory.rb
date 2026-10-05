# frozen_string_literal: true

# Records a per-NDA signatory designation for a user.
# A GP tags specific users as designated NDA signatories from the
# NDA Status Dashboard. Unlike the InvestorAccess tag_list (entity-wide),
# signatory tagging is scoped to a specific NDA config — different folders
# can have different designated signatories.
#
# @see NdaConfig
# @see NdaExemption — mirrors this model's pattern
# @see NdaStatusResolver — uses signatory data for dashboard display
class NdaSignatory < ApplicationRecord
  # The NDA config this signatory designation applies to
  belongs_to :nda_config

  # The user designated as an NDA signatory
  belongs_to :user

  # The GP user who tagged this user as a signatory
  belongs_to :tagged_by, class_name: "User"

  # One signatory tag per user per NDA config — mirrors the unique DB index
  validates :user_id, uniqueness: { scope: :nda_config_id, message: "is already a signatory for this NDA" }
end
