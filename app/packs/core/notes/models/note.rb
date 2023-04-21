class Note < ApplicationRecord
  # include Trackable
  update_index('note') { self }

  # encrypts :details
  validates :details, presence: true

  has_rich_text :details
  belongs_to :entity
  belongs_to :user
  belongs_to :investor
  delegate :investor_name, to: :investor
  delegate :full_name, to: :user, prefix: :user

  has_one :reminder, as: :owner
  accepts_nested_attributes_for :reminder, allow_destroy: true, update_only: true

  def to_s
    investor.investor_name
  end

  after_save :update_investor
  def update_investor
    investor.last_interaction_date = created_at
    investor.save
  end
end
