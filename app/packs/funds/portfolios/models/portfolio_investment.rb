# Fields in the PortfolioInvestment Model:
# -----------------------------------------
# investment_date: Date on which the investment was made.
# amount_cents: Amount invested in cents.
# fmv_cents: Fair Market Value (FMV) of the investment in cents.
# cost_cents: Cost of the investment per share in cents.
# sold_quantity: Quantity of shares or units sold from this investment.
# net_quantity: Net quantity after accounting for purchases, sales, and transfers.
# cost_of_sold_cents: Cost of the sold portion of the investment in cents.
# gain_cents: Realized gain from the investment in cents.
# base_amount_cents: Base amount invested in cents before adjustments.
# exchange_rate_id: ID of the exchange rate used for currency conversion (if applicable).
# transfer_quantity: Quantity of shares or units transferred.
# transfer_amount_cents: Amount transferred in cents.
# net_amount_cents: Net amount of the investment after accounting for adjustments in cents.
# net_bought_amount_cents: Net amount of shares or units bought in cents.
# net_bought_quantity: Net quantity of shares or units bought.
# cost_of_remaining_cents: Cost of remaining unsold shares or units in cents.
# unrealized_gain_cents: Unrealized gain from the investment in cents.
# compliant: Boolean indicating if the investment complies with regulations.

