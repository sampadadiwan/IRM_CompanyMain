class CapitalDistributionPayment < ApplicationRecord
  include WithCustomField
  include WithExchangeRate
  include Trackable
  include ActivityTrackable
  include WithFolder

  STANDARD_COLUMN_NAMES = ["Investor", "Folio No", "Amount", "Payment Date", "Completed", " "].freeze
  STANDARD_COLUMN_FIELDS = %w[investor_name folio_id amount payment_date completed dt_actions].freeze

  INVESTOR_COLUMN_NAMES = STANDARD_COLUMN_NAMES - ["Investor"]
  INVESTOR_COLUMN_FIELDS = STANDARD_COLUMN_FIELDS - %w[investor_name]

  tracked owner: proc { |_controller, model| model.fund }, entity_id: proc { |_controller, model| model.entity_id }

  include ForInvestor
  update_index('capital_distribution_payment') { self if index_record? }

  belongs_to :fund, touch: true
  belongs_to :entity
  belongs_to :capital_distribution, touch: true
  belongs_to :investor
  belongs_to :capital_commitment
  has_one :investor_kyc, through: :capital_commitment
  has_noticed_notifications

  # Note that cost_of_investment_cents is Face value for redemption
  monetize :folio_amount_cents, with_currency: ->(i) { i.capital_commitment&.folio_currency || i.fund.currency }
  monetize :amount_cents, :cost_of_investment_cents, with_currency: ->(i) { i.fund.currency }

  validates :folio_id, presence: true
  validates_uniqueness_of :folio_id, scope: :capital_distribution_id

  validates :folio_id, length: { maximum: 20 }
  validates :investor_name, length: { maximum: 255 }

  counter_culture :capital_distribution,
                  column_name: proc { |r| r.completed ? 'distribution_amount_cents' : nil },
                  delta_column: 'amount_cents',
                  column_names: {
                    ["capital_distribution_payments.completed = ?", true] => 'distribution_amount_cents'
                  }

  counter_culture :fund,
                  column_name: proc { |r| r.completed && r.capital_commitment.Pool? ? 'distribution_amount_cents' : nil },
                  delta_column: 'amount_cents',
                  column_names: lambda {
                    {
                      CapitalDistributionPayment.completed.pool => :distribution_amount_cents
                    }
                  }

  counter_culture :fund,
                  column_name: proc { |r| r.completed && r.capital_commitment.CoInvest? ? 'co_invest_distribution_amount_cents' : nil },
                  delta_column: 'amount_cents',
                  column_names: lambda {
                    {
                      CapitalDistributionPayment.completed.co_invest => :co_invest_distribution_amount_cents
                    }
                  }

  counter_culture :capital_commitment,
                  column_name: 'distribution_amount_cents',
                  delta_column: 'amount_cents'

  counter_culture %i[capital_commitment investor_kyc],
                  column_name: 'distribution_amount_cents',
                  delta_column: 'amount_cents'

  scope :has_cost_of_investment, -> { where("cost_of_investment_cents > 0") }
  scope :has_amount, -> { where("amount_cents > 0") }

  scope :completed, -> { where(completed: true) }
  scope :incomplete, -> { where(completed: false) }
  scope :pool, -> { joins(:capital_commitment).where("capital_commitments.commitment_type=?", "Pool") }
  scope :co_invest, -> { joins(:capital_commitment).where("capital_commitments.commitment_type=?", "CoInvest") }

  before_validation :ensure_commitment
  def ensure_commitment
    self.capital_commitment = fund.capital_commitments.where(investor_id:, folio_id:).first
  end

  before_save :set_investor_name
  def set_investor_name
    self.investor_name = investor.investor_name
  end

  before_save :set_amount, if: :amount_cents_changed?
  def set_amount
    # Since the distribution amount is always in the fund currency, we compute te converted folio_amount based on exchange rates.
    self.folio_amount_cents = convert_currency(fund.currency, capital_commitment.folio_currency,
                                               amount_cents, payment_date)
  end

  after_commit :send_notification, if: ->(cdp) { cdp.completed && !cdp.destroyed? }
  def send_notification
    if saved_change_to_completed? && capital_distribution.approved && !capital_distribution.manual_generation
      investor.approved_users.each do |user|
        CapitalDistributionPaymentNotification.with(entity_id:, capital_distribution_payment: self).deliver_later(user)
      end
    end
  end

  after_commit :update_investor_entity
  # rubocop:disable Rails/SkipsModelValidations
  # This is to bust any cached dashboards showing the commitments
  def update_investor_entity
    investor.investor_entity.touch if investor&.investor_entity
  end
  # rubocop:enable Rails/SkipsModelValidations

  def to_s
    if completed
      "#{investor_name}: #{amount} : Completed"
    else
      "#{investor_name}: #{amount} : Pending"
    end
  end

  def folder_path
    "#{capital_distribution.folder_path}/Payments/#{investor.investor_name.delete('/')}-#{folio_id.delete('/')}"
  end

  def management_fees_days(start_date, end_date)
    if capital_distribution.distribution_date <= start_date
      (end_date - start_date).to_i + 1
    elsif capital_distribution.distribution_date <= end_date
      (end_date - capital_distribution.distribution_date).to_i + 1
    else
      0
    end
  end

  def has_amount?
    amount_cents.positive?
  end

  def has_cost_of_investment?
    cost_of_investment_cents.positive?
  end
end
