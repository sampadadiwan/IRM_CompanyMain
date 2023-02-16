class CapitalRemittance < ApplicationRecord
  include ActivityTrackable
  tracked owner: proc { |_controller, model| model.fund }, entity_id: proc { |_controller, model| model.entity_id }
  include Trackable
  include FundScopes
  include WithFolder
  include WithCustomField

  update_index('capital_remittance') { self }

  belongs_to :entity
  belongs_to :fund, touch: true
  belongs_to :capital_call
  belongs_to :capital_commitment
  has_one :investor_kyc, through: :capital_commitment
  belongs_to :investor
  has_many :capital_remittance_payments

  scope :paid, -> { where(status: "Paid") }
  scope :pending, -> { where(status: "Pending") }
  scope :verified, -> { where(verified: true) }

  monetize :call_amount_cents, :collected_amount_cents, with_currency: ->(i) { i.fund.currency }
  validates :folio_id, presence: true
  validates_uniqueness_of :folio_id, scope: :capital_call_id

  counter_culture :capital_call, column_name: proc { |r| r.verified ? 'collected_amount_cents' : nil },
                                 delta_column: 'collected_amount_cents',
                                 column_names: {
                                   ["capital_remittances.verified = ?", true] => 'collected_amount_cents'
                                 }

  counter_culture :capital_commitment, column_name: 'call_amount_cents',
                                       delta_column: 'call_amount_cents'

  counter_culture :capital_commitment, column_name: proc { |r| r.verified ? 'collected_amount_cents' : nil },
                                       delta_column: 'collected_amount_cents',
                                       column_names: {
                                         ["capital_remittances.verified = ?", true] => 'collected_amount_cents'
                                       }

  counter_culture :fund, column_name: proc { |r| r.verified ? 'collected_amount_cents' : nil },
                         delta_column: 'collected_amount_cents',
                         column_names: {
                           ["capital_remittances.verified = ?", true] => 'collected_amount_cents'
                         }

  before_save :set_status
  before_create :set_call_amount
  def set_call_amount
    self.call_amount_cents = calc_call_amount_cents
    set_status
  end

  def calc_call_amount_cents
    capital_call.percentage_called * capital_commitment.committed_amount_cents / 100.0
  end

  def send_notification
    CapitalRemittancesMailer.with(id:).send_notification.deliver_later if capital_call.approved && !capital_call.manual_generation
  end

  before_save :set_investor_name
  def set_investor_name
    self.investor_name = investor.investor_name
  end

  def folder_path
    "#{capital_call.folder_path}/Remittances/#{investor.investor_name.delete('/')}-#{folio_id.delete('/')}"
  end

  def set_status
    self.status = if (call_amount_cents - collected_amount_cents).abs < 100
                    "Paid"
                  else
                    "Pending"
                  end
  end

  def due_amount
    call_amount - collected_amount
  end

  def to_s
    if status == "Paid"
      "#{investor_name}: #{collected_amount} : #{status}"
    else
      "#{investor_name}: #{due_amount} : #{status}"
    end
  end
end
