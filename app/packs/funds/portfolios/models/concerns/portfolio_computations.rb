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

  def compute_fmv
    # For buys setup net_quantity, note sold_quantity is -ive
    self.net_quantity = quantity + sold_quantity if buy?
    self.gain_cents = amount_cents.abs + cost_of_sold_cents if sell?

    self.fmv_cents = buy? ? compute_fmv_cents_on(Time.zone.today, create_valuation: true) : 0
  end

  def compute_fmv_cents_on(date, create_valuation: false)
    last_valuation = portfolio_company.valuations.where(investment_instrument_id:, valuation_date: ..date).order(valuation_date: :desc).first

    # We dont have a valuation and we need to create one
    last_valuation = portfolio_company.valuations.create(investment_instrument_id:, valuation_date: investment_date, per_share_value_cents: cost_cents, entity_id:, owner: fund) if last_valuation.blank? && create_valuation

    nq = if date == Time.zone.today
           net_quantity
         else
           net_quantity_on(date)
         end

    last_valuation ? nq * last_valuation.per_share_value_cents : 0
  end

  def net_quantity_on(date)
    sold_quantity_on = buys_portfolio_attributions.joins(:sold_pi).where('portfolio_investments.investment_date': ..date).sum(:quantity)
    quantity + sold_quantity_on
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
