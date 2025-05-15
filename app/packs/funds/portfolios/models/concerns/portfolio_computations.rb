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

  ############################################################################
  ####### Allocation of Gain, Cost Of Sold, Sale Amount to Commitments #######
  ############################################################################

  # Generic method to allocate a specific attribute (e.g., gain, cost_of_sold, sale_amount) in cents
  # Proportionally distributes the attribute value based on the account entry amount as of a specific date
  def allocation_of_attribute_cents(attribute_name, end_date, account_entry_name, capital_commitment, proforma: false)
    allocated_cents_for(
      attribute_name: attribute_name,
      end_date: end_date,
      account_entry_name: account_entry_name,
      capital_commitment: capital_commitment,
      proforma: proforma
    ) do |pa|
      # Determine the correct attribution date based on proforma mode
      proforma ? pa.bought_pi.custom_fields.proforma_date : pa.bought_pi.investment_date
    end
  end

  # --- Specific Aliases for Readability and Backward Compatibility ---

  # Calculates allocation based on custom proforma date and `gain` field
  def allocation_of_realized_gain_cents(end_date, account_entry_name, capital_commitment, proforma: false)
    allocation_of_attribute_cents(:gain, end_date, account_entry_name, capital_commitment, proforma:)
  end

  # Calculates allocation based on actual investment date and `cost_of_sold` field
  def allocation_of_cost_of_sold_cents(end_date, account_entry_name, capital_commitment, proforma: false)
    allocation_of_attribute_cents(:cost_of_sold, end_date, account_entry_name, capital_commitment, proforma:)
  end

  # Calculates allocation based on actual investment date and `sale_amount` field
  def allocation_of_sale_amount_cents(end_date, account_entry_name, capital_commitment, proforma: false)
    allocation_of_attribute_cents(:sale_amount, end_date, account_entry_name, capital_commitment, proforma:)
  end

  # --- Core Method for Attribute Allocation ---
  # account_entry_name: The name of the account entry to match against, such as InvestableCapitalPercentage or ForiegnInvesableCapitalPercentage. This is the basis of allocation
  # attribute_name: The name of the attribute to be allocated, such as gain, cost_of_sold, or sale_amount
  # end_date: The date for which the InvestableCapitalPercentage or ForiegnInvesableCapitalPercentage is retrived from the AccountEntries
  # proforma: Boolean flag to indicate whether to use proforma date or investment date for filtering
  def allocated_cents_for(attribute_name:, end_date:, account_entry_name:, capital_commitment:, proforma:)
    total = 0

    # Step 1: Filter portfolio attributions up to the end_date
    # The date field used depends on whether proforma mode is on
    scope = if proforma
              portfolio_attributions
                .joins(:bought_pi)
                .where("portfolio_investments.json_fields->'$.proforma_date' <= ?", end_date)
            else
              portfolio_attributions
                .joins(:bought_pi)
                .where(portfolio_investments: { investment_date: ..end_date })
            end

    # Step 2: Iterate through each attribution and compute allocation
    scope.each do |pa|
      # Yield gives us either proforma_date or investment_date
      reporting_date = yield(pa)

      # Find the most recent account entry *before or on* the reporting_date
      ae = capital_commitment.account_entries
                             .where(name: account_entry_name, reporting_date: ..reporting_date)
                             .order(reporting_date: :desc)
                             .first

      next unless ae # Skip if no matching account entry

      # Fetch the attribute value (e.g., gain, cost_of_sold) in cents from the attribution
      value_cents = pa.public_send(attribute_name).cents

      # Debug log for troubleshooting and auditing
      Rails.logger.debug do
        "pa.id=#{pa.id}, #{attribute_name}=#{value_cents}, ae.amount_cents=#{ae.amount_cents}"
      end

      # Proportional allocation: attribute value * allocation percentage (represented by ae.amount_cents / 100)
      total += value_cents * ae.amount_cents / 100
    end

    total
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
