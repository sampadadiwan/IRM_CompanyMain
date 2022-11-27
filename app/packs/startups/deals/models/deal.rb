class Deal < ApplicationRecord
  include Trackable
  include WithFolder
  # include ActivityTrackable
  # include Impressionable

  # encrypts :name
  monetize :amount_cents, with_model_currency: :currency

  # Make all models searchable
  update_index('deal') { self }

  belongs_to :entity
  counter_culture :entity
  delegate :name, to: :entity, prefix: :entity

  has_many :deal_investors, dependent: :destroy
  has_many :investors, through: :deal_investors

  has_many :deal_activities, dependent: :destroy

  has_many :documents, as: :owner, dependent: :destroy
  has_many :access_rights, as: :owner, dependent: :destroy
  has_many :tasks, as: :owner, dependent: :destroy

  # Customize form
  belongs_to :form_type, optional: true
  serialize :properties, Hash

  validates :name, :amount_cents, :status, :currency, presence: true

  STATUS = %w[Open Closed].freeze
  ACTIVITIES = Rack::Utils.parse_nested_query(ENV["DEAL_ACTIVITIES"].tr(":", "=").tr(",", "&"))

  def create_activities
    deal_investors.each(&:create_activities)
  end

  def start_deal
    self.start_date = Time.zone.today
    save
    GenerateDealActivitiesJob.perform_later(id, "Deal")
  end

  def started?
    start_date != nil
  end

  scope :for_advisor, lambda { |user|
    # Ensure the access rghts for Document
    includes(:access_rights).joins(:access_rights).merge(AccessRight.access_filter)
                            .where("access_rights.metadata=?", "Advisor").joins(entity: :investors)
                            .where("investors.investor_entity_id=?", user.entity_id)
  }

  scope :for_investor, lambda { |user|
    joins(:access_rights)
      .merge(AccessRight.access_filter)
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
    "/Deals/#{name}-#{id}"
  end

  def setup_folder_details
    setup_folder_from_path(folder_path)
  end
end
