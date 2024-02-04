class AggregatePortfolioInvestment < ApplicationRecord
  include ForInvestor
  include Trackable.new

  belongs_to :entity
  belongs_to :fund
  belongs_to :portfolio_company, class_name: "Investor"
  has_many :portfolio_investments, dependent: :destroy
  has_many :portfolio_cashflows, dependent: :destroy

  monetize :bought_amount_cents, :sold_amount_cents, :avg_cost_cents, :cost_of_sold_cents, :fmv_cents, :cost_cents, with_currency: ->(i) { i.fund.currency }

  enum :commitment_type, { Pool: "Pool", CoInvest: "CoInvest" }
  scope :pool, -> { where(commitment_type: 'Pool') }
  scope :co_invest, -> { where(commitment_type: 'CoInvest') }

  validates :portfolio_company_name, length: { maximum: 100 }
  validates :investment_type, length: { maximum: 120 }
  validates :commitment_type, length: { maximum: 10 }
  validates :investment_domicile, length: { maximum: 10 }

  before_create :update_name
  def update_name
    self.portfolio_company_name ||= portfolio_company.investor_name
  end

  def to_s
    "#{portfolio_company_name}  #{investment_type}"
  end

  before_save :compute_avg_cost
  def compute_avg_cost
    self.avg_cost_cents = bought_quantity.positive? ? bought_amount_cents / bought_quantity : 0
    self.cost_cents = bought_amount_cents + cost_of_sold_cents
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
    api.sold_quantity = pis.sells.sum(:quantity)
    api.sold_amount_cents = pis.sells.sum(:amount_cents)
    api.compute_avg_cost
    api.cost_of_sold_cents = pis.sells.sum(:cost_of_sold_cents)

    # FMV is complicated, as the latest fmv is stored, so we need to recompute the fmv as of end_date
    category, sub_category = investment_type.split(" : ")
    valuation = api.portfolio_company.valuations.where(valuation_date: ..end_date, category:, sub_category:).order(valuation_date: :asc).last
    api.fmv_cents = valuation ? api.quantity * valuation.per_share_value_cents : 0
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

  def fifo_cost_of_sold_allocation(capital_commitment, _end_date)
    total = 0
    portfolio_investments.each do |portfolio_investment|
      # Do not move this check into the query. Sometimes we get as_of API (see method above), then query filtering does not work
      next unless portfolio_investment.sell?

      icp_ae = capital_commitment.account_entries.where(name: "Investable Capital Percentage", reporting_date: ..portfolio_investment.investment_date).order(reporting_date: :asc).last

      percentage = icp_ae.amount_cents / 10_000
      total += portfolio_investment.cost_of_sold_cents * portfolio_investment.quantity * percentage
    end
    total
  end

  # This will trigger a stock split for all portfolio_investments
  def split(stock_split_ratio)
    portfolio_investments.each do |pi|
      pi.split(stock_split_ratio)
    end
  end

  def category
    investment_type.split(" : ").first
  end

  def sub_category
    investment_type.split(" : ").last
  end
end
