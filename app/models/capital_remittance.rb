class CapitalRemittance < ApplicationRecord
  include ActivityTrackable
  tracked owner: proc { |_controller, model| model.fund }, entity_id: proc { |_controller, model| model.entity_id }

  belongs_to :entity
  belongs_to :fund, touch: true
  belongs_to :capital_call
  belongs_to :capital_commitment
  belongs_to :investor

  belongs_to :form_type, optional: true
  serialize :properties, Hash

  has_many_attached :payment_proof, service: :amazon

  scope :paid, -> { where(status: "Paid") }
  scope :pending, -> { where(status: "Pending") }

  monetize :call_amount_cents, :collected_amount_cents, with_currency: ->(i) { i.entity.currency }

  before_validation :set_capital_commitment
  def set_capital_commitment
    self.capital_commitment = fund.capital_commitments.where(investor_id:).first
  end

  counter_culture :capital_call, column_name: proc { |r| r.verified ? 'collected_amount_cents' : nil },
                                 delta_column: 'collected_amount_cents'

  counter_culture :capital_call, column_name: 'call_amount_cents',
                                 delta_column: 'call_amount_cents'

  counter_culture :capital_commitment, column_name: proc { |r| r.verified ? 'collected_amount_cents' : nil },
                                       delta_column: 'collected_amount_cents'

  counter_culture :fund, column_name: proc { |r| r.verified ? 'collected_amount_cents' : nil },
                         delta_column: 'collected_amount_cents'

  counter_culture :fund, column_name: 'call_amount_cents',
                         delta_column: 'call_amount_cents'

  before_save :set_status
  before_create :set_call_amount
  def set_call_amount
    self.call_amount_cents = capital_commitment ? capital_call.percentage_called * capital_commitment.committed_amount_cents / 100.0 : 0

    set_status
  end

  def set_status
    self.status = if call_amount_cents == collected_amount_cents
                    "Paid"
                  else
                    "Pending"
                  end
  end

  def due_amount
    call_amount - collected_amount
  end

  def to_s
    "#{investor.investor_name}: #{due_amount}: #{status}"
  end
end
