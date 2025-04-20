module PortfolioComputations
  extend ActiveSupport::Concern

  included do
    ##########################################################
    ############# Computations for Fund Ratios  ##############
    ##########################################################

    def self.total_investment_costs_cents(model, end_date)
      model.portfolio_investments.buys.where(investment_date: ..end_date).sum(:cost_of_remaining_cents)
    end

    def self.avg_cost_cents(model, end_date)
      total_amount_cents = model.portfolio_investments.buys.where(investment_date: ..end_date).sum(:amount_cents)
      total_buy_quantity = model.portfolio_investments.buys.where(investment_date: ..end_date).sum(:quantity)
      total_buy_quantity.positive? ? total_amount_cents / total_buy_quantity : 0
    end

    def self.cost_of_sold_cents_for(model, end_date)
      model.portfolio_investments.sells.where(investment_date: ..end_date).sum(:cost_of_sold_cents)
    end

    def self.total_investment_sold_cents(model, end_date)
      model.portfolio_investments.sells.where(investment_date: ..end_date).sum(:amount_cents)
    end
  end

  def compute_all_numbers
    # We have amount_cents and quantity as stable entered values.
    # cost_cents = amount_cents / quantity and is stable
    # We also have transfer_amount and transfer_quantity as stable values post transfer
    # We also have sold_quantity as stable value based on PA rollups of pa.quantity
    if buy?
      self.net_quantity = (quantity + sold_quantity - transfer_quantity)
      self.net_bought_quantity = quantity - transfer_quantity
      # net_amount_cents is cost of remaining
      self.net_amount_cents = net_quantity * cost_cents
      self.net_bought_amount_cents = net_bought_quantity * cost_cents
      self.cost_of_remaining_cents = net_quantity * cost_cents

      compute_fmv
      # Unrealized gain is fmv - cost_of_remaining, only for buys
      self.unrealized_gain_cents = fmv_cents - net_amount_cents
    else
      self.net_quantity = quantity
      self.net_bought_quantity = 0
      self.net_amount_cents = amount_cents
      self.net_bought_amount_cents = 0
      self.cost_of_remaining_cents = 0
      self.gain_cents = amount_cents.abs + cost_of_sold_cents

      compute_fmv

    end
  end

  def compute_all_numbers_on(end_date)
    # We have amount_cents and quantity as stable entered values.
    # cost_cents = amount_cents / quantity and is stable
    # We also have transfer_amount and transfer_quantity as stable values post transfer
    # We also have sold_quantity as stable value based on PA rollups of pa.quantity
    if buy?
      # This is the quantity of the buys that have been sold before the end date
      sold_quantity = buys_portfolio_attributions.where(investment_date: ..end_date).sum(:quantity)
      # This is the quantity of the buys that have been transferred/converted before the end date
      transfer_quantity = stock_conversions.where(conversion_date: ..end_date).sum(:from_quantity)
      self.sold_quantity = sold_quantity
      self.transfer_quantity = transfer_quantity
      self.net_quantity = (quantity + sold_quantity - transfer_quantity)
      self.net_bought_quantity = quantity - transfer_quantity
      # net_amount_cents is cost of remaining
      self.net_amount_cents = net_quantity * cost_cents
      self.net_bought_amount_cents = net_bought_quantity * cost_cents
      self.cost_of_remaining_cents = net_quantity * cost_cents
      # FMV in the fund currency
      self.fmv_cents = compute_fmv_cents_on(end_date)
      self.unrealized_gain_cents = fmv_cents - cost_of_remaining_cents

      # This are the fields in the instrument currency
      self.base_fmv_cents = compute_base_fmv_cents_on(end_date)
      self.base_cost_of_remaining_cents = net_quantity * base_cost_cents
      self.base_unrealized_gain_cents = base_fmv_cents - base_cost_of_remaining_cents
    else
      self.sold_quantity = 0
      self.transfer_quantity = 0
      self.net_quantity = quantity
      self.net_bought_quantity = 0
      self.net_amount_cents = amount_cents
      self.net_bought_amount_cents = 0
      self.cost_of_remaining_cents = 0
      self.gain_cents = amount_cents.abs + cost_of_sold_cents
      self.fmv_cents = 0
      self.unrealized_gain_cents = 0
      # This are the fields in the instrument currency
      self.base_fmv_cents = 0
      self.base_cost_of_remaining_cents = 0
      self.base_unrealized_gain_cents = 0
    end

    freeze
  end

  # This method is memoized to avoid multiple calls to the database
  def compute_fmv
    # For buys setup net_quantity, note sold_quantity is -ive
    self.fmv_cents = if buy?
                       compute_fmv_cents_on(Time.zone.today)
                     else
                       0
                     end
  end

  # This method is memoized to avoid multiple calls to the database
  def compute_fmv_cents_on(date)
    last_valuation = valuations.where(investment_instrument_id:, valuation_date: ..date).order(valuation_date: :desc).first

    nq = if date == Time.zone.today
           net_quantity
         else
           net_quantity_on(date)
         end

    last_valuation ? nq * last_valuation.per_share_value_in(fund.currency, date) : 0
  end

  def compute_base_fmv_cents_on(date)
    last_valuation = valuations.where(investment_instrument_id:, valuation_date: ..date).order(valuation_date: :desc).first

    nq = if date == Time.zone.today
           net_quantity
         else
           net_quantity_on(date)
         end

    last_valuation ? nq * last_valuation.per_share_value_cents : 0
  end

  # This method is memoized to avoid multiple calls to the database
  def net_quantity_on(date)
    sold_quantity_on = buys_portfolio_attributions.joins(:sold_pi).merge(PortfolioInvestment.before(date)).sum(:quantity)

    # Conversions can happen in the future, but the investment_date of the converted PI is set to the investment_date of the PI from which it was converted (See StockConversion)
    # If the conversion of any of the buys has happened before the end_date, then we need to subtract the converted quantity from the buy_quantity as it has already been converted.
    from_conversion_quantity = fund.stock_conversions.where(from_portfolio_investment_id: id, conversion_date: ..date).sum(:from_quantity)

    conversion_quantity = from_conversion_quantity
    quantity + sold_quantity_on - conversion_quantity
  end

  def price_per_share_cents
    amount_cents / quantity.abs
  end

  # account_entry_name = "Investable Capital Percentage" or "Foreign Investable Capital Percentage"
  def allocation_of_realized_gain_cents(end_date, account_entry_name, capital_commitment)
    realized_gain = 0
    pas_before_end_date = portfolio_attributions.joins(:bought_pi).where(portfolio_investments: { investment_date: ..end_date })
    pas_before_end_date.each do |pa|
      ae_date_of_buy = capital_commitment.account_entries.where(name: account_entry_name, reporting_date: ..pa.bought_pi.investment_date).order(reporting_date: :desc).first
      Rails.logger.debug { "pa.id = #{pa.id} gain cents = #{pa.gain.cents} percentage = #{ae_date_of_buy.amount_cents / 100}" }
      realized_gain += pa.gain.cents * ae_date_of_buy.amount_cents / 100
    end
    realized_gain
  end

  # This method is specific for Pravega. Used similar to the above call, for allocation but on the basis of proforma dates
  def allocation_of_realized_gain_cents_proforma(end_date, account_entry_name, capital_commitment)
    realized_gain = 0
    pas_before_end_date = portfolio_attributions.joins(:bought_pi).where("portfolio_investments.json_fields->'$.proforma_date' <= ?", end_date)
    pas_before_end_date.each do |pa|
      ae_date_of_buy = capital_commitment.account_entries.where(name: account_entry_name, reporting_date: ..pa.bought_pi.custom_fields.proforma_date).order(reporting_date: :desc).first
      Rails.logger.debug { "pa.id = #{pa.id} gain cents = #{pa.gain.cents} percentage = #{ae_date_of_buy.amount_cents / 100}" }
      realized_gain += pa.gain.cents * ae_date_of_buy.amount_cents / 100
    end
    realized_gain
  end

  def sell_quantity_allowed
    if sell? && new_record?

      buys = fund.portfolio_investments.allocatable_buys(portfolio_company_id, investment_instrument_id)

      total_net_quantity = buys.sum(:net_quantity)

      if quantity.abs > total_net_quantity
        errors.add(:quantity,
                   "Sell quantity is greater than net position #{total_net_quantity}")
      end
    end
  end
end
