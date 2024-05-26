module PortfolioComputations
  extend ActiveSupport::Concern

  included do
    ##########################################################
    ############# Computations for Fund Ratios  ##############
    ##########################################################

    def self.total_investment_costs_cents(model, end_date)
      model.portfolio_investments.buys.where(investment_date: ..end_date).sum(:amount_cents)
    end

    def self.fmv_cents(model, end_date)
      total_fmv_end_date = 0
      model.portfolio_investments.pool.buys.where(investment_date: ..end_date).find_each do |pi|
        # Find the valuation just prior to the end_date
        valuation = pi.portfolio_company.valuations.where(investment_instrument_id: pi.investment_instrument_id, valuation_date: ..end_date).order(valuation_date: :asc).last
        raise "Valuation not found for #{pi.portfolio_company.investor_name} on #{end_date}" unless valuation

        currency = model.instance_of?(::Fund) ? model.currency : model.fund.currency
        total_fmv_end_date += pi.quantity * valuation.per_share_value_in(currency, end_date)
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

  # This method is memoized to avoid multiple calls to the database
  def compute_fmv
    # For buys setup net_quantity, note sold_quantity is -ive
    if buy?
      self.net_quantity = (quantity + sold_quantity - transfer_quantity)
      self.fmv_cents = compute_fmv_cents_on(Time.zone.today)
    else
      self.net_quantity = quantity
      self.fmv_cents = 0
      self.gain_cents = amount_cents.abs + cost_of_sold_cents
    end

    # self.net_quantity = buy? ? (quantity + sold_quantity - transfer_quantity) : quantity
    # self.gain_cents = amount_cents.abs + cost_of_sold_cents if sell?
    # self.fmv_cents = buy? ? compute_fmv_cents_on(Time.zone.today) : 0
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

  # This method is memoized to avoid multiple calls to the database
  def net_quantity_on(date)
    sold_quantity_on = buys_portfolio_attributions.joins(:sold_pi).where('portfolio_investments.investment_date': ..date).sum(:quantity)
    transfer_quantity_on = stock_conversions.where(from_portfolio_investment_id: id, conversion_date: ..date).sum(:from_quantity)
    quantity + sold_quantity_on - transfer_quantity_on
  end

  def price_per_share_cents
    amount_cents / quantity.abs
  end

  # account_entry_name = "Investable Capital Percentage" or "Foreign Investable Capital Percentage"
  def allocation_of_realized_gain_cents(end_date, account_entry_name, capital_commitment)
    realized_gain = 0
    pas_before_end_date = portfolio_attributions.joins(:bought_pi).where("portfolio_investments.investment_date <= ?", end_date)
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
      buys = buys.where(capital_commitment_id:) if self.CoInvest?
      buys = buys.pool if self.Pool?

      total_net_quantity = buys.sum(:net_quantity)

      if quantity.abs > total_net_quantity
        errors.add(:quantity,
                   "Sell quantity is greater than net position #{total_net_quantity}")
      end
    end
  end
end
