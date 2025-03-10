class Note < ApplicationRecord
  # include Trackable.new
  update_index('note') { self if index_record? || details.body_previously_changed? }

  # encrypts :details
  validates :details, presence: true
  validates :tags, length: { maximum: 100 }

  has_rich_text :details
  belongs_to :entity
  belongs_to :user
  belongs_to :investor
  delegate :investor_name, to: :investor
  delegate :full_name, to: :user, prefix: :user

  has_one :reminder, as: :owner, dependent: :destroy
  accepts_nested_attributes_for :reminder, allow_destroy: true, update_only: true

  def to_s
    investor.investor_name
  end

  after_save :update_investor
  def update_investor
    investor.last_interaction_date = created_at
    investor.save
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[tags details created_at on]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[investor user]
  end
end
