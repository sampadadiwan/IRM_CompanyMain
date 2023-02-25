class CapitalDistribution < ApplicationRecord
  include WithCustomField
  include Trackable
  include ActivityTrackable
  tracked owner: proc { |_controller, model| model.fund }, entity_id: proc { |_controller, model| model.entity_id }

  include ForInvestor

  belongs_to :fund, touch: true
  belongs_to :entity
  belongs_to :approved_by_user, class_name: "User", optional: true

  has_many :capital_distribution_payments, dependent: :destroy, inverse_of: :capital_distribution
  # Stores the prices for unit types for this call
  serialize :unit_prices, Hash

  monetize :net_amount_cents, :reinvestment_cents, :gross_amount_cents, :distribution_amount_cents, with_currency: ->(i) { i.fund.currency }

  before_save :compute_net_amount
  def compute_net_amount
    self.net_amount_cents = gross_amount_cents - reinvestment_cents
  end

  after_commit :generate_distribution_payments

  def generate_distribution_payments
    if generate_payments
      Rails.logger.debug { "generate_distribution_payments called for #{id}" }
      CapitalDistributionJob.perform_later(id)
    else
      Rails.logger.debug { "Skipping generate_distribution_payments for #{id}, generate_payments is false" }
    end
  end

  def to_s
    title
  end
end