class PortfolioInvestment < PortfolioInvestmentBase
  include WithFolder
  # This has all the utility methods required for snashots
  include WithSnapshot
  include WithExchangeRate
  include Trackable.new
  include PortfolioComputations
  include Memoized

  attr_accessor :created_by_import

  belongs_to :fund
  belongs_to :aggregate_portfolio_investment

  has_many :portfolio_attributions, foreign_key: :sold_pi_id, dependent: :destroy
  has_many :buys_portfolio_attributions, class_name: "PortfolioAttribution", foreign_key: :bought_pi_id, dependent: :destroy

  has_many :stock_conversions, foreign_key: :from_portfolio_investment_id, dependent: :destroy

  validates :investment_date, :quantity, :amount_cents, presence: true
  validates :base_amount, :amount_cents, numericality: { greater_than_or_equal_to: 0 }

  # We rollup net quantity to the API quantity, only for buys. This takes care of sells and transfers
  counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.buy? ? "quantity" : nil }, delta_column: 'net_quantity', column_names: {
    ["portfolio_investments.quantity > ?", 0] => 'quantity',
    ["portfolio_investments.quantity < ?", 0] => nil
  }

  counter_culture :aggregate_portfolio_investment, column_name: 'transfer_amount_cents', delta_column: 'transfer_amount_cents'
  counter_culture :aggregate_portfolio_investment, column_name: 'transfer_quantity', delta_column: 'transfer_quantity'

  counter_culture :aggregate_portfolio_investment, column_name: 'cost_of_remaining_cents', delta_column: 'cost_of_remaining_cents'
  counter_culture :aggregate_portfolio_investment, column_name: 'unrealized_gain_cents', delta_column: 'unrealized_gain_cents'
  counter_culture :aggregate_portfolio_investment, column_name: 'gain_cents', delta_column: 'gain_cents'

  counter_culture :aggregate_portfolio_investment, column_name: 'fmv_cents', delta_column: 'fmv_cents'

  validate :sell_quantity_allowed
  validates :portfolio_company_name, length: { maximum: 100 }
  # validates :quantity, numericality: { other_than: 0 }, on: :create

  # For sells, roll up the amount_cents to the aggregate portfolio investment sold_amount_cents
  counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.sell? ? "sold_amount_cents" : nil }, delta_column: 'amount_cents', column_names: {
    ["portfolio_investments.quantity < ?", 0] => 'sold_amount_cents'
  }

  counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.sell? ? "sold_quantity" : nil }, delta_column: 'quantity', column_names: {
    ["portfolio_investments.quantity < ?", 0] => 'sold_quantity'
  }

  # For buys, roll up the net_bought_amount_cents to the aggregate portfolio investment bought_amount_cents
  counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.buy? ? "bought_amount_cents" : nil }, delta_column: 'amount_cents', column_names: {
    ["portfolio_investments.quantity > ?", 0] => 'bought_amount_cents'
  }

  counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.buy? ? "net_bought_amount_cents" : nil }, delta_column: 'net_bought_amount_cents', column_names: {
    ["portfolio_investments.quantity > ?", 0] => 'net_bought_amount_cents'
  }

  counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.buy? ? "bought_quantity" : nil }, delta_column: 'quantity', column_names: {
    ["portfolio_investments.quantity > ?", 0] => 'bought_quantity'
  }

  # This is used to improve the performance of the portfolio computations, in allocations
  memoize :compute_fmv, :compute_fmv_cents_on, :net_quantity_on

  def setup_aggregate
    if aggregate_portfolio_investment_id.blank?
      self.aggregate_portfolio_investment = AggregatePortfolioInvestment.find_or_initialize_by(fund_id:, portfolio_company_id:, entity:, investment_instrument_id:)

      aggregate_portfolio_investment.form_type = entity.form_types.where(name: "AggregatePortfolioInvestment").last
      ret_val = aggregate_portfolio_investment.save

      logger.error "Error in setting up aggregate portfolio investment #{aggregate_portfolio_investment.errors.full_messages}" unless ret_val
      ret_val
    elsif aggregate_portfolio_investment.form_type_id.blank?
      aggregate_portfolio_investment.form_type = entity.form_types.where(name: "AggregatePortfolioInvestment").last
      aggregate_portfolio_investment.save
    else
      true
    end
  end

  # When we buy or sell there are transaction costs, outside of the buy / sell price
  # Its assumed that these costs are recorded in the instrument currency
  def expense_cents
    expense_custom_fields_names = form_custom_fields.where(meta_data: "Expense").pluck(:name)
    # Find the names from the expense_custom_fields_names in json_fields
    # and add up the values after converting to decimal
    expenses_from_cf = expense_custom_fields_names.filter_map { |name| json_fields[name].to_d }.sum * 100
    buy? ? expenses_from_cf : -expenses_from_cf
  end

  def compute_amount_cents
    self.base_amount_cents = ex_expenses_base_amount_cents + expense_cents
    if fund.currency == investment_instrument.currency || investment_instrument.currency.nil?
      # No conversion required
      self.ex_expenses_amount_cents = ex_expenses_base_amount_cents
      self.amount_cents = base_amount_cents
    else
      # Setup the conversion from the base currency to the fund currency
      self.ex_expenses_amount_cents = convert_currency(investment_instrument.currency, fund.currency, ex_expenses_base_amount_cents, investment_date)
      self.amount_cents = convert_currency(investment_instrument.currency, fund.currency, base_amount_cents, investment_date)
      # This sets the exchange rate being used for the conversion
      self.exchange_rate = get_exchange_rate(investment_instrument.currency, fund.currency, investment_date)
    end

    self.transfer_amount_cents = -transfer_quantity * cost_cents
  end

  def compute_quantity_as_of_date
    self.quantity_as_of_date = aggregate_portfolio_investment.portfolio_investments.where(investment_date: ..investment_date).sum(:quantity)
  end

  def as_of(end_date)
    compute_all_numbers_on(end_date)
  end

  before_create :update_name
  def update_name
    self.portfolio_company_name ||= portfolio_company.investor_name
  end

  def compute_avg_cost
    aggregate_portfolio_investment.reload
    # save will recomute the avg costs
    aggregate_portfolio_investment.save
  end

  # Called from PortfolioInvestmentJob
  # This method is used to setup which sells are linked to which buys for purpose of attribution
  def setup_attribution
    AttributionService.new(self).setup_attribution
  end

  def split(stock_split_ratio)
    StockSplitter.new(self).split(stock_split_ratio)
  end
end
