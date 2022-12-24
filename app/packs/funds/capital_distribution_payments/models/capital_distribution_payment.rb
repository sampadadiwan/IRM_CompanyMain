class CapitalDistributionPayment < ApplicationRecord
  include Trackable
  include ActivityTrackable
  tracked owner: proc { |_controller, model| model.fund }, entity_id: proc { |_controller, model| model.entity_id }

  include FundScopes
  update_index('capital_distribution_payment') { self }

  belongs_to :fund, touch: true
  belongs_to :entity
  belongs_to :capital_distribution, touch: true
  belongs_to :investor
  belongs_to :capital_commitment
  belongs_to :form_type, optional: true
  serialize :properties, Hash

  monetize :amount_cents, with_currency: ->(i) { i.fund.currency }
  validates :folio_id, presence: true
  validates_uniqueness_of :folio_id, scope: :capital_distribution_id

  counter_culture :capital_distribution,
                  column_name: proc { |r| r.completed ? 'distribution_amount_cents' : nil },
                  delta_column: 'amount_cents',
                  column_names: {
                    ["capital_distribution_payments.completed = ?", true] => 'distribution_amount_cents'
                  }

  counter_culture :fund,
                  column_name: proc { |r| r.completed ? 'distribution_amount_cents' : nil },
                  delta_column: 'amount_cents',
                  column_names: {
                    ["capital_distribution_payments.completed = ?", true] => 'distribution_amount_cents'
                  }

  counter_culture :capital_commitment,
                  column_name: 'distribution_amount_cents',
                  delta_column: 'amount_cents'

  before_validation :ensure_commitment
  def ensure_commitment
    self.capital_commitment = fund.capital_commitments.where(investor_id:, folio_id:).first
  end

  after_commit :send_notification, if: :completed
  def send_notification
    CapitalDistributionPaymentsMailer.with(id:).send_notification.deliver_later if saved_change_to_completed? && capital_distribution.approved && !capital_distribution.manual_generation
  end
end
