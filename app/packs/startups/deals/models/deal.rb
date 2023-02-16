class Deal < ApplicationRecord
  include Trackable
  include WithFolder
  include WithDataRoom
  include WithCustomField
  # include ActivityTrackable
  # include Impressionable

  # encrypts :name
  monetize :amount_cents, with_model_currency: :currency

  # Make all models searchable
  update_index('deal') { self }

  belongs_to :entity
  # belongs_to :clone_from, optional: true, class_nane: "Deal"

  counter_culture :entity
  delegate :name, to: :entity, prefix: :entity

  has_many :deal_investors, dependent: :destroy
  has_many :investors, through: :deal_investors

  has_many :deal_activities, dependent: :destroy
  has_many :access_rights, as: :owner, dependent: :destroy
  has_many :tasks, as: :owner, dependent: :destroy

  validates :name, :amount_cents, :status, :currency, presence: true

  STATUS = %w[Open Closed].freeze
  ACTIVITIES = Rack::Utils.parse_nested_query(ENV["DEAL_ACTIVITIES"].tr(":", "=").tr(",", "&"))
  FUND_ACTIVITIES = Rack::Utils.parse_nested_query(ENV["FUND_DEAL_ACTIVITIES"].tr(":", "=").tr(",", "&"))

  def create_activities
    deal_investors.each(&:create_activities)
  end

  def broadcast_message(message, level = "info")
    broadcast_replace_to [self, "deal_message"],
                         partial: '/deals/deal_message',
                         locals: { deal: self, message:, level: },
                         target: "deal_message"
  end

  scope :for_employee, lambda { |user|
    includes(:access_rights).joins(:access_rights).where("deals.entity_id=? and access_rights.user_id=?", user.entity_id, user.id)
  }

  scope :for_advisor, lambda { |user|
    # Ensure the access rghts for Document
    includes(:access_rights).joins(:access_rights).merge(AccessRight.access_filter(user))
                            .where("access_rights.metadata=?", "Advisor").joins(entity: :investors)
                            .where("investors.investor_entity_id=?", user.entity_id)
  }

  scope :for_investor, lambda { |user|
    joins(:access_rights)
      .merge(AccessRight.access_filter(user))
      .joins(:investors)
      # Ensure that the user is an investor and tis investor has been given access rights
      .where("investors.investor_entity_id=?", user.entity_id)
      # Ensure this user has investor access
      .joins(entity: :investor_accesses)
      .merge(InvestorAccess.approved_for_user(user))
  }

  def to_s
    name
  end

  def activity_names
    DealActivity.templates(self).collect(&:title)
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

  def investor_users(metadata = nil)
    User.joins(investor_accesses: :investor).where("investor_accesses.approved=? and investor_accesses.entity_id=?", true, entity_id).merge(Investor.owner_access_rights(self, metadata))
  end
end
