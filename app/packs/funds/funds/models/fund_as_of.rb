class FundAsOf
  include Memoized

  attr_reader :fund, :as_of_date

  DELEGATED_METHODS = %i[id json_fields name currency tracking_currency].freeze
  # Initialize with a fund and the as_of_date
  # @param fund [Fund] The fund to represent
  # @param as_of_date [Date] The date to represent the fund as of
  def initialize(fund, as_of_date)
    @fund = fund
    @as_of_date = as_of_date.is_a?(Date) ? as_of_date.end_of_day : as_of_date
  end

  # Below are the methods that filter the fund's data based on the as_of_date
  def capital_commitments
    fund.capital_commitments.where(commitment_date: ..as_of_date)
  end
  memoize :capital_commitments

  def capital_remittances
    fund.capital_remittances.where(remittance_date: ..as_of_date).where(capital_call_id: capital_calls.select(:id))
  end
  memoize :capital_remittances

  def capital_remittance_payments
    fund.capital_remittance_payments.where(payment_date: ..as_of_date).where(capital_remittance_id: capital_remittances.select(:id))
  end
  memoize :capital_remittance_payments

  def capital_distribution_payments
    fund.capital_distribution_payments.where(payment_date: ..as_of_date).where(capital_commitment_id: capital_commitments.select(:id))
  end
  memoize :capital_distribution_payments

  def capital_calls
    fund.capital_calls.where(call_date: ..as_of_date)
  end
  memoize :capital_calls

  def capital_distributions
    fund.capital_distributions.where(distribution_date: ..as_of_date)
  end
  memoize :capital_distributions

  def valuations
    fund.valuations.where(valuation_date: ..as_of_date)
  end
  memoize :valuations

  def fund_ratios
    fund.fund_ratios.where(end_date: ..as_of_date)
  end
  memoize :fund_ratios

  def latest_valuation
    valuations.order(valuation_date: :desc).first
  end
  memoize :latest_valuation

  # The fund's own money figures (Fund#committed_amount and the rest) are running totals rolled up from the rows below,
  # so these sum the same rows up to the as-of date and equal the fund's own figures for today. H18
  # Commitments dated up to the date; a commitment dated later (E27) is not in it. Adjustments are not rolled back.
  def committed_amount
    Money.new(capital_commitments.sum(:committed_amount_cents), fund.currency)
  end
  memoize :committed_amount

  def tracking_committed_amount
    Money.new(capital_commitments.sum(:tracking_committed_amount_cents), tracking_money_currency)
  end
  memoize :tracking_committed_amount

  def call_amount
    Money.new(capital_remittances.sum(:call_amount_cents), fund.currency)
  end
  memoize :call_amount

  def tracking_call_amount
    Money.new(capital_remittances.sum(:tracking_call_amount_cents), tracking_money_currency)
  end
  memoize :tracking_call_amount

  # What was received up to the date, from the remittances the fund has verified (as the fund's own total counts only
  # verified ones). From the payments, not the remittance's running total, so a payment made after the date (E28) is not
  # counted early. An unverified remittance is not counted (E29); verification is read as it is now.
  def collected_amount
    Money.new(verified_remittance_payments.sum(:amount_cents), fund.currency)
  end
  memoize :collected_amount

  def tracking_collected_amount
    Money.new(verified_remittance_payments.sum(:tracking_amount_cents), tracking_money_currency)
  end
  memoize :tracking_collected_amount

  # Gross payable of the distribution payments dated up to the date (E30), as the fund's own total sums it
  def distribution_amount
    Money.new(capital_distribution_payments.sum(:gross_payable_cents), fund.currency)
  end
  memoize :distribution_amount

  # Only completed payments, as the fund's own tracking-currency total counts them
  def tracking_distribution_amount
    Money.new(capital_distribution_payments.completed.sum(:tracking_net_payable_cents), tracking_money_currency)
  end
  memoize :tracking_distribution_amount

  # Premium of the units issued up to the date (E31)
  def total_units_premium
    Money.new(fund.fund_units.where(issue_date: ..as_of_date).sum(:total_premium_cents), fund.currency)
  end
  memoize :total_units_premium

  # Not dated: the target is a plan, not something that happens on a day
  delegate :target_committed_amount, to: :fund

  def account_entries
    fund.account_entries.where(reporting_date: ..as_of_date)
  end

  # The currency of the tracking-currency figures: the fund's tracking currency, else the fund's own
  def tracking_money_currency
    fund.tracking_currency.presence || fund.currency
  end

  def verified_remittance_payments
    capital_remittance_payments.where(capital_remittance_id: capital_remittances.verified.select(:id))
  end
  private :tracking_money_currency, :verified_remittance_payments

  # Delegate filtered methods to the fund
  def method_missing(method, *, &)
    if fund.respond_to?(method) && DELEGATED_METHODS.include?(method)
      fund.send(method, *, &)
    else
      super
    end
  end

  def respond_to_missing?(method, include_private = false)
    fund.respond_to?(method, include_private) || super
  end
end
