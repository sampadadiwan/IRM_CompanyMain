class FundCalcs
  def initialize(model, valuation)
    @model = model
    @valuation = valuation
    @collected_amount_cents = @model.capital_remittance_payments.where(capital_remittance_payments: { payment_date: ..@valuation.valuation_date }).sum(:amount_cents)
    @distribution_amount_cents = @model.capital_distribution_payments.where(capital_distribution_payments: { payment_date: ..@valuation.valuation_date }).sum(:net_payable_cents)
    @committed_amount_cents = @model.instance_of?(::Fund) ? @model.capital_commitments.sum(:committed_amount_cents) : @model.committed_amount_cents
  end

  def fund_utilization
    @committed_amount_cents.positive? ? ((@valuation.portfolio_inv_cost_cents + @valuation.management_opex_cost_cents) / @committed_amount_cents) : 0
  end

  def portfolio_value_to_cost
    @valuation.portfolio_inv_cost_cents.positive? ? (@valuation.portfolio_fmv_valuation_cents / @valuation.portfolio_inv_cost_cents) : 0
  end

  def paid_in_to_committed_capital
    @committed_amount_cents ? @collected_amount_cents / @committed_amount_cents : 0
  end

  def quarterly_irr
    0
  end

  # Fund and Commitment
  def compute_rvpi
    @rvpi = 0
  end

  # Fund and Commitment
  def compute_dpi
    @dpi = (@distribution_amount_cents / @collected_amount_cents).round(2) if @collected_amount_cents.positive?
  end

  # Fund and Commitment
  def compute_tvpi
    @dpi + @rvpi if @rvpi && @dpi
  end

  def compute_moic
    # (self.tvpi / self.collected_amount_cents).round(2) if self.tvpi && self.collected_amount_cents > 0
  end
end
