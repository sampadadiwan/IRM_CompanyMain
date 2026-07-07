class Deal < ApplicationRecord
  include ForInvestor
  include Trackable.new
  include WithFolder
  include WithDataRoom
  include WithCustomField
  include InvestorsGrantedAccess
  include KanbanManager
  include WithFriendlyId
  include WithIncomingEmail
  include WithCustomNotifications

  monetize :amount_cents, with_model_currency: :currency

  # Make all models searchable
  update_index('deal') { self if index_record? }

  belongs_to :entity

  counter_culture :entity
  delegate :name, to: :entity, prefix: :entity

  has_many :deal_investors, dependent: :destroy
  has_many :investors, through: :deal_investors

  has_many :deal_activities, dependent: :destroy
  has_many :access_rights, as: :owner, dependent: :destroy
  has_many :tasks, as: :owner, dependent: :destroy

  has_many :ci_track_records, as: :owner, dependent: :destroy
  has_many :ci_widgets, as: :owner, dependent: :destroy

  # added a new field for deal_investor_status to store allowed statuses for deal investors, defaulting to DealInvestor::STATUS if not set
  attribute :deal_investor_status, :json, default: []

  validates :name, :amount_cents, :status, :currency, :deal_investor_status, presence: true
  validates :status, length: { maximum: 20 }
  validates :tags, length: { maximum: 100 }
  validates :currency, length: { maximum: 10 }
  validates :units, length: { maximum: 15 }

  # Not persisted — set at creation time to skip seeding default step templates.
  attr_accessor :skip_templates

  STATUS = %w[Open Closed].freeze
  ACTIVITIES = Rack::Utils.parse_nested_query(ENV.fetch("DEAL_ACTIVITIES", "").tr(":", "=").tr(",", "&"))
  FUND_ACTIVITIES = Rack::Utils.parse_nested_query(ENV.fetch("FUND_DEAL_ACTIVITIES", "").tr(":", "=").tr(",", "&"))

  def create_activities
    deal_investors.each(&:create_activities)
  end

  def deal_documents_folder
    document_folder.children.where(name: "Deal Documents", folder_type: :regular, entity_id:, owner: self).first_or_create
  end

  def broadcast_message(message, level = "info")
    broadcast_replace_to [self, "deal_message"],
                         partial: '/deals/deal_message',
                         locals: { deal: self, message:, level: },
                         target: "deal_message"
  end

  def to_s
    name
  end

  def deal_investor_status
    current_value = self[:deal_investor_status]
    normalized = normalize_deal_investor_status(current_value)
    return normalized if normalized.present?

    normalize_deal_investor_status(json_fields&.[]("deal_investor_status"))
  end

  def deal_investor_status=(value)
    self[:deal_investor_status] = normalize_deal_investor_status(value)
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name status tags start_date end_date amount_cents currency archived created_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[deal_activities deal_investors investors]
  end

  def activity_names
    DealActivity.templates(self).collect(&:title)
  end

  def data_room_name
    "Overview"
  end

  def folder_path
    "/Deals/#{name.delete('/')}"
  end

  def folder_type
    :regular
  end

  def history
    versions.map(&:reify)
  end

  # Accepts a JSON string from the hidden form field and parses it before assigning.
  def grid_columns=(val)
    parsed = if val.is_a?(String)
               begin
                 JSON.parse(val)
               rescue StandardError
                 val
               end
             else
               val
             end
    super(parsed)
  end

  # Returns [{field:, label:}] for the JS column filter; defaults to all standard columns when none configured.
  def grid_columns_for_js
    label_map = DealInvestor::STANDARD_COLUMNS.each_with_object({}) do |(k, v), h|
      h[v.split("; ").first] = k.split("; ").first
    end
    cols = grid_columns.presence
    return label_map.map { |field, label| { field: field, label: label } } if cols.blank?

    # Extend with custom field labels so they resolve without a manual override
    entity.form_types.find_by(name: 'DealInvestor')&.form_custom_fields&.visible&.each do |cf|
      label_map["properties.#{cf.name}"] = cf.label.presence || cf.name.humanize
    end

    cols.filter_map do |col|
      field = col["field"].presence
      next unless field

      label    = col["label"].presence || label_map[field] || field.to_s.humanize
      position = col["position"].presence || "end"
      { field: field, label: label, position: position }
    end
  end

  private

  # Added a private method to normalize the deal_investor_status value to ensure it is always an array of strings, regardless of how it is provided (string, array, or JSON). This helps maintain consistency in how the status is stored and accessed throughout the application.
  def normalize_deal_investor_status(value)
    statuses = case value
               when String
                 parsed_value = JSON.parse(value) rescue nil
                 parsed_value.is_a?(Array) ? parsed_value : value.split(',')
               when Array
                 value
               else
                 Array.wrap(value)
               end

    statuses.map { |status| status.to_s.strip }.reject(&:blank?)
  end
end
