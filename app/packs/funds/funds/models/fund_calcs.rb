class FundCalcs
  attr_accessor :fund, :valuation

  def initialize(fund, valuation)
    @fund = fund
    @valuation = valuation
    @collected_amount_cents = @fund.capital_remittance_payments.where("payment_date <= ?", @valuation.valuation_date).sum(:amount_cents)
    @distribution_amount_cents = @fund.capital_distribution_payments.where("payment_date <= ?", @valuation.valuation_date).sum(:amount_cents)
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

    @fund.capital_remittance_payments.where("created_at <= ?", @valuation.valuation_date).each do |cr|
      cf << Xirr::Transaction.new(-1 * cr.amount_cents, date: cr.payment_date)
    end

    @fund.capital_distribution_payments.where("created_at <= ?", @valuation.valuation_date).each do |cdp|
      cf << Xirr::Transaction.new(cdp.amount_cents, date: cdp.payment_date)
    end

    cf << Xirr::Transaction.new(@valuation.valuation_cents, date: @valuation.valuation_date)

    Rails.logger.debug { "fund.xirr cf: #{cf}" }
    Rails.logger.debug { "fund.xirr irr: #{cf.xirr}" }
    (cf.xirr * 100).round(2)
  end
end
