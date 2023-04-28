class PortfolioInvestment < ApplicationRecord
  include WithCustomField
  include WithFolder

  belongs_to :entity
  belongs_to :fund
  # This is only for co invest
  belongs_to :capital_commitment, optional: true
  belongs_to :aggregate_portfolio_investment
  belongs_to :portfolio_company, class_name: "Investor"
  has_many :portfolio_attributions, foreign_key: :sold_pi_id, dependent: :destroy
  has_many :buys_portfolio_attributions, class_name: "PortfolioAttribution", foreign_key: :bought_pi_id, dependent: :destroy

  validates :investment_date, :quantity, :amount_cents, :investment_type, presence: true
  monetize :amount_cents, :cost_cents, :fmv_cents, :gain_cents, :cost_of_sold_cents, with_currency: ->(i) { i.fund.currency }

  counter_culture :aggregate_portfolio_investment, column_name: 'quantity', delta_column: 'quantity'
  counter_culture :aggregate_portfolio_investment, column_name: 'fmv_cents', delta_column: 'fmv_cents'

  enum :commitment_type, { Pool: "Pool", CoInvest: "CoInvest" }
  scope :pool, -> { where(commitment_type: 'Pool') }
  scope :co_invest, -> { where(commitment_type: 'CoInvest') }

  validates :capital_commitment_id, presence: true, if: proc { |p| p.commitment_type == "CoInvest" }

  validate :sell_quantity_allowed

  SECTORS = ENV["SECTORS"].split(",").sort
  CATEGORIES = JSON.parse(ENV.fetch("PORTFOLIO_CATEGORIES", nil))

  def sell_quantity_allowed
    if sell? && new_record?

      buys = fund.portfolio_investments.allocatable_buys(portfolio_company_id, investment_type)
      buys = buys.where(capital_commitment_id:) if self.CoInvest?
      buys = buys.pool if self.Pool?

      total_net_quantity = buys.sum(:net_quantity)

      if quantity.abs > total_net_quantity
        errors.add(:quantity,
                   "Sell quantity is greater than net position #{total_net_quantity}")
      end
    end
  end

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

  before_validation :setup_aggregate

  scope :buys, -> { where("portfolio_investments.quantity > 0") }
  scope :allocatable_buys, lambda { |portfolio_company_id, investment_type|
    where("portfolio_company_id=? and investment_type = ? and portfolio_investments.quantity > 0 and net_quantity > 0", portfolio_company_id, investment_type)
  }
  scope :sells, -> { where("portfolio_investments.quantity < 0") }

  def setup_aggregate
    self.aggregate_portfolio_investment = AggregatePortfolioInvestment.find_or_initialize_by(fund_id:, portfolio_company_id:, entity:, investment_type:, commitment_type:) if aggregate_portfolio_investment_id.blank?
  end

  before_create :update_name
  def update_name
    self.portfolio_company_name ||= portfolio_company.investor_name
  end

  before_save :compute_fmv
  def compute_fmv
    last_valuation = portfolio_company.valuations.where(instrument_type: investment_type).order(valuation_date: :desc).first
    self.fmv_cents = last_valuation ? quantity * last_valuation.per_share_value_cents : 0
    # For buys setup net_quantity, note sold_quantity is -ive
    self.net_quantity = quantity + sold_quantity if buy?
    self.gain_cents = fmv_cents.abs - cost_of_sold_cents if sell?
  end

  after_commit :compute_avg_cost
  def compute_avg_cost
    aggregate_portfolio_investment.reload
    # save will recomute the avg costs
    aggregate_portfolio_investment.save
  end

  after_create_commit -> { PortfolioInvestmentJob.perform_later(id) }
  # Called from PortfolioInvestmentJob
  # This method is used to setup which sells are linked to which buys for purpose of attribution
  def setup_attribution
    if sell?
      # Sell quantity is negative
      allocatable_quantity = quantity.abs
      # It's a sell
      buys = aggregate_portfolio_investment.portfolio_investments.allocatable_buys(portfolio_company_id, investment_type)
      buys = buys.where(capital_commitment_id:) if self.CoInvest?
      buys = buys.pool if self.Pool?

      buys.order(investment_date: :asc).each do |buy|
        Rails.logger.debug { "processing buy #{buy.to_json}" }
        attribution_quantity = [buy.net_quantity, allocatable_quantity].min
        # Create the portfolio attribution
        PortfolioAttribution.create!(entity_id:, fund_id:, bought_pi: buy,
                                     sold_pi: self, quantity: -attribution_quantity)
        # This triggers the computation of net_quantity
        buy.reload.save

        # Update if we have more to allocate
        allocatable_quantity -= attribution_quantity

        # Check if we are done
        break if allocatable_quantity.zero?
      end
    end
  end

  def cost_cents
    quantity.positive? ? (amount_cents / quantity).abs : 0
  end

  def to_s
    "#{portfolio_company_name} #{category} #{buy? ? 'Buy' : 'Sell'} #{quantity}"
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

  ##########################################################
  ############# Computations for Fund Ratios  ##############
  ##########################################################

  def self.total_investment_costs_cents(model, end_date)
    model.portfolio_investments.buys.where(investment_date: ..end_date).sum(:amount_cents)
  end

  def self.fmv_cents(model, end_date)
    total_fmv_end_date = 0
    model.portfolio_investments.pool.buys.where(investment_date: ..end_date).each do |pi|
      # Find the valuation just prior to the end_date
      valuation = pi.portfolio_company.valuations.where(instrument_type: pi.investment_type, valuation_date: ..end_date).order(valuation_date: :asc).last
      total_fmv_end_date += pi.quantity * valuation.per_share_value_cents
    end
    total_fmv_end_date
  end

  def self.avg_cost_cents(model, end_date)
    total_amount_cents = model.portfolio_investments.pool.buys.where(investment_date: ..end_date).sum(:amount_cents)
    total_buy_quantity = model.portfolio_investments.pool.buys.where(investment_date: ..end_date).sum(:quantity)
    total_buy_quantity.positive? ? total_amount_cents / total_buy_quantity : 0
  end

  def self.cost_of_sold_cents_for(model, end_date)
    model.portfolio_investments.pool.sells.where(investment_date: ..end_date).sum(:cost_of_sold_cents)
  end

  def self.total_investment_sold_cents(model, end_date)
    model.portfolio_investments.pool.sells.where(investment_date: ..end_date).sum(:amount_cents)
  end
end
