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

  validates :name, :amount_cents, :status, :currency, presence: true
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
    parsed = val.is_a?(String) ? (JSON.parse(val) rescue val) : val
    super(parsed)
  end

  # Returns [{field:, label:}] for the JS column filter; defaults to all standard columns when none configured.
  def grid_columns_for_js
    label_map = DealInvestor::STANDARD_COLUMNS.each_with_object({}) do |(k, v), h|
      h[v.split("; ").first] = k.split("; ").first
    end
    cols = grid_columns.presence
    return label_map.map { |field, label| { field: field, label: label } } if cols.blank?

    cols.map do |col|
      field = col["field"].presence
      next unless field
      label    = col["label"].presence || label_map[field] || field.to_s.humanize
      position = col["position"].presence || "end"
      { field: field, label: label, position: position }
    end.compact
  end
end
