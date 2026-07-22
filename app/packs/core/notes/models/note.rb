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
  def update_investor
    return unless owner.respond_to?(:last_interaction_date=)

    owner.last_interaction_date = created_at
    owner.save
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[tags details owner_type created_at on]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[user]
  end
end
