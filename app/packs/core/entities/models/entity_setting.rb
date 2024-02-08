# Stores all settings not used by the UI / used typically by background jobs to handle entity related features
# This enables us to make the Entity small as its used in every request,
# while moving other attributes to EntitySetting
class EntitySetting < ApplicationRecord
  include Trackable.new(associated_with: :entity)
  belongs_to :entity

  validate :validate_ckyc_enabled
  validates :from_email, length: { maximum: 100 }
  serialize :kpi_doc_list, type: Array

  # Add new flags to the end of this list
  flag :custom_flags, %i[enable_approval_show_kycs enable_this enable_that]

  def validate_ckyc_enabled
    errors.add(:ckyc, "can not be enabled without FI Code") if ckyc_enabled == true && fi_code.blank?
  end

  def ckyc_or_kra_enabled?
    ckyc_enabled || kra_enabled
  end

  def to_s
    "#{entity.name} settings"
  end

  def fetch_whatsapp_endpoint
    whatsapp_endpoint.present? && whatsapp_token.present? ? whatsapp_endpoint : Rails.application.credentials[:WHATSAPP_API_ENDPOINT]
  end

  def fetch_whatsapp_token
    whatsapp_token.present? && whatsapp_endpoint.present? ? whatsapp_token : Rails.application.credentials[:WHATSAPP_ACCESS_TOKEN]
  end

  def fetch_whatsapp_template(template_name)
    whatsapp_templates.present? && whatsapp_token.present? && whatsapp_endpoint.present? ? JSON.parse(whatsapp_templates)[template_name.to_s] : ENV.fetch('CAPHIVE_NOTIFICATION')
  end
end
