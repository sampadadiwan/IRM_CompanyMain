class AggregatePortfolioInvestment < ApplicationRecord
  # Indexing for Elasticsearch updates when this record is saved
  update_index('aggregate_portfolio_investment') { self if index_record?(AggregatePortfolioInvestmentIndex) }

  # Include shared behaviors for snapshots, folders, tracking, investor views, etc.
  include WithSnapshot
  include WithFolder
  include Trackable.new
  include ForInvestor
  include WithCustomField
  include WithDocQuestions

  # Adds dynamic search capabilities for monetary fields
  include RansackerAmounts.new(fields: %w[sold_amount bought_amount fmv avg_cost])

  # Associations
  belongs_to :entity, touch: true
  belongs_to :fund, -> { with_snapshots }
  belongs_to :portfolio_company, class_name: "Investor"
  belongs_to :investment_instrument

  has_many :portfolio_cashflows, dependent: :destroy
  has_many :portfolio_investments, dependent: :destroy
  has_many :ci_track_records, as: :owner, dependent: :destroy
  has_many :ci_widgets, as: :owner, dependent: :destroy

  monetize :tracking_bought_amount_cents, :tracking_sold_amount_cents, :tracking_fmv_cents,
           with_currency: ->(i) { i.fund.tracking_currency.presence || i.fund.currency }

  # Define monetized fields using fund's currency
  monetize :unrealized_gain_cents, :gain_cents, :bought_amount_cents, :net_bought_amount_cents,
           :sold_amount_cents, :transfer_amount_cents, :avg_cost_cents, :cost_of_sold_cents,
           :fmv_cents, :cost_of_remaining_cents, :portfolio_income_cents, :ex_expenses_amount_cents,
           with_currency: ->(i) { i.fund.currency }

  # Validations for length restrictions
  validates :portfolio_company_name, length: { maximum: 100 }
  validates :investment_domicile, length: { maximum: 10 }

  STANDARD_COLUMNS = {
    "Portfolio Company" => "portfolio_company_name",
    "Instrument" => "investment_instrument_name",
    "Current Quantity" => "quantity",
    "Net Bought Amount" => "bought_amount",
    "Sold Amount" => "sold_amount",
    "Fmv" => "fmv",
    "Unrealized Gain" => "unrealized_gain",
    "Realized Gain" => "gain",
    "Avg Cost / Share" => "avg_cost"
  }.freeze

  STANDARD_COLUMNS_WITH_FUND = { "Fund Name" => "fund_name" }.merge(STANDARD_COLUMNS).freeze
  INVESTOR_TAB_STANDARD_COLUMNS = STANDARD_COLUMNS_WITH_FUND.except("Portfolio Company").freeze

  # Callbacks
  before_create :update_name
  before_save :compute_avg_cost, if: -> { bought_quantity.positive? }

  # Set name based on portfolio company if not already set
  def update_name
    self.portfolio_company_name ||= portfolio_company.investor_name
  end

  # Construct a folder path used for storing files related to this investment
  def folder_path
    "/AggregatePortfolioInvestment/#{portfolio_company_name.delete('/')}_#{id_or_random_int}"
  end

  # Basic string representation
  def to_s
    "#{portfolio_company_name}  #{investment_instrument}"
  end

  # Compute average cost if quantity exists
  def compute_avg_cost
    self.avg_cost_cents = bought_amount_cents / bought_quantity
  end

  # Returns a duplicate of this object as of a specified end_date
  # Used extensively in historical accounting and allocation engines
  def as_of(end_date)
    api = dup

    # Fetch PIs before the end_date and calculate their state as of that date
    pis = portfolio_investments.before(end_date).map { |pi| pi.as_of(end_date) }
    api.portfolio_investments = pis

    # Partition into buys and sells for financial calculation
    buys, sells = pis.partition { |pi| pi.quantity.positive? }

    api.bought_quantity = buys.sum(&:quantity)
    api.bought_amount_cents = buys.sum(&:amount_cents)
    api.sold_quantity = sells.sum(&:quantity)
    api.sold_amount_cents = sells.sum(&:amount_cents)

    api.avg_cost_cents = api.bought_amount_cents / api.bought_quantity if api.bought_quantity.positive?
    api.fmv_cents = fmv_on_date(end_date)

    # Compute quantity transfers through stock conversions
    api.transfer_quantity = fund.stock_conversions.where(from_portfolio_investment_id: pis.map(&:id), conversion_date: ..end_date).sum(:from_quantity)
    api.transfer_amount_cents = buys.sum(&:transfer_amount_cents)
    api.quantity = pis.sum(&:quantity) - api.transfer_quantity

    # Realized and unrealized gain calculations
    api.cost_of_sold_cents = sells.sum(&:cost_of_sold_cents)
    api.cost_of_remaining_cents = api.bought_amount_cents + api.cost_of_sold_cents + api.transfer_amount_cents
    api.unrealized_gain_cents = api.fmv_cents - api.cost_of_remaining_cents
    api.gain_cents = api.sold_amount_cents + api.cost_of_sold_cents

    # Calculate net bought amount
    net_bought_quantity = net_quantity_on(end_date, only_buys: true)
    api.net_bought_amount_cents = net_bought_quantity * api.avg_cost_cents

    # Base currency conversions
    api.instrument_currency_fmv_cents = buys.sum(&:instrument_currency_fmv_cents)
    api.instrument_currency_cost_of_remaining_cents = buys.sum(&:instrument_currency_cost_of_remaining_cents)
    api.instrument_currency_unrealized_gain_cents = buys.sum(&:instrument_currency_unrealized_gain_cents)
    api.portfolio_income_cents = portfolio_cashflows.where(payment_date: ..end_date).sum(:amount_cents)
    api.freeze
  end

  # Allocate sold amount proportionally to capital commitment’s ICP
  def sold_amount_allocation(commitment, _end_date)
    portfolio_investments.sum do |pi|
      next 0 unless pi.sell?

      ae = commitment.account_entries.where(name: "Investable Capital Percentage", reporting_date: ..pi.investment_date).order(:reporting_date).last
      pct = ae.amount_cents / 10_000.0
      pi.amount_cents * pct
    end
  end

  # Allocate average cost of sold units to the capital commitment
  def avg_cost_of_sold_allocation(commitment, _end_date)
    portfolio_investments.sum do |pi|
      next 0 unless pi.sell?

      ae = commitment.account_entries.where(name: "Investable Capital Percentage", reporting_date: ..pi.investment_date).order(:reporting_date).last
      pct = ae.amount_cents / 10_000.0
      avg_cost_cents * pi.quantity * pct
    end
  end

  # Perform a stock split on all related portfolio investments
  def split(ratio)
    portfolio_investments.each do |pi|
      logger.info("Stock split #{ratio} for #{pi}")
      pi.split(ratio)
    end
  end

  # Adds ransack support for additional fields
  include RansackerAmounts.new(fields: %w[avg_cost bought_amount sold_amount fmv cost_of_remaining cost_of_sold net_bought_amount transfer_amount unrealized_gain])

  def self.ransackable_attributes(_auth_object = nil)
    %w[avg_cost bought_amount bought_quantity cost_of_remaining cost_of_sold fmv net_bought_amount portfolio_company_name quantity sold_amount sold_quantity transfer_amount transfer_quantity unrealized_gain updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[fund investment_instrument portfolio_company]
  end

  # Reserved for future use
  def avg_cost_on(date); end

  # Calculates net quantity as of a given date
  # Optionally restricts to only buy transactions
  def net_quantity_on(end_date, only_buys: false)
    buys = portfolio_investments.buys.before(end_date)
    buy_qty = buys.sum(:quantity)
    return 0 if buy_qty.zero?

    # Adjust for stock conversions before the given date
    converted_qty = fund.stock_conversions.where(from_portfolio_investment_id: buys.pluck(:id), conversion_date: ..end_date).sum(:from_quantity)

    sells = portfolio_investments.sells.where(investment_date: ..end_date).sum(:quantity)

    only_buys ? buy_qty - converted_qty : buy_qty + sells - converted_qty
  end

  # Calculates FMV as of a given date based on the latest valuation
  def fmv_on_date(end_date)
    qty = net_quantity_on(end_date)
    return 0 if qty.zero?

    val = Valuation.where(owner_id: portfolio_company_id, owner_type: "Investor", investment_instrument: investment_instrument, valuation_date: ..end_date).order(:valuation_date).last
    raise "No valuation found for #{portfolio_company.investor_name}, #{investment_instrument.name} prior to #{end_date}" unless val

    qty * val.per_share_value_in(fund.currency, end_date)
  end

  # Calculates FMV in base currency (raw cents)
  def instrument_currency_fmv_on_date(end_date)
    qty = net_quantity_on(end_date)
    return 0 if qty.zero?

    val = Valuation.where(owner_id: portfolio_company_id, owner_type: "Investor", investment_instrument: investment_instrument, valuation_date: ..end_date).order(:valuation_date).last
    raise "No valuation found for #{portfolio_company.investor_name}, #{investment_instrument.name} prior to #{end_date}" unless val

    qty * val.per_share_value_cents
  end

  # Sums a specific custom field (from JSON) across investments up to a given date
  def sum_custom_field(cf_name, end_date)
    portfolio_investments.where(investment_date: ..end_date).sum { |pi| (pi.json_fields[cf_name] || 0).to_d }
  end
end
