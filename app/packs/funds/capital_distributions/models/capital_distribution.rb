class CapitalDistribution < ApplicationRecord
  include ActivityTrackable
  tracked owner: proc { |_controller, model| model.fund }, entity_id: proc { |_controller, model| model.entity_id }

  include FundScopes

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

  after_save :generate_payments

  def generate_payments
    if manual_generation
      Rails.logger.debug { "Skipping generate_payments for #{id}, manual_generation is true" }
    else
      Rails.logger.debug { "generate_payments called for #{id}" }
      CapitalDistributionJob.perform_later(id)
    end
  end

  def to_s
    title
  end
end
