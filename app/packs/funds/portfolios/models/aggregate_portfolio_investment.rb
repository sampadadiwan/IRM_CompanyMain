class AggregatePortfolioInvestment < AggregatePortfolioInvestmentBase
  update_index('aggregate_portfolio_investment') { self if index_record?(AggregatePortfolioInvestmentIndex) }
  # This has all the utility methods required for snashots
  include WithSnapshot
  include WithFolder
  include Trackable.new

  belongs_to :entity, touch: true
  belongs_to :fund, -> { with_snapshots }
  has_many :portfolio_cashflows, dependent: :destroy
  has_many :portfolio_investments, dependent: :destroy

  has_many :ci_track_records, as: :owner, dependent: :destroy
  has_many :ci_widgets, as: :owner, dependent: :destroy

  validates :portfolio_company_name, length: { maximum: 100 }
  validates :investment_domicile, length: { maximum: 10 }

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
  def as_of(end_date)
    api = dup
    # Get the PIs as of the end_date
    pis_before_end_date = portfolio_investments.before(end_date)

    api.portfolio_investments = pis_before_end_date
    api.quantity = pis_before_end_date.sum(:quantity)

    api.bought_quantity = pis_before_end_date.buys.sum(:quantity)
    api.bought_amount_cents = pis_before_end_date.buys.sum(:amount_cents)

    api.sold_quantity = pis_before_end_date.sells.sum(:quantity)
    api.sold_amount_cents = pis_before_end_date.sells.sum(:amount_cents)

    net_quantity_on(end_date)
    api.avg_cost_cents = api.bought_amount_cents / api.bought_quantity if api.bought_quantity.positive?

    api.fmv_cents = fmv_on_date(end_date)

    # Get the StockConversions where the from_portfolio_investment_id is in pis_before_end_date
    transfer_quantity = fund.stock_conversions.where(from_portfolio_investment_id: pis_before_end_date.pluck(:id), conversion_date: ..end_date).sum(:from_quantity)
    api.transfer_quantity = transfer_quantity

    api.cost_of_sold_cents = pis_before_end_date.sells.sum(:cost_of_sold_cents)
    # Note cost_of_sold_cents is -ive, so we need to add it to the bought_amount_cents
    api.cost_of_remaining_cents = api.bought_amount_cents + api.cost_of_sold_cents
    api.unrealized_gain_cents = api.fmv_cents - api.cost_of_remaining_cents
    api.gain_cents = api.sold_amount_cents - api.cost_of_sold_cents
    net_bought_quantity = net_quantity_on(end_date, only_buys: true)
    api.net_bought_amount_cents = net_bought_quantity * api.avg_cost_cents

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

  def avg_cost_on(date); end

  def net_quantity_on(end_date, only_buys: false)
    # Buys before the end_date
    buy_portfolio_investments = portfolio_investments.buys.before(end_date)
    return 0 if buy_portfolio_investments.blank?

    buy_quantity = buy_portfolio_investments.sum(:quantity)

    # Conversions can happen in the future, but the investment_date of the converted PI is set to the investment_date of the PI from which it was converted (See StockConversion)
    # If the conversion of any of the buys has happened before the end_date, then we need to subtract the converted quantity from the buy_quantity as it has already been converted.
    from_conversion_quantity = fund.stock_conversions.where(from_portfolio_investment_id: buy_portfolio_investments.pluck(:id), conversion_date: ..end_date).sum(:from_quantity)

    conversion_quantity = from_conversion_quantity

    # Sells before the end date
    sell_portfolio_investments = portfolio_investments.sells.where(investment_date: ..end_date)
    sell_quantity = sell_portfolio_investments.sum(:quantity)
    net_quantity = if only_buys
                     # This is net bought quantity
                     buy_quantity - conversion_quantity
                   else
                     # This is net quantity
                     buy_quantity + sell_quantity - conversion_quantity
                   end

    Rails.logger.debug { "Net Quantity: #{net_quantity}, Buy Quantity: #{buy_quantity}, Sell Quantity: #{sell_quantity}, Conversion Quantity: #{conversion_quantity}, API: #{id}" }

    net_quantity
  end

  def fmv_on_date(end_date)
    net_quantity = net_quantity_on(end_date)
    return 0 if net_quantity.zero?

    # Get the valuation for this portfolio_company before the end_date
    valuation = Valuation.where(owner_id: portfolio_company_id, owner_type: "Investor", investment_instrument: investment_instrument, valuation_date: ..end_date).order(valuation_date: :asc).last

    # We cannot proceed without a valid valuation
    raise "No valuation found for #{Investor.find(portfolio_company_id).investor_name}, #{investment_instrument.name} prior to date #{end_date}" unless valuation

    # Get the fmv for this portfolio_company on the end_date
    net_quantity * valuation.per_share_value_in(fund.currency, end_date)
  end

  # This method is used in some allocations formulas, do NOT delete this, as its not directly referenced by the codebase
  def sum_custom_field(cf_name, end_date)
    portfolio_investments.where(investment_date: ..end_date).sum { |pi| (pi.json_fields[cf_name] || 0).to_d }
  end
end
