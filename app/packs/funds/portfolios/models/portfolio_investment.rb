class PortfolioInvestment < ApplicationRecord
  include WithCustomField
  include WithFolder
  include ForInvestor
  include Trackable
  include PortfolioComputations

  attr_accessor :created_by_import

  belongs_to :entity
  belongs_to :fund
  # This is only for co invest
  belongs_to :capital_commitment, optional: true
  belongs_to :aggregate_portfolio_investment
  belongs_to :portfolio_company, class_name: "Investor"
  has_many :portfolio_attributions, foreign_key: :sold_pi_id, dependent: :destroy
  has_many :buys_portfolio_attributions, class_name: "PortfolioAttribution", foreign_key: :bought_pi_id, dependent: :destroy

  validates :investment_date, :quantity, :amount_cents, :category, :sub_category, :sector, presence: true
  monetize :amount_cents, :cost_cents, :fmv_cents, :gain_cents, :cost_of_sold_cents, with_currency: ->(i) { i.fund.currency }

  counter_culture :aggregate_portfolio_investment, column_name: 'quantity', delta_column: 'quantity'
  counter_culture :aggregate_portfolio_investment, column_name: 'fmv_cents', delta_column: 'fmv_cents'

  enum :commitment_type, { Pool: "Pool", CoInvest: "CoInvest" }
  scope :pool, -> { where(commitment_type: 'Pool') }
  scope :co_invest, -> { where(commitment_type: 'CoInvest') }

  validates :capital_commitment_id, presence: true, if: proc { |p| p.commitment_type == "CoInvest" }
  validate :sell_quantity_allowed
  validates :portfolio_company_name, length: { maximum: 100 }
  validates :category, length: { maximum: 15 }
  validates :sub_category, :sector, length: { maximum: 100 }
  validates :investment_domicile, length: { maximum: 10 }
  validates :amount, numericality: { greater_than_or_equal_to: 0 }

  SECTORS = ENV["SECTORS"].split(",").sort
  CATEGORIES = JSON.parse(ENV.fetch("PORTFOLIO_CATEGORIES", nil))

  counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.buy? ? "bought_quantity" : "sold_quantity" }, delta_column: 'quantity', column_names: {
    ["portfolio_investments.quantity > ?", 0] => 'bought_quantity',
    ["portfolio_investments.quantity < ?", 0] => 'sold_quantity'
  }

  # Cost of sold must be computed only from sells
  counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.sell? ? "cost_of_sold_cents" : nil }, delta_column: 'cost_of_sold_cents', column_names: {
    ["portfolio_investments.quantity < ?", 0] => 'cost_of_sold_cents'
  }

  counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.quantity.positive? ? "bought_amount_cents" : "sold_amount_cents" }, delta_column: 'amount_cents', column_names: {
    ["portfolio_investments.quantity > ?", 0] => 'bought_amount_cents',
    ["portfolio_investments.quantity < ?", 0] => 'sold_amount_cents'
  }

  scope :buys, -> { where("portfolio_investments.quantity > 0") }
  scope :allocatable_buys, lambda { |portfolio_company_id, category, _sub_category|
    where("portfolio_company_id=? and category = ? and portfolio_investments.quantity > 0 and net_quantity > 0", portfolio_company_id, category).order(investment_date: :asc)
  }
  scope :sells, -> { where("portfolio_investments.quantity < 0") }

  before_validation :setup_aggregate
  def setup_aggregate
    self.aggregate_portfolio_investment = AggregatePortfolioInvestment.find_or_initialize_by(fund_id:, portfolio_company_id:, entity:, investment_type:, commitment_type:, investment_domicile:) if aggregate_portfolio_investment_id.blank?
  end

  before_create :update_name
  def update_name
    self.portfolio_company_name ||= portfolio_company.investor_name
  end

  before_save :compute_fmv, unless: :destroyed?

  after_create_commit :compute_avg_cost, unless: :destroyed?
  def compute_avg_cost
    aggregate_portfolio_investment.reload
    # save will recomute the avg costs
    aggregate_portfolio_investment.save
  end

  after_create_commit lambda {
    # After we save the PI, we need to create the attributions for sells.
    # When we import the data we create it in the same thread, as we need to ensure the attribution is setup before we move on to the next row. However if the portfolio_investment is created by the user, we can do it in the background.
    # Originally we were doing this in the background, but it was causing issues with the attribution being created in parallel and sometimes in the wrong order.
    if sell?
      created_by_import ? PortfolioInvestmentJob.perform_now(id) : PortfolioInvestmentJob.perform_later(id)
    end
  }

  # Called from PortfolioInvestmentJob
  # This method is used to setup which sells are linked to which buys for purpose of attribution
  def setup_attribution
    AttributionService.new(self).setup_attribution
  end

  def investment_type
    "#{category} : #{sub_category}"
  end

  def cost_cents
    quantity.positive? ? (amount_cents / quantity).abs : 0
  end

  def buy_sell
    buy? ? 'Buy' : 'Sell'
  end

  def to_s
    "#{portfolio_company_name} #{category} : #{sub_category} #{buy_sell} #{investment_date}"
  end

  def folder_path
    "#{portfolio_company.folder_path}/Portfolio Investments"
  end

  def buy?
    quantity.positive?
  end

  def sell?
    quantity.negative?
  end

  def split(stock_split_ratio)
    StockSplitter.new(self).split(stock_split_ratio)
  end
end
