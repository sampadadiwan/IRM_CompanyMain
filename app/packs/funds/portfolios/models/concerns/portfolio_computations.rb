module PortfolioComputations
  extend ActiveSupport::Concern
  include Memoized

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

    # Gain split (H9): price effect = local-currency gain × today's rate; currency effect is the rest,
    # so the two always add up to the gain exactly (E32 — Edge case: rounding).
    self.unrealized_price_effect_cents = price_effect_cents(instrument_currency_unrealized_gain_cents, fmv_cents, instrument_currency_fmv_cents, unrealized_gain_cents)
    self.realized_price_effect_cents = 0
  end

  # Currency effect = total gain − price effect (shown on screens and in reports)
  def unrealized_fx_effect_cents
    unrealized_gain_cents.to_d - unrealized_price_effect_cents.to_d
  end

  def realized_fx_effect_cents
    gain_cents.to_d - realized_price_effect_cents.to_d
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

    # E33 — Edge case: realised gain split, using the cost (local) of the lots this sale consumed
    self.unrealized_price_effect_cents = 0
    local_cost_of_sold = portfolio_attributions.includes(:bought_pi).sum { |a| a.quantity.abs * a.bought_pi.base_cost_cents }
    self.realized_price_effect_cents = price_effect_cents(base_amount_cents.abs - local_cost_of_sold, amount_cents.abs, base_amount_cents.abs, gain_cents)
  end

  # Local gain converted at the rate implied by the fund-currency and local-currency values; when
  # there is no local value (no valuation, or same currency) the whole gain is price effect.
  def price_effect_cents(local_gain_cents, fund_value_cents, local_value_cents, total_gain_cents)
    return total_gain_cents.to_d if local_value_cents.to_d.zero?

    (local_gain_cents.to_d * (fund_value_cents.to_d / local_value_cents.to_d)).round(2)
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
    Rails.logger.debug { "compute_fmv_cents_on called for date #{date} for PI id=#{id}" }
    valuation = latest_valuation_on(date)
    quantity_to_use = date == Time.zone.today ? net_quantity : net_quantity_on(date)

    valuation ? quantity_to_use * valuation.per_share_value_in(fund.currency, date, fund:) : 0
  end

  # FMV = latest price * quantity held (in base/instrument currency)
  def compute_instrument_currency_fmv_cents_on(date)
    valuation = latest_valuation_on(date)
    quantity_to_use = date == Time.zone.today ? net_quantity : net_quantity_on(date)

    valuation ? quantity_to_use * valuation.per_share_value_cents : 0
  end

  # Fetches the latest valuation on or before a date
  # The price this fund accepts (PriceResolver): manual and cost always, market when chosen (H7)
  def latest_valuation_on(date)
    PriceResolver.lookup(instrument: investment_instrument, owner: portfolio_company, as_of: date, policy: SourcePolicy.for(fund))&.valuation
  end

  # Calculates net quantity as of a given date
  def net_quantity_on(date)
    # Quantity of this investment that has been sold
    sold_quantity_on = buys_portfolio_attributions
                       .joins(:sold_pi)
                       .merge(PortfolioInvestment.include_proforma.before(date))
                       .sum(:quantity)

    # Quantity that has been converted into another investment
    conversion_quantity = fund.stock_conversions
                              .where(from_portfolio_investment_id: id, conversion_date: ..date)
                              .sum(:from_quantity)

    quantity + sold_quantity_on - conversion_quantity
  end

  memoize :compute_fmv_cents_on, :compute_instrument_currency_fmv_cents_on, :latest_valuation_on, :net_quantity_on

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

  # percentage_head is the custom field in BUY PI which has the percentage to be used for allocation instead of the account entry amount.
  # custom_field_key is the custom field in BUY PI which has the key to fetch the percentage from capital commitment json fields.
  # Instead of using an AccountEntry to determine the allocation percentage, this method uses a custom field in the Buy PI to get the percentage directly - in one case this is the fx_rate
  # We multiply it by the udr percent that is stored in the commitment that is from the feeder fund to the master fund
  # eg - BUY PI - json fields - { exchange_rate: 0.15, fund_level_udr_code: "UDR-1"}
  # capital commitment - json fields - { udr_1: 0.2 }
  # We do - allocated_amount = attribute_value * exchange_rate * udr_percent
  def allocated_amount_with_percent(attribute_name:, percentage_head:, custom_field_key:, end_date:, capital_commitment:)
    total = 0

    # Step 1: Filter portfolio attributions up to the end_date
    scope = portfolio_attributions
            .joins(:bought_pi)
            .where(portfolio_investments: { investment_date: ..end_date })

    # Step 2: Iterate through each attribution and compute allocation
    scope.includes(:bought_pi).find_each do |pa|
      bought_pi = pa.bought_pi
      reporting_date = bought_pi.investment_date

      # Get the percentage from the Buy PI custom field if the percentage_head is present, otherwise default to 1 (100%)
      percentage = percentage_head.present? ? bought_pi.custom_fields.send(percentage_head).to_d : 1

      udr_code = nil
      udr_percent = 1
      if custom_field_key.present?
        udr_code = bought_pi.custom_fields.send(custom_field_key)&.downcase&.delete("-")&.parameterize(separator: "_")
        udr_percent = capital_commitment.json_fields[udr_code.to_s].to_d
      end

      # Fetch the attribute value (e.g., gain, cost_of_sold) in cents from the attribution
      value_cents = pa.public_send(attribute_name).cents

      # Debug log for troubleshooting and auditing
      Rails.logger.debug do
        "pa.id=#{pa.id}, #{attribute_name}=#{value_cents}, percentage=#{percentage}, udr_percent=#{udr_percent}, udr_code=#{udr_code}, reporting_date=#{reporting_date}"
      end

      # Proportional allocation: attribute value * allocation percentage * udr percent
      total += (value_cents / 100) * percentage * udr_percent
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
