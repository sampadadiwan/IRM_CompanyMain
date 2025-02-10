class AggregatePortfolioInvestment < ApplicationRecord
  update_index('aggregate_portfolio_investment') { self if index_record?(AggregatePortfolioInvestmentIndex) }

  include ForInvestor
  include WithFolder
  include Trackable.new
  include WithCustomField
  include RansackerAmounts.new(fields: %w[sold_amount bought_amount fmv avg_cost])
  include WithDocQuestions

  belongs_to :entity, touch: true
  belongs_to :fund
  belongs_to :portfolio_company, class_name: "Investor"
  belongs_to :investment_instrument
  has_many :portfolio_cashflows, dependent: :destroy
  has_many :portfolio_investments, dependent: :destroy

  has_many :ci_track_records, as: :owner, dependent: :destroy
  has_many :ci_widgets, as: :owner, dependent: :destroy

  monetize :unrealized_gain_cents, :bought_amount_cents, :net_bought_amount_cents, :sold_amount_cents, :transfer_amount_cents, :avg_cost_cents, :cost_of_sold_cents, :fmv_cents, :cost_of_remaining_cents, :portfolio_income_cents, with_currency: ->(i) { i.fund.currency }

  STANDARD_COLUMN_NAMES = ["Portfolio Company", "Instrument", "Net Bought Amount", "Sold Amount", "Current Quantity", "Fmv", "Avg Cost / Share", " "].freeze
  STANDARD_COLUMN_FIELDS = %w[portfolio_company_name investment_instrument bought_amount sold_amount current_quantity fmv avg_cost dt_actions].freeze

  validates :portfolio_company_name, length: { maximum: 100 }
  validates :investment_domicile, length: { maximum: 10 }

  STANDARD_COLUMNS = {
    "Portfolio Company" => "portfolio_company_name",
    "Instrument" => "investment_instrument_name",
    "Current Quantity" => "quantity",
    "Net Bought Amount" => "bought_amount",
    "Sold Amount" => "sold_amount",
    "Fmv" => "fmv",
    "Avg Cost / Share" => "avg_cost"
  }.freeze

  STANDARD_COLUMNS_WITH_FUND = { "Fund Name" => "fund_name" }.merge(STANDARD_COLUMNS).freeze

  INVESTOR_TAB_STANDARD_COLUMNS = STANDARD_COLUMNS_WITH_FUND.except("Portfolio Company").freeze

  before_create :update_name
  def update_name
    self.portfolio_company_name ||= portfolio_company.investor_name
  end

  def folder_path
    "/AggregatePortfolioInvestment/#{portfolio_company_name.delete('/')}_#{id_or_random_int}"
  end

  def to_s
    "#{portfolio_company_name}  #{investment_instrument}"
  end

  before_save :compute_avg_cost, if: -> { bought_quantity.positive? }
  def compute_avg_cost
    self.avg_cost_cents = bought_amount_cents / bought_quantity if bought_quantity.positive?
  end

  # This is used extensively in the AccountEntryAllocationEngine
  # The AccountEntryAllocationEngine needs the date as of end_date,
  # so this creates an AggregatePortfolioInvestment with data as of the end_date
  def as_of(start_date, end_date)
    api = dup
    pis = portfolio_investments.where(investment_date: ..end_date)
    pis = pis.where(investment_date: start_date..) if start_date

    api.portfolio_investments = pis
    api.quantity = pis.sum(:quantity)
    api.bought_quantity = pis.buys.sum(:quantity)
    api.bought_amount_cents = pis.buys.sum(:amount_cents)
    api.net_bought_amount_cents = pis.buys.sum(:net_bought_amount_cents)

    api.sold_quantity = pis.sells.sum(:quantity)
    api.sold_amount_cents = pis.sells.sum(:amount_cents)
    api.unrealized_gain_cents = pis.sum(:unrealized_gain_cents)

    api.transfer_quantity = pis.sum(:transfer_quantity)

    api.cost_of_sold_cents = pis.sells.sum(:cost_of_sold_cents)
    api.cost_of_remaining_cents = pis.sum(:cost_of_remaining_cents)
    api.compute_avg_cost

    # FMV is complicated, as the latest fmv is stored, so we need to recompute the fmv as of end_date
    valuation = api.portfolio_company.valuations.where(valuation_date: ..end_date, investment_instrument_id:).order(valuation_date: :asc).last
    api.fmv_cents = valuation ? api.quantity * valuation.per_share_value_in(fund.currency, end_date) : 0
    api.freeze
  end

  def sold_amount_allocation(capital_commitment, _end_date)
    total = 0
    portfolio_investments.each do |portfolio_investment|
      # Do not move this check into the query. Sometimes we get as_of API (see method above), then query filtering does not work
      next unless portfolio_investment.sell?

      icp_ae = capital_commitment.account_entries.where(name: "Investable Capital Percentage", reporting_date: ..portfolio_investment.investment_date).order(reporting_date: :asc).last

      percentage = icp_ae.amount_cents / 10_000
      total += portfolio_investment.amount_cents * percentage
    end
    total
  end

  def avg_cost_of_sold_allocation(capital_commitment, _end_date)
    total = 0
    portfolio_investments.each do |portfolio_investment|
      # Do not move this check into the query. Sometimes we get as_of API (see method above), then query filtering does not work
      next unless portfolio_investment.sell?

      icp_ae = capital_commitment.account_entries.where(name: "Investable Capital Percentage", reporting_date: ..portfolio_investment.investment_date).order(reporting_date: :asc).last

      percentage = icp_ae.amount_cents / 10_000
      total += avg_cost_cents * portfolio_investment.quantity * percentage
    end
    total
  end

  # def fifo_cost_of_sold_allocation(capital_commitment, _end_date)
  #   total = 0
  #   portfolio_investments.each do |portfolio_investment|
  #     # Do not move this check into the query. Sometimes we get as_of API (see method above), then query filtering does not work
  #     next unless portfolio_investment.sell?

  #     icp_ae = capital_commitment.account_entries.where(name: "Investable Capital Percentage", reporting_date: ..portfolio_investment.investment_date).order(reporting_date: :asc).last

  #     percentage = icp_ae.amount_cents / 10_000
  #     total += portfolio_investment.cost_of_sold_cents * portfolio_investment.quantity * percentage
  #   end
  #   total
  # end

  # This will trigger a stock split for all portfolio_investments
  def split(stock_split_ratio)
    portfolio_investments.each do |pi|
      logger.info "Stock split #{stock_split_ratio} for #{pi}"
      pi.split(stock_split_ratio)
    end
  end

  include RansackerAmounts.new(fields: %w[avg_cost bought_amount sold_amount fmv cost_of_remaining cost_of_sold net_bought_amount transfer_amount unrealized_gain])
  def self.ransackable_attributes(_auth_object = nil)
    %w[avg_cost bought_amount bought_quantity cost_of_remaining cost_of_sold fmv net_bought_amount portfolio_company_name quantity sold_amount sold_quantity transfer_amount transfer_quantity unrealized_gain updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[fund investment_instrument portfolio_company]
  end
end
