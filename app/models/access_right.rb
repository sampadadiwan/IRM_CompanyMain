# == Schema Information
#
# Table name: access_rights
#
#  id                    :integer          not null, primary key
#  owner_type            :string(255)      not null
#  owner_id              :integer          not null
#  access_to_email       :string(30)
#  access_to_investor_id :integer
#  access_type           :string(15)
#  metadata              :string(255)
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  entity_id             :integer          not null
#  access_to_category    :string(20)
#  deleted_at            :datetime
#

class AccessRight < ApplicationRecord
  include Trackable
  include ActivityTrackable

  update_index('access_right') { self }

  ALL = "All".freeze
  SELF = "Self".freeze
  SUMMARY = "Summary".freeze
  VIEWS = [ALL, SELF].freeze
  TYPES = ["All Users for Specific Investor", "All Investors of Specific Category"].freeze

  belongs_to :owner, polymorphic: true # , strict_loading: true
  belongs_to :entity
  belongs_to :investor, foreign_key: :access_to_investor_id, optional: true # , strict_loading: true

  delegate :name, to: :entity, prefix: :entity
  delegate :name, to: :owner, prefix: :owner

  scope :investments, -> { where(access_type: "Investment") }
  scope :documents, -> { where(access_type: "Document") }
  scope :deals, -> { where(access_type: "Deal") }

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
    errors.add :base, "Must specify Investor or Category" if %w[access_to_investor_id access_to_category].all? { |attr| self[attr].blank? }
  end

  validate :access_is_unique
  def access_is_unique
    errors.add(:owner, 'Duplicate! already has this permission') if AccessRight.exists?(owner:, access_to_investor_id:, access_to_category:)
  end

  def to_s
    access_to_label
  end

  def access_to_label
    label = access_to_category if access_to_category.present?
    label ||= investor.investor_name if access_to_investor_id.present?

    label
  end

  # Emails of all approved investor users
  def investor_emails
    emails = []

    if access_to_investor_id.present? && !investor.is_holdings_entity
      # Get all the investor -> investor access that are approved, and get the email addresses
      emails = investor.investor_accesses.approved.collect(&:email)
    elsif access_to_category.present?
      # Get all the investors with this category -> investor access that are approved, and get the email addresses
      investors = Investor.where(entity_id:, category: access_to_category)
      investors.each do |investor|
        emails += investor.investor_accesses.approved.collect(&:email)
      end
    end

    emails
  end

  # Emails of all holding investor users
  def holding_employees_emails
    emails = []

    if access_to_investor_id.present? && investor.is_holdings_entity
      # Get all the investor -> investor access that are approved, and get the email addresses
      emails = investor.investor_accesses.collect(&:email)
    end

    emails
  end

  before_save :strip_fields
  def strip_fields
    self.access_to_category = access_to_category.strip if access_to_category
    self.metadata = metadata.strip if metadata
    self.access_type = access_type.strip if access_type
  end

  after_create :send_notification
  def send_notification
    AccessRightsMailer.with(access_right_id: id).notify_access.deliver_later
  end

  after_create :update_owner
  def update_owner
    owner.access_rights_changed(id) if owner.respond_to? :access_rights_changed
  end
end
