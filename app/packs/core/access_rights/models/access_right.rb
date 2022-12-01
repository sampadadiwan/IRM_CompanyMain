class AccessRight < ApplicationRecord
  # include Trackable
  include ActivityTrackable

  update_index('access_right') { self }

  ALL = "All".freeze
  SELF = "Self".freeze
  SUMMARY = "Summary".freeze
  VIEWS = [ALL, SELF].freeze
  TYPES = ["All Users for Specific Investor", "All Investors of Specific Category"].freeze

  # Additional permission - this is experimental and does not work yet
  flag :permissions, %i[create read update destroy]

  belongs_to :owner, polymorphic: true, touch: true # , strict_loading: true
  belongs_to :entity
  # If this is a user access
  belongs_to :user, optional: true
  # If this is a specific investor access
  belongs_to :investor, foreign_key: :access_to_investor_id, optional: true # , strict_loading: true

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

  scope :for_secondary_sale, lambda { |secondary_sale|
                               where("(access_rights.entity_id=?
                                             and access_rights.owner_id=?
                                             and access_rights.owner_type=?)",
                                     secondary_sale.entity_id, secondary_sale.id, "SecondarySale")
                             }

  scope :investor_access, lambda { |investor|
                            where(" (access_rights.entity_id=?) AND
                                    (access_rights.access_to_investor_id=? OR access_rights.access_to_category=?)",
                                  investor.entity_id, investor.id, investor.category)
                          }

  scope :access_filter, lambda {
    where("investors.category=access_rights.access_to_category OR access_rights.access_to_investor_id=investors.id")
  }

  validate :any_present?

  def any_present?
    errors.add :base, "Must specify Investor or Category" if %w[access_to_investor_id access_to_category user_id].all? { |attr| self[attr].blank? }
  end

  validate :access_is_unique
  def access_is_unique
    errors.add(:owner, 'Duplicate! already has this permission') if AccessRight.where.not(id:).exists?(owner:, access_to_investor_id:, access_to_category:, user_id:)
  end

  def to_s
    access_to_label
  end

  def types
    owner_class_name = owner.class.name
    case owner_class_name
    when "Deal", "DealInvestor"
      AccessRight::TYPES - ["All Investors of Specific Category"]
    when "Fund", "SecondarySale"
      AccessRight::TYPES + ["Employee"]
    else
      AccessRight::TYPES
    end
  end

  def access_to_label
    label = access_to_category if access_to_category.present?
    label ||= investor.investor_name if access_to_investor_id.present?

    label
  end

  # Emails of all approved investor users
  def investor_emails
    emails = []

    if access_to_investor_id.present?
      # Get all the investor -> investor access that are approved, and get the email addresses
      emails = investor.investor_accesses.approved.collect(&:email) unless investor.is_holdings_entity
    elsif access_to_category.present?
      # Get all the investors with this category -> investor access that are approved, and get the email addresses
      Investor.where(entity_id:, category: access_to_category, is_holdings_entity: false).find_each do |investor|
        emails += investor.investor_accesses.approved.collect(&:email)
      end
    end

    emails
  end

  # Emails of all holding investor users
  def holding_employees_emails
    emails = []

    if access_to_investor_id.present? && investor.is_holdings_entity
      # Get all the investor employees emails
      emails = investor.investor_entity.employees.collect(&:email)
    elsif access_to_category.present?
      # Get all the investors entity employees and get the email addresses
      Investor.where(entity_id:, category: access_to_category, is_holdings_entity: true).find_each do |investor|
        emails += investor.investor_entity.employees.collect(&:email)
      end
    end

    emails
  end

  def employee_users(metadata)
    User.joins(entity: :investees).where("investors.is_holdings_entity=? and investors.entity_id=?", true, entity_id).merge(Investor.with_access_rights(self, metadata))
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
    if Rails.env.test?
      AccessRightsMailer.with(access_right_id: id).notify_access.deliver_later
    else
      AccessRightsMailer.with(access_right_id: id).notify_access.deliver_later(wait_until: rand(30).seconds.from_now)
    end
  end

  after_create_commit :update_owner
  after_destroy :update_owner
  def update_owner
    owner.access_rights_changed(id) if owner.respond_to? :access_rights_changed
  end

  def investors
    if access_to_category.present?
      entity.investors.where(category: access_to_category)
    else
      [investor]
    end
  end
end
