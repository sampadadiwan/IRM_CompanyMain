class CapitalDistribution < ApplicationRecord
  include WithCustomField
  include Trackable
  include ActivityTrackable
  include WithFolder
  tracked owner: proc { |_controller, model| model.fund }, entity_id: proc { |_controller, model| model.entity_id }

  include ForInvestor

  enum :distribution_on, ["Commitment Percentage", "Investable Capital Percentage"]

  belongs_to :fund, touch: true
  belongs_to :entity
  belongs_to :approved_by_user, class_name: "User", optional: true

  enum :commitment_type, { Pool: "Pool", CoInvest: "CoInvest" }
  scope :pool, -> { where(commitment_type: 'Pool') }
  scope :co_invest, -> { where(commitment_type: 'CoInvest') }
  # This is only for co_invest
  belongs_to :capital_commitment, optional: true

  has_many :capital_distribution_payments, dependent: :destroy, inverse_of: :capital_distribution
  # Stores the prices for unit types for this call
  serialize :unit_prices, type: Hash

  monetize :net_amount_cents, :reinvestment_cents, :gross_amount_cents, :distribution_amount_cents, :cost_of_investment_cents, with_currency: ->(i) { i.fund.currency }

  validates :gross_amount_cents, numericality: { greater_than: 0 }

  validates_uniqueness_of :title, scope: :fund_id
  validates :title, presence: true
  validates :title, length: { maximum: 255 }

  validates :commitment_type, length: { maximum: 10 }
  validates :distribution_date, presence: true
  validates :capital_commitment, presence: true, if: proc { |cd| cd.CoInvest? }

  before_save :compute_net_amount
  def compute_net_amount
    self.net_amount_cents = gross_amount_cents - reinvestment_cents
  end

  after_create_commit :generate_distribution_payments, unless: :destroyed?

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

  def folder_path
    "#{fund.folder_path}/Capital Distributions/#{title.delete('/')}"
  end

  def distribution_percentage(capital_commitment)
    if self.Pool?
      # This is for the pool
      case distribution_on
      when "Commitment Percentage"
        # Commitment Percentage
        capital_commitment.percentage
      when "Investable Capital Percentage"
        # Investable Capital Percentage
        icp_entries = capital_commitment.account_entries.where(name: "Investable Capital Percentage", reporting_date: ..distribution_date)
        icp_entries.order(reporting_date: :asc).last.amount_cents / 100.0
      else
        raise "Unknown distribution_on for CD #{id}"
      end
    elsif self.CoInvest?
      # For CoInvest we will make 100% of the distributed amount as payment to the specific co_invest
      100
    end
  end

  def fund_units
    FundUnit.where(fund_id:, owner_type: "CapitalDistributionPayment", owner_id: capital_distribution_payment_ids)
  end
end
