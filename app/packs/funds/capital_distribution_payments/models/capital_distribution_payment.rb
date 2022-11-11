class CapitalDistributionPayment < ApplicationRecord
  belongs_to :fund, touch: true
  belongs_to :entity
  belongs_to :capital_distribution, touch: true
  belongs_to :investor
  belongs_to :form_type, optional: true

  monetize :amount_cents, with_currency: ->(i) { i.entity.currency }

  counter_culture :fund,
                  column_name: proc { |r| r.completed ? 'distribution_amount_cents' : nil },
                  delta_column: 'amount_cents'

  counter_culture :capital_distribution,
                  column_name: proc { |r| r.completed ? 'distribution_amount_cents' : nil }, delta_column: 'amount_cents'

  scope :for_employee, lambda { |user|
    joins(fund: :access_rights).where("funds.entity_id=? and access_rights.user_id=?", user.entity_id, user.id)
  }

  scope :for_investor, lambda { |user|
    # Ensure the access rghts for Document
    joins(:investor, fund: :access_rights)
      .merge(AccessRight.access_filter)
      .where("investors.investor_entity_id=?", user.entity_id)
      # Ensure this user has investor access
      .joins(entity: :investor_accesses)
      .merge(InvestorAccess.approved_for_user(user))
  }

  scope :for_advisor, lambda { |user|
    # Ensure the access rghts for Document
    joins(fund: :access_rights).merge(AccessRight.access_filter)
                               .where("access_rights.metadata=?", "Advisor").joins(entity: :investors)
                               .where("investors.investor_entity_id=?", user.entity_id)
  }

  after_save :send_notification, if: :completed
  def send_notification
    CapitalDistributionPaymentsMailer.with(id:).send_notification.deliver_later if saved_change_to_completed? && capital_distribution.approved
  end
end
