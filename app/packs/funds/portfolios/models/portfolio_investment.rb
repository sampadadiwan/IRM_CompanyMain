class PortfolioInvestment < ApplicationRecord
  ##########################################################
  ###################### INCLUDED MODULES ##################
  ##########################################################

  include WithFolder                   # Handles folder_path logic
  include WithSnapshot                 # Snapshot support (historical views)
  include WithExchangeRate             # Currency conversion and tracking
  include Trackable.new                # Track changes to records
  include PortfolioComputations        # Financial computations
  include Memoized                     # Caching of heavy methods
  include PortfolioInvestmentCounters  # Counter cache logic
  include WithCustomField              # JSON-based custom field support
  include ForInvestor                  # Scopes for investor filtering
  include RansackerAmounts.new(fields: %w[amount cost_of_sold fmv gain])

  ##########################################################
  ####################### ATTRIBUTES #######################
  ##########################################################

  attr_accessor :created_by_import

  ##########################################################
  ###################### ASSOCIATIONS ######################
  ##########################################################

  belongs_to :entity
  belongs_to :portfolio_company, class_name: "Investor"
  belongs_to :investment_instrument
  belongs_to :fund, -> { with_snapshots } # Loads fund snapshot if enabled
  belongs_to :aggregate_portfolio_investment, -> { with_snapshots }

  has_many :valuations, through: :portfolio_company
  has_many :portfolio_attributions, foreign_key: :sold_pi_id, dependent: :destroy
  has_many :buys_portfolio_attributions, class_name: "PortfolioAttribution", foreign_key: :bought_pi_id, dependent: :destroy
  has_many :stock_conversions, foreign_key: :from_portfolio_investment_id, dependent: :destroy

  ##########################################################
  ######################## VALIDATIONS #####################
  ##########################################################

  validates :investment_date, :quantity, :amount_cents, presence: true
  validates :base_amount, :amount_cents, numericality: { greater_than_or_equal_to: 0 }
  validate  :sell_quantity_allowed
  validates :portfolio_company_name, length: { maximum: 100 }
  validates :portfolio_company_name, uniqueness: { scope: %i[investment_date ex_expenses_base_amount_cents quantity investment_instrument_id fund_id entity_id ref_id] }

  ##########################################################
  ######################## CALLBACKS #######################
  ##########################################################

  before_create :update_name

  ##########################################################
  ##################### MONETIZED FIELDS ###################
  ##########################################################

  monetize :ex_expenses_base_amount_cents, :base_amount_cents, :base_cost_cents,
           with_currency: ->(i) { i.investment_instrument&.currency || i.fund.currency }

  monetize :net_bought_amount_cents, :net_amount_cents, :ex_expenses_amount_cents,
           :amount_cents, :cost_cents, :fmv_cents, :gain_cents,
           :unrealized_gain_cents, :cost_of_sold_cents, :cost_of_remaining_cents,
           :transfer_amount_cents,
           with_currency: ->(i) { i.fund.currency }

  ##########################################################
  ########################## SCOPES ########################
  ##########################################################

  scope :buys, -> { where("portfolio_investments.quantity > 0") }

  # Returns buys that are eligible to be matched to sells
  scope :allocatable_buys, lambda { |pc_id, inst_id|
    where("portfolio_company_id = ? AND investment_instrument_id = ? AND quantity > 0 AND net_quantity > 0", pc_id, inst_id)
      .order(investment_date: :asc)
  }

  scope :sells, -> { where("portfolio_investments.quantity < 0") }

  scope :conversions, -> { where.not(conversion_date: nil) }

  # Ensures conversion_date doesn't affect snapshots as_of past date
  scope :before, lambda { |date|
    where(investment_date: ..date)
      .where("conversion_date IS NULL OR conversion_date <= ?", date)
  }

  ##########################################################
  ###################### CONSTANTS #########################
  ##########################################################

  STANDARD_COLUMNS = {
    "Portfolio Company" => "portfolio_company_name",
    "Instrument" => "investment_instrument_name",
    "Investment Date" => "investment_date",
    "Amount" => "amount",
    "Quantity" => "quantity",
    "Cost Per Share" => "cost",
    "FMV" => "fmv",
    "Unrealized Gain" => "unrealized_gain",
    "Realized Gain" => "gain",
    "FIFO Cost" => "cost_of_sold",
    "Notes" => "notes"
  }.freeze

  ##########################################################
  ####################### HELPERS ##########################
  ##########################################################

  def buy?
    quantity.positive?
  end

  def sell?
    quantity.negative?
  end

  def buy_sell
    buy? ? 'Buy' : 'Sell'
  end

  def to_s
    "#{portfolio_company_name} #{investment_instrument} #{buy_sell} #{I18n.l(investment_date)}"
  end

  def folder_path
    "#{portfolio_company.folder_path}/Portfolio Investments"
  end

  def name
    "#{portfolio_company_name} #{investment_instrument.name} #{investment_date}"
  end

  # Returns cost per share in fund currency
  def cost_cents
    quantity.positive? ? (amount_cents / quantity).abs : 0
  end

  # Returns cost per share in instrument's base currency
  def base_cost_cents
    quantity.positive? ? (base_amount_cents / quantity).abs : 0
  end

  ##########################################################
  ################### AGGREGATE SETUP ######################
  ##########################################################

  # Ensures the record is linked to an AggregatePortfolioInvestment.
  # If not linked, creates or updates it with appropriate form_type.
  def setup_aggregate
    if aggregate_portfolio_investment_id.blank?
      self.aggregate_portfolio_investment = AggregatePortfolioInvestment.find_or_initialize_by(
        fund_id:, portfolio_company_id:, entity:, investment_instrument_id:
      )

      aggregate_portfolio_investment.form_type = entity.form_types.where(name: "AggregatePortfolioInvestment").last
      success = aggregate_portfolio_investment.save
      logger.error "Aggregate PI setup failed: #{aggregate_portfolio_investment.errors.full_messages}" unless success
      success
    elsif aggregate_portfolio_investment.form_type_id.blank?
      aggregate_portfolio_investment.form_type = entity.form_types.where(name: "AggregatePortfolioInvestment").last
      aggregate_portfolio_investment.save
    else
      true
    end
  end

  ##########################################################
  ################### AMOUNT COMPUTATION ###################
  ##########################################################

  # Computes final amount_cents and sets base_amount, transfer_amount, etc.
  # Handles currency conversion if needed between base and fund currencies.
  def compute_amount_cents
    # Add any explicitly declared expenses (recorded in base currency)
    self.base_amount_cents = ex_expenses_base_amount_cents + expense_cents

    if fund.currency == investment_instrument.currency || investment_instrument.currency.nil?
      # No conversion needed — same currency
      self.ex_expenses_amount_cents = ex_expenses_base_amount_cents
      self.amount_cents = base_amount_cents
    else
      # Convert both fields to fund currency
      self.ex_expenses_amount_cents = convert_currency(
        investment_instrument.currency, fund.currency, ex_expenses_base_amount_cents, investment_date
      )

      self.amount_cents = convert_currency(
        investment_instrument.currency, fund.currency, base_amount_cents, investment_date
      )

      # Store the actual exchange rate used
      self.exchange_rate = get_exchange_rate(investment_instrument.currency, fund.currency, investment_date)
    end

    # Transfer amount is computed as cost * transferred quantity
    self.transfer_amount_cents = -transfer_quantity * cost_cents
  end

  ##########################################################
  ####################### EXPENSES #########################
  ##########################################################

  # Sums up all form custom fields tagged as 'Expense'
  def expense_cents
    expense_fields = form_custom_fields.where(meta_data: "Expense").pluck(:name)

    # Convert values to cents and sum
    total = expense_fields.filter_map do |name|
      json_fields[name].to_d
    rescue StandardError
      nil
    end.sum * 100

    # Negative if sell, positive if buy
    buy? ? total : -total
  end

  ##########################################################
  ################ SNAPSHOT & TEMPORAL HELPERS #############
  ##########################################################

  # Computes cumulative quantity as of a date across all matching PIs
  def compute_quantity_as_of_date
    self.quantity_as_of_date = aggregate_portfolio_investment
                               .portfolio_investments
                               .where(investment_date: ..investment_date)
                               .sum(:quantity)
  end

  # Returns a copy of the record with values as of the given date
  def as_of(end_date)
    compute_all_numbers_on(end_date)
  end

  ##########################################################
  #################### CALLBACK METHODS ####################
  ##########################################################

  # Fills in portfolio_company_name from associated record
  def update_name
    self.portfolio_company_name ||= portfolio_company.investor_name
  end

  ##########################################################
  ################# AGGREGATE METRIC UPDATE ################
  ##########################################################

  # Forces recomputation of aggregate-level cost metrics
  def compute_avg_cost
    aggregate_portfolio_investment.reload
    aggregate_portfolio_investment.save
  end

  ##########################################################
  #################### ATTRIBUTION SETUP ###################
  ##########################################################

  # Links this investment (sell) to its buys for gain allocation
  def setup_attribution
    AttributionService.new(self).setup_attribution
  end

  ##########################################################
  ################### STOCK SPLITTING ######################
  ##########################################################

  # Applies a stock split (used for backward adjustments)
  def split(stock_split_ratio)
    StockSplitter.new(self).split(stock_split_ratio)
  end

  ##########################################################
  ################## RANSACK SEARCH SUPPORT ################
  ##########################################################

  def self.ransackable_attributes(_auth_object = nil)
    %w[
      amount cost_of_sold created_at fmv folio_id gain investment_date
      net_quantity notes portfolio_company_name quantity sector sold_quantity
      updated_at snapshot_date snapshot
    ].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[fund portfolio_company investment_instrument]
  end
end
