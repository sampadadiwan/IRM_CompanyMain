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

  # encrypts :name
  monetize :amount_cents, with_model_currency: :currency

  # Make all models searchable
  update_index('deal') { self if index_record? }

  belongs_to :entity
  # belongs_to :clone_from, optional: true, class_nane: "Deal"

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

  STATUS = %w[Open Closed].freeze
  ACTIVITIES = Rack::Utils.parse_nested_query(ENV["DEAL_ACTIVITIES"].tr(":", "=").tr(",", "&"))
  FUND_ACTIVITIES = Rack::Utils.parse_nested_query(ENV["FUND_DEAL_ACTIVITIES"].tr(":", "=").tr(",", "&"))

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
    versions.each(&:reify)
  end
end
