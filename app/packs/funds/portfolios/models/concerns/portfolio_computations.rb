module PortfolioComputations
  extend ActiveSupport::Concern

  included do
    ##########################################################
    ######### Fund-Level Aggregation Methods (Class) #########
    ##########################################################

    # Total cost of current holdings (buys not sold/transferred)
    def self.total_investment_costs_cents(model, end_date)
      model.portfolio_investments.buys.where(investment_date: ..end_date).sum(:cost_of_remaining_cents)
    end

    # Average cost per share across all buys until end_date
    def self.avg_cost_cents(model, end_date)
      buys = model.portfolio_investments.buys.where(investment_date: ..end_date)
      total_amount = buys.sum(:amount_cents)
      total_quantity = buys.sum(:quantity)
      total_quantity.positive? ? total_amount / total_quantity : 0
    end

    # Total cost of investments that have been sold
    def self.cost_of_sold_cents_for(model, end_date)
      model.portfolio_investments.sells.where(investment_date: ..end_date).sum(:cost_of_sold_cents)
    end

    # Total sell value (not gain) for all sales until end_date
    def self.total_investment_sold_cents(model, end_date)
      model.portfolio_investments.sells.where(investment_date: ..end_date).sum(:amount_cents)
    end
  end

  # Run all investment-level computations for current date
  def compute_all_numbers
    buy? ? compute_buy_metrics(Time.zone.today) : compute_sell_metrics
  end

  # Run all investment-level computations for a past date
  def compute_all_numbers_on(end_date)
    buy? ? compute_buy_metrics(end_date) : compute_sell_metrics
    freeze
  end

  ##########################################################
  ############## Core Computation Helpers ##################
  ##########################################################

  # Compute metrics for a buy transaction
  def compute_buy_metrics(date)
    # Determine how much was sold/transferred before given date
    set_buy_quantities(date)

    # Cost-based fields in fund currency
    self.net_amount_cents = net_quantity * cost_cents
    self.net_bought_amount_cents = net_bought_quantity * cost_cents
    self.cost_of_remaining_cents = net_quantity * cost_cents

    # Fair Market Value (FMV) and gains in fund currency
    self.fmv_cents = compute_fmv_cents_on(date)
    self.unrealized_gain_cents = fmv_cents - cost_of_remaining_cents

    # FMV and gains in instrument currency
    self.instrument_currency_fmv_cents = compute_instrument_currency_fmv_cents_on(date)
    self.instrument_currency_cost_of_remaining_cents = net_quantity * base_cost_cents
    self.instrument_currency_unrealized_gain_cents = instrument_currency_fmv_cents - instrument_currency_cost_of_remaining_cents
  end

  # Compute metrics for a sell transaction
  def compute_sell_metrics
    # Set trivial zero or fixed fields
    self.sold_quantity                = 0
    self.transfer_quantity            = 0
    self.net_quantity                 = quantity
    self.net_bought_quantity          = 0
    self.net_amount_cents             = amount_cents
    self.net_bought_amount_cents      = 0
    self.cost_of_remaining_cents      = 0
    self.gain_cents                   = amount_cents.abs + cost_of_sold_cents

    # No FMV for sell positions
    self.fmv_cents                    = 0
    self.unrealized_gain_cents = 0
    self.instrument_currency_fmv_cents = 0
    self.instrument_currency_cost_of_remaining_cents = 0
    self.instrument_currency_unrealized_gain_cents = 0
  end

  # Sets sold and transferred quantities before a given date
  def set_buy_quantities(date)
    self.sold_quantity = buys_portfolio_attributions.where(investment_date: ..date).sum(:quantity)
    self.transfer_quantity = stock_conversions.where(conversion_date: ..date).sum(:from_quantity)

    self.net_quantity = quantity + sold_quantity - transfer_quantity
    self.net_bought_quantity = quantity - transfer_quantity
  end

  ##########################################################
  ######### FMV and Quantity Computations ##################
  ##########################################################

  # Compute FMV based on latest valuation (in fund currency)
  def compute_fmv
    self.fmv_cents = buy? ? compute_fmv_cents_on(Time.zone.today) : 0
  end

  # FMV = latest price * quantity held (in fund currency)
  def compute_fmv_cents_on(date)
    valuation = latest_valuation_on(date)
    quantity_to_use = date == Time.zone.today ? net_quantity : net_quantity_on(date)

    valuation ? quantity_to_use * valuation.per_share_value_in(fund.currency, date) : 0
  end

  # FMV = latest price * quantity held (in base/instrument currency)
  def compute_instrument_currency_fmv_cents_on(date)
    valuation = latest_valuation_on(date)
    quantity_to_use = date == Time.zone.today ? net_quantity : net_quantity_on(date)

    valuation ? quantity_to_use * valuation.per_share_value_cents : 0
  end

  # Fetches the latest valuation on or before a date
  def latest_valuation_on(date)
    valuations.where(investment_instrument_id: investment_instrument_id, valuation_date: ..date)
              .order(valuation_date: :desc)
              .first
  end

  # Calculates net quantity as of a given date
  def net_quantity_on(date)
    # Quantity of this investment that has been sold
    sold_quantity_on = buys_portfolio_attributions
                       .joins(:sold_pi)
                       .merge(PortfolioInvestment.before(date))
                       .sum(:quantity)

    # Quantity that has been converted into another investment
    conversion_quantity = fund.stock_conversions
                              .where(from_portfolio_investment_id: id, conversion_date: ..date)
                              .sum(:from_quantity)

    quantity + sold_quantity_on - conversion_quantity
  end

  # Per-share price in cents for this transaction
  def price_per_share_cents
    amount_cents / quantity.abs
  end

  ##########################################################
  ####### Allocation of Realized Gain to Commitments #######
  ##########################################################

  # Allocate realized gain proportionally based on account entry value on date of original buy
  def allocation_of_realized_gain_cents(end_date, account_entry_name, capital_commitment)
    calculate_realized_gain(
      end_date: end_date,
      account_entry_name: account_entry_name,
      capital_commitment: capital_commitment
    ) { |pa| pa.bought_pi.investment_date }
  end

  # Same as above, but based on custom `proforma_date` in JSON field (Pravega-specific)
  def allocation_of_realized_gain_cents_proforma(end_date, account_entry_name, capital_commitment)
    calculate_realized_gain(
      end_date: end_date,
      account_entry_name: account_entry_name,
      capital_commitment: capital_commitment,
      proforma: true
    ) { |pa| pa.bought_pi.custom_fields.proforma_date }
  end

  # Shared helper to compute gain allocations, customizable by date field
  def calculate_realized_gain(end_date:, account_entry_name:, capital_commitment:, proforma: false)
    realized_gain = 0

    # Choose attribution scope based on mode
    scope = if proforma
              portfolio_attributions
                .joins(:bought_pi)
                .where("portfolio_investments.json_fields->'$.proforma_date' <= ?", end_date)
            else
              portfolio_attributions
                .joins(:bought_pi)
                .where(portfolio_investments: { investment_date: ..end_date })
            end

    scope.each do |pa|
      reporting_date = yield(pa)

      ae = capital_commitment.account_entries
                             .where(name: account_entry_name, reporting_date: ..reporting_date)
                             .order(reporting_date: :desc)
                             .first

      Rails.logger.debug { "pa.id = #{pa.id} gain cents = #{pa.gain.cents} percentage = #{ae.amount_cents / 100}" }

      realized_gain += pa.gain.cents * ae.amount_cents / 100
    end

    realized_gain
  end

  ##########################################################
  ######### Validation for Sell Quantity ###################
  ##########################################################

  # Validates that a sell does not exceed net available quantity
  def sell_quantity_allowed
    return unless sell? && new_record?

    buys = fund.portfolio_investments.allocatable_buys(portfolio_company_id, investment_instrument_id)
    total_net_quantity = buys.sum(:net_quantity)

    errors.add(:quantity, "Sell quantity is greater than net position #{total_net_quantity}") if quantity.abs > total_net_quantity
  end
end
