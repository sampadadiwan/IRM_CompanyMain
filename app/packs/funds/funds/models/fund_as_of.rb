class FundAsOf
  include Memoized

  attr_reader :fund, :as_of_date

  DELEGATED_METHODS = %i[id json_fields name currency].freeze
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
    fund.capital_remittances.where(remittance_date: ..as_of_date).where(capital_call_id: capital_calls.pluck(:id))
  end
  memoize :capital_remittances

  def capital_distribution_payments
    fund.capital_distribution_payments.where(payment_date: ..as_of_date).where(capital_commitment_id: capital_commitments.pluck(:id))
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
