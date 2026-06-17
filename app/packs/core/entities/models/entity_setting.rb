# Stores all settings not used by the UI / used typically by background jobs to handle entity related features
# This enables us to make the Entity small as its used in every request,
# while moving other attributes to EntitySetting
class EntitySetting < ApplicationRecord
  include Trackable.new(associated_with: :entity)

  belongs_to :entity
  extend Enumerize

  enumerize :db_dumps_frequency, in: %i[daily weekly monthly interval custom_days adhoc], default: :daily

  validates :from_email, length: { maximum: 100 }
  validates :mailbox, length: { maximum: 30 }
  validates :investor_presentations_email, length: { maximum: 100 }, allow_blank: true
  validates :kpi_reminder_frequency, length: { maximum: 10 }, allow_blank: true
  validates :regulatory_env, length: { maximum: 20 }, allow_blank: true
  validates :db_dumps_retention_period, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :db_dumps_interval, numericality: { only_integer: true, greater_than: 0 }, if: -> { db_dumps_frequency&.interval? }
  validates :db_dumps_custom_days, presence: true, if: -> { db_dumps_frequency&.custom_days? }
  serialize :kpi_doc_list, type: Array

  before_save :check_esign_provider
  before_create :set_kanban_steps

  before_save :validate_document_colors
  # Add new flags to the end of this list
  flag :custom_flags, %i[no_password_login]

  def validate_document_colors
    if document_colors.blank?
      self.document_colors = {}
      return
    end
    if document_colors.is_a?(String)
      begin
        self.document_colors = JSON.parse(document_colors)
      rescue JSON::ParserError
        errors.add(:document_colors, "must be a valid JSON string")
        throw(:abort)
      end
    end
  end

  def get_document_colors
    if document_colors.is_a?(String)
      begin
        JSON.parse(document_colors)
      rescue JSON::ParserError
        {}
      end
    elsif document_colors.is_a?(Hash)
      document_colors
    else
      {}
    end
  end

  def check_esign_provider
    self.esign_provider = "Digio" if esign_provider.blank?
    self.esign_provider = esign_provider.strip.capitalize
  end

  def start_of_financial_year_date(date = nil, nil_if_not_set: false)
    if date.nil? && nil_if_not_set
      nil
    else
      date ||= Time.zone.today
      month_offset_for_fy = self.month_offset_for_fy.present? ? self.month_offset_for_fy.to_i : 3
      fy_start_date = date.month > month_offset_for_fy ? date.beginning_of_year : (date.beginning_of_year - 1.year)
      (fy_start_date + month_offset_for_fy.months)
    end
  end

  def to_s
    "#{entity.name} settings"
  end

  # Returns grouped options for select, filtered to providers with a configured API key.
  # Format matches grouped_options_for_select: [["Provider", [["Label", "model-id"], ...]], ...]
  def available_llm_models
    LlmModels::PROVIDERS.filter_map do |_key, provider|
      next if send(provider[:key_field]).blank?

      [provider[:label], provider[:models]]
    end
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

  def self.disable_all(reset: false)
    if Rails.env.development?
      EntitySetting.update_all(sandbox: true)
      User.update_all(whatsapp_enabled: false)

      root_emails = ["admin@altx.com", "admin@caphive.us"]

      root_emails.each do |email|
        root = User.find_by email: email
        if root.present?
          root.password = "password"
          root.save
        end
      end

      if reset
        User.find_each do |u|
          u.password = "password"
          u.save
        end
      end
    end
  end

  # --- MCP (AI Client Integration) Settings ---

  # @return [Boolean] whether MCP is enabled for this entity
  def mcp_enabled?
    mcp_enabled == true
  end

  # @return [Array<String>] roles allowed to use MCP
  def mcp_allowed_roles_list
    JSON.parse(mcp_allowed_roles || '["employee"]')
  rescue JSON::ParserError
    ["employee"]
  end

  # @param roles [Array<String>] roles to allow
  def mcp_allowed_roles_list=(roles)
    self.mcp_allowed_roles = Array(roles).compact_blank.to_json
  end

  # @return [Array<String>] allowed OAuth client names (empty = all)
  def mcp_allowed_clients_list
    JSON.parse(mcp_allowed_clients || '[]')
  rescue JSON::ParserError
    []
  end

  # @param clients [Array<String>] client names to allow
  def mcp_allowed_clients_list=(clients)
    self.mcp_allowed_clients = Array(clients).compact_blank.to_json
  end

  # rubocop : enable Rails/SkipsModelValidations

  private

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
