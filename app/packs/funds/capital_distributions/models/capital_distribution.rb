class CapitalDistribution < ApplicationRecord
  include ActivityTrackable
  tracked owner: proc { |_controller, model| model.fund }, entity_id: proc { |_controller, model| model.entity_id }

  belongs_to :fund, touch: true
  belongs_to :entity
  belongs_to :form_type, optional: true
  belongs_to :approved_by_user, class_name: "User", optional: true

  has_many :capital_distribution_payments, dependent: :destroy

  monetize :net_amount_cents, :carry_cents, :gross_amount_cents, :distribution_amount_cents, with_currency: ->(i) { i.entity.currency }

  before_save :compute_net_amount
  def compute_net_amount
    self.net_amount_cents = gross_amount_cents - carry_cents
  end

  after_create ->(cd) { CapitalDistributionJob.perform_later(cd.id) }

  scope :for_employee, lambda { |user|
    joins(fund: :access_rights).where("funds.entity_id=? and access_rights.user_id=?", user.entity_id, user.id)
  }

  scope :for_investor, lambda { |user|
    joins(fund: :access_rights)
      .merge(AccessRight.access_filter)
      .joins(entity: :investors)
      # Ensure that the user is an investor and tis investor has been given access rights
      # .where("entities.id=?", entity.id)
      .where("investors.investor_entity_id=?", user.entity_id)
      # Ensure this user has investor access
      .joins(entity: :investor_accesses)
      .merge(InvestorAccess.approved_for_user(user))
  }

  def to_s
    title
  end

  scope :for_advisor, lambda { |user|
    # Ensure the access rghts for Document
    joins(fund: :access_rights).merge(AccessRight.access_filter)
                               .where("access_rights.metadata=?", "Advisor").joins(entity: :investors)
                               .where("investors.investor_entity_id=?", user.entity_id)
  }
end
