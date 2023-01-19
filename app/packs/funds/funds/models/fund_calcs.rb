class FundCalcs
  attr_accessor :fund, :valuation

  def initialize(fund, valuation)
    @fund = fund
    @valuation = valuation
    @collected_amount_cents = @fund.capital_remittance_payments.where("payment_date <= ?", @valuation.valuation_date).sum(:amount_cents)
    @distribution_amount_cents = @fund.capital_distribution_payments.where("payment_date <= ?", @valuation.valuation_date).sum(:amount_cents)
    @committed_amount_cents = @fund.capital_commitments.sum(:committed_amount_cents)
  end

  def fund_utilization
    @committed_amount_cents.positive? ? ((@valuation.portfolio_inv_cost_cents - @valuation.management_opex_cost_cents) / @committed_amount_cents) : 0
  end

  def portfolio_value_to_cost
    @valuation.portfolio_inv_cost_cents.positive? ? (@valuation.portfolio_fmv_valuation_cents / @valuation.portfolio_inv_cost_cents) : 0
  end

  def paid_in_to_committed_capital
    @committed_amount_cents ? @collected_amount_cents / @committed_amount_cents : 0
  end

  def quarterly_irr
    vals = @fund.valuations.order("valuation_date desc").limit(2)
    if vals.length == 2
      prev_valuation = vals[1]
      (@valuation.valuation_cents - @valuation.collection_last_quarter_cents) / prev_valuation.valuation_cents
    else
      0
    end
  end

  def compute_rvpi
    @rvpi = (@valuation.valuation_cents / @collected_amount_cents).round(2) if @collected_amount_cents.positive?
  end

  def compute_dpi
    @dpi = (@distribution_amount_cents / @collected_amount_cents).round(2) if @collected_amount_cents.positive?
  end

  def compute_tvpi
    @dpi + @rvpi if @rvpi && @dpi
  end

  def compute_moic
    # (self.tvpi / self.collected_amount_cents).round(2) if self.tvpi && self.collected_amount_cents > 0
  end

  def compute_xirr
    cf = Xirr::Cashflow.new

    @fund.capital_remittance_payments.where("capital_remittance_payments.payment_date <= ?", @valuation.valuation_date).each do |cr|
      # puts "Adding capital_remittance_payment #{-1 * cr.amount_cents} #{cr.payment_date}"
      cf << Xirr::Transaction.new(-1 * cr.amount_cents, date: cr.payment_date)
    end

    @fund.capital_distribution_payments.where("capital_distribution_payments.payment_date <= ?", @valuation.valuation_date).each do |cdp|
      # puts "Adding capital_distribution_payment #{cdp.amount_cents} #{cdp.payment_date}"
      cf << Xirr::Transaction.new(cdp.amount_cents, date: cdp.payment_date)
    end

    # puts "Adding valuation #{@valuation.valuation_cents} #{@valuation.valuation_date}"
    cf << Xirr::Transaction.new(@valuation.valuation_cents, date: @valuation.valuation_date)

    Rails.logger.debug { "fund.xirr cf: #{cf}" }
    Rails.logger.debug { "fund.xirr irr: #{cf.xirr}" }
    (cf.xirr * 100).round(2)
  end
end
