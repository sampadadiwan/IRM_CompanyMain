class AccessRight < ApplicationRecord
  include Trackable.new

  # To allow tag_list for creating new access rights
  attr_accessor :tag_list

  update_index('access_right') { self if index_record? }

  ALL = "All".freeze
  SELF = "Self".freeze
  SUMMARY = "Summary".freeze
  VIEWS = [ALL, SELF].freeze
  TYPES = ["All Users for Specific Stakeholder", "All Stakeholders of Specific Category", "All Stakeholders with Tag"].freeze

  # Additional permissions for access rights, for employees/advisors specifically
  flag :permissions, %i[create read update destroy]

  belongs_to :owner, polymorphic: true # , strict_loading: true
  belongs_to :entity
  # If this is a user access
  belongs_to :user, optional: true
  belongs_to :granted_by, class_name: "User", optional: true
  # If this is a specific investor access
  belongs_to :investor, foreign_key: :access_to_investor_id, optional: true # , strict_loading: true
  has_many :noticed_events, as: :record, dependent: :destroy, class_name: "Noticed::Event"

  delegate :name, to: :entity, prefix: :entity
  delegate :name, to: :owner, prefix: :owner

  scope :investments, -> { where(access_type: "Investment") }
  scope :documents, -> { where(access_type: "Document") }
  scope :deals, -> { where(access_type: "Deal") }

  scope :for_user, ->(user_id) { where(user_id:) }
  scope :not_user, -> { where(user_id: nil) }

  scope :for, ->(owner) { where(owner_id: owner.id, owner_type: owner.class.name) }
  scope :for_access_type, ->(type) { where("access_rights.access_type=?", type) }

  scope :for_investor, lambda { |investor|
                         where("(access_rights.entity_id=?
                                        and access_rights.access_to_investor_id is NULL
                                        and access_rights.access_to_category=?)
                                        OR (access_rights.access_to_investor_id=?)",
                               investor.entity_id, investor.category, investor.id)
                       }

  scope :investor_access, lambda { |investor, user|
                            where(" (access_rights.entity_id=?) AND
                                    ( access_rights.access_to_investor_id=? OR
                                    access_rights.access_to_category=? OR
                                    access_rights.user_id=? )",
                                  investor.entity_id, investor.id, investor.category, user.id)
                          }

  scope :access_filter, lambda { |user|
    if user.investor_advisor?
      # Since he is currently playing the role of IA, we should only use the access_rights
      # given to his specific user id
      where("access_rights.user_id=? OR access_rights.access_to_investor_id=investors.id", user.id)
    elsif user.has_cached_role?(:investor_advisor) && !user.investor_advisor?
      # This is to avoid duplicates in the results of the final query
      # If the user has the role but is not currently switched as an IA for another investor
      # Then essentially he is looking for his own funds/commitments/etc - so we dont use the user_id here
      # We join only based on his own investor id
      where("investors.category=access_rights.access_to_category OR access_rights.access_to_investor_id=investors.id")
    else
      # For regular users
      where("investors.category=access_rights.access_to_category OR access_rights.access_to_investor_id=investors.id OR access_rights.user_id=?", user.id)
    end
  }

  scope :access_filter_for_rm, lambda { |user|
    where("access_rights.access_to_category='RM' OR access_rights.access_to_investor_id=rm_mappings.rm_id OR access_rights.user_id=?", user.id)
  }

  # This scope is used to filter access rights for investor advisors, who manage folios for investors.
  # Investors grant access_rights to the Fund or Sale or Deal, to the investor advisor.
  # Do not call this with a user who is not an investor_advisor
  scope :investor_granted_access_filter, lambda { |user, across_all_entities: false|
    if across_all_entities && user.has_cached_role?(:investor_advisor)
      # This is used only in the case of sending emails, when the advisor is logged in as an investor, but emails need to be sent out irrespective of which investor they are currently switched into
      where("access_rights.user_id=?", user.id)
    else
      # This kicks in when the investor advisor is logged in and switches to a specific investor
      where("access_rights.user_id=? and access_rights.entity_id=?", user.id, user.entity_id)
    end
  }

  validates :access_to_email, length: { maximum: 30 }
  validates :access_type, length: { maximum: 25 }
  validates :access_to_category, length: { maximum: 20 }
  validate :any_present?

  def any_present?
    errors.add :base, "Must specify Investor or Category" if %w[access_to_investor_id access_to_category user_id].all? { |attr| self[attr].blank? }
  end

  validate :access_is_unique
  def access_is_unique
    errors.add(:owner, 'Duplicate! already has this permission') if AccessRight.where.not(id:).exists?(owner:, access_to_investor_id:, access_to_category:, user_id:, entity_id:)
  end

  def to_s
    access_to_label
  end

  def types
    case owner_type
    when "Deal"
      ["All Users for Specific Stakeholder"] + %w[Employee Advisor]
    when "Fund", "InvestmentOpportunity", "SecondarySale"
      AccessRight::TYPES + %w[Employee Advisor]
    when "Document", "Folder"
      AccessRight::TYPES + ["Specific User", "Employee"]
    else
      AccessRight::TYPES
    end
  end

  def access_to_label
    label = access_to_category if access_to_category.present?
    label ||= investor.investor_name if access_to_investor_id.present?
    label ||= user.full_name if user_id.present?

    label
  end

  # Emails of all approved investor users
  def investor_emails
    emails = []

    if access_to_investor_id.present?
      # Get all the investor -> investor access that are approved, and get the email addresses
      emails = investor.investor_accesses.approved.collect(&:email)
    elsif access_to_category.present?
      # Get all the investors with this category -> investor access that are approved, and get the email addresses
      Investor.where(entity_id:, category: access_to_category).find_each do |investor|
        emails += investor.investor_accesses.approved.collect(&:email)
      end
    end

    emails
  end

  before_save :strip_fields
  def strip_fields
    self.access_to_category = access_to_category.strip if access_to_category
    self.metadata = metadata.strip if metadata
    self.access_type = access_type.strip if access_type
    self.access_type ||= owner_type
  end

  after_create_commit :send_notification
  def send_notification
    if notify && (%w[Document Folder].exclude?(owner_type) || (owner.respond_to?(:send_email) && owner.send_email))
      users.each do |user|
        msg = "You have been granted access to #{owner_type} #{owner.name} by #{entity.name}"
        AccessRightNotifier.with(record: self, entity_id:, msg:).deliver_later(user)
      end
    end
  end

  after_commit :add_to_user_access_rights_cache, unless: -> { destroyed? || deleted_at.present? || owner_type == "Folder" }
  def add_to_user_access_rights_cache
    # We have couple of cases
    # 1 AR is for category, so we need to add it to all the investor users of that category
    # 2 AR is for investor, so we need to add it to all the users of that investor
    # 3 AR is for user, so we need to add it to that user
    if access_to_category.present?
      # Get all the investors with this category -> investor access that are approved
      investors.each do |investor|
        investor.add_to_user_access_rights_cache(self)
      end
    elsif access_to_investor_id.present?
      # Get all the investor -> investor access that are approved
      investor.add_to_user_access_rights_cache(self)
    elsif user_id.present?
      # Add it to the user cache
      user.cache_access_rights(self)
    end
  end

  after_destroy_commit :remove_from_user_access_rights_cache, unless: -> { owner_type == "Folder" }
  def remove_from_user_access_rights_cache
    if access_to_category.present?
      # Get all the investors with this category -> investor access that are approved
      investors.each do |investor|
        investor.remove_from_user_access_rights_cache(self)
      end
    elsif access_to_investor_id.present?
      # Get all the investor -> investor access that are approved
      inv = Investor.with_deleted.find(access_to_investor_id)
      inv.remove_from_user_access_rights_cache(self)
    elsif user_id.present?
      # Add it to the user cache
      u = User.with_deleted.find(user_id)
      u.remove_access_rights_cache(self)
    end
  end

  def users
    if user_id.present?
      [user]
    elsif access_to_investor_id.present?
      investor.notification_users(owner)
    elsif access_to_category.present?
      User.joins(investor_accesses: :investor).where(entity_id:, 'investors.category': access_to_category).where(investor_accesses: { approved: true })
    else
      []
    end
  end

  after_commit :update_owner
  # rubocop:disable Rails/SkipsModelValidations
  # This is to bust any cached dashboards showing the commitments
  def update_owner
    # Update the investors entity to bust any cache
    Entity.where(id: investors.pluck(:investor_entity_id)).update_all(updated_at: Time.zone.now)
    # Update the owner to bust any cache
    # owner.touch
    # Tell the owner that the access rights have changed
    owner.access_rights_changed(self) if owner.respond_to?(:access_rights_changed)
  end
  # rubocop:enable Rails/SkipsModelValidations

  after_destroy lambda {
    AccessRightsDeletedJob.perform_later(owner_id, owner_type, id) if owner.respond_to?(:document_folder) || owner_type == "Folder"
  }

  def investors
    if access_to_category.present?
      entity.investors.where(category: access_to_category)
    else
      investor ? [investor] : []
    end
  end

  def self.grant(owner, investor_id)
    AccessRight.create(owner:, access_to_investor_id: investor_id, entity_id: owner.entity_id)
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[access_to_category access_to_investor_id user_id].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[investor user]
  end
end
