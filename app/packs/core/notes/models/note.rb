class Note < ApplicationRecord
  # include Trackable.new
  update_index('note') { self if index_record? || details.body_previously_changed? }

  # encrypts :details
  validates :details, presence: true
  validates :tags, length: { maximum: 100 }

  has_rich_text :details
  belongs_to :entity
  belongs_to :user
  belongs_to :owner, polymorphic: true, optional: true
  attr_readonly :owner_id, :owner_type # never moves to another owner (funds_api_security_policy_plan.md, B)

  # LP CRM: the person at the LP this note was with — the contact's InvestorAccess
  # record, plus the guard that keeps it a contact of the note's own stakeholder.
  # Works for both Investor-owned notes and notes logged under a DealInvestor
  # (whose contacts are its parent LP's contacts). See WithTouchPoint.
  include WithTouchPoint

  delegate :full_name, to: :user, prefix: :user

  has_one :reminder, as: :owner, dependent: :destroy
  accepts_nested_attributes_for :reminder, allow_destroy: true, update_only: true

  # Frozen inputs for owner_type
  OWNER_TYPES = %w[User Investor DealInvestor].freeze

  def investor_name
    owner.respond_to?(:investor_name) ? owner.investor_name : owner&.to_s
  end

  def to_s
    # If the owner is nill then return empty str if it is an Investor, return the investor_name; otherwise, return the owner's string representation.
    if owner
      owner.respond_to?(:investor_name) ? owner.investor_name : owner.to_s
    else
      ""
    end
  end

  after_save :update_investor

  # A DealInvestor's last_interaction_date is "the latest date a user actually put
  # on a note", so only `on` counts and it never moves backwards — an undated note
  # leaves it alone. Investor keeps its long-standing created_at behaviour, which
  # Investor.not_interacted reads.
  #
  # Deleting a note deliberately does not recompute: removing a record should not
  # silently rewind an investor's history.
  def update_investor
    if owner.is_a?(DealInvestor)
      owner.register_interaction(self[:on])
    elsif owner.respond_to?(:last_interaction_date=)
      owner.last_interaction_date = created_at
      owner.save
    end
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[tags details owner_type created_at on]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[user]
  end
end
