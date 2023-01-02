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
  # belongs_to :clone_from, optional: true, class_nane: "Deal"

  counter_culture :entity
  delegate :name, to: :entity, prefix: :entity

  has_many :deal_investors, dependent: :destroy
  has_many :investors, through: :deal_investors

  has_many :deal_activities, dependent: :destroy

  has_many :documents, as: :owner, dependent: :destroy
  has_many :access_rights, as: :owner, dependent: :destroy
  has_many :tasks, as: :owner, dependent: :destroy
  belongs_to :data_room_folder, class_name: "Folder", dependent: :destroy, optional: true

  # Customize form
  belongs_to :form_type, optional: true
  serialize :properties, Hash

  validates :name, :amount_cents, :status, :currency, presence: true

  STATUS = %w[Open Closed].freeze
  ACTIVITIES = Rack::Utils.parse_nested_query(ENV["DEAL_ACTIVITIES"].tr(":", "=").tr(",", "&"))
  FUND_ACTIVITIES = Rack::Utils.parse_nested_query(ENV["FUND_DEAL_ACTIVITIES"].tr(":", "=").tr(",", "&"))

  after_create_commit :create_data_room

  def create_data_room
    self.data_room_folder = document_folder.children.where(entity_id:, name: "Data Room", folder_type: :regular).first_or_create
    save
  end

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

  def folder_type
    :regular
  end

  def history
    versions.each(&:reify)
  end

  def access_rights_changed(access_right)
    ar = AccessRight.where(id: access_right.id).first
    if ar
      # Add this ar to the data room
      data_room_ar = ar.dup
      data_room_ar.owner = data_room_folder
      data_room_ar.cascade = true
      data_room_ar.save
    else
      # Remove this ar to the data room
      data_room_folder.access_rights.where(access_to_investor_id: access_right.access_to_investor_id, access_to_category: access_right.access_to_category, user_id: access_right.user_id).each(&:destroy)
    end
  end
end
