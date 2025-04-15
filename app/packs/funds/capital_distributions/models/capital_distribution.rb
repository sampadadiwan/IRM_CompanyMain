class CapitalDistribution < ApplicationRecord
  include WithCustomField
  include Trackable.new

  include WithFolder
  include RansackerAmounts.new(fields: %w[carry cost_of_investment distribution_amount fee gross_amount income reinvestment])

  include ForInvestor

  FEE_TYPES = ["Fees Part Of Capital", "Other Fees"].freeze
  enum :distribution_on, ["Commitment Percentage", "Investable Capital Percentage", "Upload"]

  belongs_to :fund, touch: true
  belongs_to :entity
  belongs_to :approved_by_user, class_name: "User", optional: true

  has_many :distribution_fees, inverse_of: :capital_distribution, dependent: :destroy
  accepts_nested_attributes_for :distribution_fees, allow_destroy: true

  has_many :capital_distribution_payments, dependent: :destroy, inverse_of: :capital_distribution
  # Stores the prices for unit types for this call
  serialize :unit_prices, type: Hash

  self.ignored_columns += %w[net_amount_cents]
  # cost_of_investment - this is the FV for Redemption
  # distribution_amount - this what has actually been distributed via payments & marked as completed
  # gross_amount - this is the total amount that has to be distributed
  # reinvestment - This is the amount that is reinvested
  # income - This is the income from sale of portfolio that is to be distributed
  monetize :income_cents, :reinvestment_cents, :gross_amount_cents, :distribution_amount_cents, :completed_distribution_amount_cents, :cost_of_investment_cents, :fee_cents, with_currency: ->(i) { i.fund.currency }

  validates_uniqueness_of :title, scope: :fund_id
  validates :title, presence: true
  validates :title, length: { maximum: 255 }

  validates :distribution_date, presence: true

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
    case distribution_on
    when "Commitment Percentage"
      # Commitment Percentage
      capital_commitment.percentage
    when "Investable Capital Percentage"
      # Investable Capital Percentage
      icp_entries = capital_commitment.account_entries.where(name: "Investable Capital Percentage", reporting_date: ..distribution_date)
      per = icp_entries.order(reporting_date: :asc).last
      per.present? ? per.amount_cents / 100.0 : capital_commitment.percentage
    else
      raise "Unknown distribution_on for CD #{id}"
    end
  end

  def fee_account_entry_names
    fund.account_entries.where(entry_type: DistributionFee::TYPES).pluck(:name).uniq << "Other"
  end

  def fund_units
    FundUnit.where(fund_id:, owner_type: "CapitalDistributionPayment", owner_id: capital_distribution_payment_ids)
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[approved carry completed cost_of_investment created_at distribution_amount distribution_date distribution_on fee gross_amount income reinvestment title updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[fund]
  end

  ransacker :distribution_on, formatter: lambda { |value|
    # If user passes something like "Upload", map it to 2
    # If user passes the integer, e.g. "2", then it remains "2"
    # So we handle both cases safely
    distribution_ons[value] || value
  } do |parent|
    parent.table[:distribution_on]
  end

  def distribution_on_upload?
    distribution_on == "Upload"
  end
end
