# Stores all settings not used by the UI / used typically by background jobs to handle entity related features
# This enables us to make the Entity small as its used in every request,
# while moving other attributes to EntitySetting
class EntitySetting < ApplicationRecord
  include Trackable.new(associated_with: :entity)
  belongs_to :entity

  validate :validate_ckyc_enabled
  validates :from_email, length: { maximum: 100 }
  validates :mailbox, length: { maximum: 30 }
  serialize :kpi_doc_list, type: Array

  before_save :ensure_single_kra_enabled, if: -> { kra_enabled_changed? && kra_enabled == true }
  before_save :check_esign_provider
  before_create :set_kanban_steps
  # Add new flags to the end of this list
  flag :custom_flags, %i[no_password_login]

  def ckyc_or_kra_enabled?
    ckyc_enabled || kra_enabled
  end

  def check_esign_provider
    self.esign_provider = "Digio" if esign_provider.blank?
    self.esign_provider = esign_provider.strip.capitalize
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

  def digio_auth_token
    Base64.strict_encode64("#{digio_client_id}:#{digio_client_secret}") if digio_client_id.present? && digio_client_secret.present?
  end

  # rubocop : disable Rails/SkipsModelValidations
  def self.disable_all(reset_password: false)
    if Rails.env.development?
      EntitySetting.update_all(sandbox: true)
      User.update_all(whatsapp_enabled: false)

      u = User.find_by email: "admin@altx.com"
      u.password = "password"
      u.save

      if reset_password
        User.find_each do |u|
          u.password = "password"
          u.save
        end
      end
    end
  end
  # rubocop : enable Rails/SkipsModelValidations

  private

  # rubocop : disable Rails/SkipsModelValidations
  def ensure_single_kra_enabled
    # Update other EntitySetting records to set kra_enabled to false
    self.class.where.not(id:).where(kra_enabled: true).update_all(kra_enabled: false)
  end
  # rubocop : enable Rails/SkipsModelValidations

  def validate_ckyc_enabled
    errors.add(:ckyc, "can not be enabled without FI Code") if ckyc_enabled == true && fi_code.blank?
  end

  def set_kanban_steps
    self.kanban_steps = {
      "Deal" =>
      ["Pre Term Sheet Memo",
       "Information Memorandum",
       "Business Plan",
       "IC Minutes",
       "Final Term Sheet",
       "Diligence Reports",
       "Closing Investment Memo",
       "Transaction Documents",
       "CP Confirmation Certificate"],
      "KanbanBoard" => ["Todo", "In Progres", "Done", "Validated"]
    }
  end
end
