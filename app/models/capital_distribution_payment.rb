class CapitalDistributionPayment < ApplicationRecord
  belongs_to :fund
  belongs_to :entity
  belongs_to :capital_distribution, touch: true
  belongs_to :investor
  belongs_to :form_type, optional: true

  monetize :amount_cents, with_currency: ->(i) { i.entity.currency }

  counter_culture :fund, column_name: proc { |r| r.completed ? 'distribution_amount_cents' : nil },
                         delta_column: 'amount_cents'

  counter_culture :capital_distribution, column_name: proc { |r| r.completed ? 'distribution_amount_cents' : nil },
                                         delta_column: 'amount_cents'

  def self.for_investor(user)
    CapitalDistributionPayment
      # Ensure the access rghts for Document
      .joins(fund: :access_rights)
      .merge(AccessRight.access_filter)
      .joins(entity: :investors)
      # Ensure that the user is an investor and tis investor has been given access rights
      # .where("entities.id=?", entity.id)
      .where("investors.investor_entity_id=?", user.entity_id)
      # Ensure this user has investor access
      .joins(entity: :investor_accesses)
      .merge(InvestorAccess.approved_for_user(user))
  end
end
