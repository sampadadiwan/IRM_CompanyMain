# Stores all settings not used by the UI / used typically by background jobs to handle entity related features
# This enables us to make the Entity small as its used in every request,
# while moving other attributes to EntitySetting
class EntitySetting < ApplicationRecord
  belongs_to :entity

  validate :validate_ckyc_kra_enabled

  def validate_ckyc_kra_enabled
    errors.add(:ckyc_kra, "can not be enabled without FI Code") if ckyc_kra_enabled == true && fi_code.blank?
  end
end
