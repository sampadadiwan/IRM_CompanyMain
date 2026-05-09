class FundTemplateDecorator < TemplateDecorator # rubocop:disable Metrics/ClassLength
  include CurrencyHelper
  include Memoized

  DIST_CASH_SQL = "gross_payable_cents - reinvestment_with_fees_cents".freeze
  DUE_AMOUNT_SQL = "capital_remittances.call_amount_cents + capital_remittances.other_fee_cents".freeze

  METHODS_START_WITH = %w[money_].freeze
  attr_reader :as_of_date, :currency, :capital_commitment, :capital_remittance

  def initialize(object)
    super
    @as_of_date = object.as_of_date
    @yesterday_end_of_day = @as_of_date.yesterday.end_of_day
    @currency = object.currency
    @capital_remittance = object.json_fields["capital_remittance"]
    @capital_distribution_payment = object.json_fields["capital_distribution_payment"]

    @capital_commitment = if @capital_remittance
                            @capital_remittance.capital_commitment
                          elsif @capital_distribution_payment
                            @capital_distribution_payment.capital_commitment
                          end
  end

  def method_missing(method_name, *args, &)
    if method_name.to_s.starts_with?("money_")
      # please refer to the comment in the TemplateDecorator for core  working
      # In  cases where the resultant attribute is not a Money object but a numeric value, we convert it to Money using the currency of the fund before formatting it.
      # This is to handle cases where we might be summing up cents values directly from the database which would return a numeric value instead of a Money object.
      attr_name = method_name.to_s.gsub("money_", "")

      res = send(attr_name)
      res = Money.new(res, @currency) if !res.is_a?(Money) && res.is_a?(Numeric)
      money_to_currency(res)
    else
      # for any other method, we just call super to handle it as usual
      super
    end
  end

  def respond_to_missing?(method_name, include_private = false)
    METHODS_START_WITH.any? { |prefix| method_name.to_s.starts_with?(prefix) } || super
  end

  # === Helpers ===

  def money_sum(scope, column)
    Money.new(scope.sum(column), @currency)
  end

  def percentage(part, total)
    part = part.cents.to_d if part.respond_to?(:cents)
    total = total.cents.to_d if total.respond_to?(:cents)
    return 0 if total.zero?

    (part.to_d / total.to_d) * 100
  end

  # === Fund Base ===
  # Fund As Of is the fund object at the time of the remittance date
  def fund_as_of = object
  memoize :fund_as_of

  # Commitments of type All, LP and GP as of the remittance date
  def fund_commitments = fund_as_of.capital_commitments
  memoize :fund_commitments

  # Fetch Capital Calls before the remittance date
  def prior_calls = fund_as_of.capital_calls.where(call_date: ..@yesterday_end_of_day)
  memoize :prior_calls

  def total_fund_call_amount_cents
    fund_as_of.capital_remittances.sum(:call_amount_cents)
  end
  memoize :total_fund_call_amount_cents

  def total_fund_call_amount = Money.new(total_fund_call_amount_cents, @currency)
  memoize :total_fund_call_amount

  def total_fund_computed_amount_cents
    fund_as_of.capital_remittances.sum(:computed_amount_cents)
  end
  memoize :total_fund_computed_amount_cents

  def total_fund_computed_amount = Money.new(total_fund_computed_amount_cents, @currency)
  memoize :total_fund_computed_amount

  def total_fund_capital_fee_cents
    fund_as_of.capital_remittances.sum(:capital_fee_cents)
  end
  memoize :total_fund_capital_fee_cents

  def total_fund_capital_fee = Money.new(total_fund_capital_fee_cents, @currency)
  memoize :total_fund_capital_fee

  def fund_commitments_lp = fund_commitments.lp(fund_as_of.id)
  memoize :fund_commitments_lp

  def fund_commitments_gp = fund_commitments.gp(fund_as_of.id)
  memoize :fund_commitments_gp

  # Remittances of type LP and GP as of the remittance date
  def fund_remittances_lp = fund_as_of.capital_remittances.joins(:capital_commitment).merge(fund_commitments_lp)
  memoize :fund_remittances_lp

  def fund_remittances_gp = fund_as_of.capital_remittances.joins(:capital_commitment).merge(fund_commitments_gp)
  memoize :fund_remittances_gp

  def fund_remittances_lp_prior = fund_remittances_lp.where(remittance_date: ..@yesterday_end_of_day, capital_call_id: prior_calls.select(:id))
  memoize :fund_remittances_lp_prior

  def fund_remittances_lp_curr
    if @capital_remittance.present?
      fund_remittances_lp.where(remittance_date: @as_of_date, capital_call_id: @capital_remittance.capital_call_id)
    else
      fund_remittances_lp.where(remittance_date: @as_of_date)
    end
  end
  memoize :fund_remittances_lp_curr

  def fund_remittances_gp_prior = fund_remittances_gp.where(remittance_date: ..@yesterday_end_of_day, capital_call_id: prior_calls.select(:id))
  memoize :fund_remittances_gp_prior

  def fund_remittances_gp_curr
    if @capital_remittance.present?
      fund_remittances_gp.where(remittance_date: @as_of_date, capital_call_id: @capital_remittance.capital_call_id)
    else
      fund_remittances_gp.where(remittance_date: @as_of_date)
    end
  end
  memoize :fund_remittances_gp_curr

  # Fund remittances total amounts - prior/current for LP and GP
  def fund_remittances_prior = fund_as_of.capital_remittances.where(remittance_date: ..@yesterday_end_of_day, capital_call_id: prior_calls.select(:id))
  memoize :fund_remittances_prior

  def fund_remittances_curr
    if @capital_remittance.present?
      fund_as_of.capital_remittances.where(remittance_date: @as_of_date, capital_call_id: @capital_remittance.capital_call_id)
    else
      fund_as_of.capital_remittances.where(remittance_date: @as_of_date)
    end
  end
  memoize :fund_remittances_curr

  # Fund-level totals for prior notice (computed amount and capital fee)
  def total_fund_computed_amount_prior_cents = fund_remittances_prior.sum(:computed_amount_cents)
  memoize :total_fund_computed_amount_prior_cents

  def total_fund_capital_fee_prior_cents = fund_remittances_prior.sum(:capital_fee_cents)
  memoize :total_fund_capital_fee_prior_cents

  def total_fund_call_amount_prior_cents = fund_remittances_prior.sum(:call_amount_cents)
  memoize :total_fund_call_amount_prior_cents

  # Fund-level totals for current notice (computed amount and capital fee)
  def total_fund_computed_amount_curr_cents = fund_remittances_curr.sum(:computed_amount_cents)
  memoize :total_fund_computed_amount_curr_cents

  def total_fund_capital_fee_curr_cents = fund_remittances_curr.sum(:capital_fee_cents)
  memoize :total_fund_capital_fee_curr_cents

  def total_fund_call_amount_curr_cents = fund_remittances_curr.sum(:call_amount_cents)
  memoize :total_fund_call_amount_curr_cents

  ########### DISTRIBUTIONS ###########

  # Distribution Payments of type All, LP and GP as of the remittance date
  def fund_dist_payments = fund_as_of.capital_distribution_payments
  memoize :fund_dist_payments

  def fund_dist_payments_lp = fund_dist_payments.joins(:capital_commitment).merge(fund_commitments_lp)
  memoize :fund_dist_payments_lp

  def fund_dist_payments_gp = fund_dist_payments.joins(:capital_commitment).merge(fund_commitments_gp)
  memoize :fund_dist_payments_gp

  def fund_dist_payments_prior = fund_dist_payments.where(payment_date: ..@yesterday_end_of_day)
  memoize :fund_dist_payments_prior

  def fund_dist_payments_curr = fund_dist_payments.where(payment_date: @as_of_date)
  memoize :fund_dist_payments_curr

  # Distribution Payments prior to and on current notice date for LP and GP
  def fund_dist_payments_lp_prior = fund_dist_payments_lp.where(payment_date: ..@yesterday_end_of_day)
  memoize :fund_dist_payments_lp_prior

  def fund_dist_payments_gp_prior = fund_dist_payments_gp.where(payment_date: ..@yesterday_end_of_day)
  memoize :fund_dist_payments_gp_prior

  def fund_dist_payments_lp_curr = fund_dist_payments_lp.where(payment_date: @as_of_date)
  memoize :fund_dist_payments_lp_curr

  def fund_dist_payments_gp_curr = fund_dist_payments_gp.where(payment_date: @as_of_date)
  memoize :fund_dist_payments_gp_curr

  # Distribution Payments associated to the capital commitment of type All  as of the remittance date
  # This is folio/investor dist_payments
  def dist_payments = @capital_commitment.capital_distribution_payments.where(payment_date: ..@as_of_date)
  memoize :dist_payments

  # kyc dist payments should only consider within the fund
  def kyc_dist_payments = @capital_commitment.investor_kyc.capital_distribution_payments.where(fund_id: @capital_commitment.fund_id, payment_date: ..@as_of_date)
  memoize :kyc_dist_payments

  # def fund_distributions = fund_as_of.capital_distributions
  # memoize :fund_distributions

  alias comm_dist_payments dist_payments

  def comm_dist_payments_lp = dist_payments.joins(:capital_commitment).merge(fund_commitments_lp)
  memoize :comm_dist_payments_lp

  def comm_dist_payments_gp = dist_payments.joins(:capital_commitment).merge(fund_commitments_gp)
  memoize :comm_dist_payments_gp

  def kyc_dist_payments_lp = kyc_dist_payments.joins(:capital_commitment).merge(fund_commitments_lp)
  memoize :kyc_dist_payments_lp

  def kyc_dist_payments_gp = kyc_dist_payments.joins(:capital_commitment).merge(fund_commitments_gp)
  memoize :kyc_dist_payments_gp

  def comm_dist_payments_prior = comm_dist_payments.where(payment_date: ..@yesterday_end_of_day)
  memoize :comm_dist_payments_prior

  def comm_dist_payments_curr = comm_dist_payments.where(payment_date: @as_of_date)
  memoize :comm_dist_payments_curr

  def kyc_dist_payments_prior = kyc_dist_payments.where(payment_date: ..@yesterday_end_of_day)
  memoize :kyc_dist_payments_prior

  def kyc_dist_payments_curr = kyc_dist_payments.where(payment_date: @as_of_date)
  memoize :kyc_dist_payments_curr

  #=== Committed Cash Helpers ===#
  # Committed Cash Amount of the fund_as_of commitments of type LP and GP
  def committed_cash_lp = money_sum(fund_commitments_lp, :committed_amount_cents)
  memoize :committed_cash_lp

  def committed_cash_gp = money_sum(fund_commitments_gp, :committed_amount_cents)
  memoize :committed_cash_gp

  def committed_cash_total_fund_cents = fund_commitments.sum(:committed_amount_cents)
  memoize :committed_cash_total_fund_cents

  # Money conversion methods for fund-level totals
  def committed_cash_total_fund = Money.new(committed_cash_total_fund_cents, @currency)
  memoize :committed_cash_total_fund

  def committed_cash_investor = @capital_commitment.committed_amount
  memoize :committed_cash_investor

  # Percentage of committed cash of the capital commitment relative to the total fund commitments
  def committed_cash_investor_percent = percentage(committed_cash_investor, committed_cash_total_fund)

  # Committed Cash Amount of the KYC
  def committed_cash_kyc = money_sum(kyc_commitments, :committed_amount_cents)
  memoize :committed_cash_kyc

  # Percentage of committed cash of the KYC relative to the total fund commitments
  def committed_cash_kyc_percent = percentage(committed_cash_kyc, committed_cash_total_fund)

  #=== Committed Reinvestment Helpers ===#

  # Committed Reinvestment Amount of the fund_as_of commitments of type LP and GP
  def committed_reinvest_lp = money_sum(fund_dist_payments_lp, :reinvestment_with_fees_cents)
  memoize :committed_reinvest_lp

  def committed_reinvest_gp = money_sum(fund_dist_payments_gp, :reinvestment_with_fees_cents)
  memoize :committed_reinvest_gp

  # Total Reinvestment Amount of the fund_as_of distribution payments
  def committed_reinvest_total_fund_cents
    fund_dist_payments.sum(:reinvestment_with_fees_cents)
  end
  memoize :committed_reinvest_total_fund_cents

  def committed_reinvest_total_fund = Money.new(committed_reinvest_total_fund_cents, @currency)
  memoize :committed_reinvest_total_fund

  # Committed Reinvestment Amount of the commitment
  def committed_reinvest_investor = money_sum(dist_payments, :reinvestment_with_fees_cents)
  memoize :committed_reinvest_investor

  # Committed reinvestment of the investor kyc
  def committed_reinvest_kyc = money_sum(kyc_dist_payments, :reinvestment_with_fees_cents)
  memoize :committed_reinvest_kyc

  # Percentage of committed reinvestment of the KYC relative to the total fund reinvestments
  def committed_reinvest_kyc_percent = percentage(committed_reinvest_kyc, committed_reinvest_total_fund)

  # Percentage of committed reinvestment of the capital commitment relative to the total fund commitments
  def committed_reinvest_investor_percent = percentage(committed_reinvest_investor, committed_reinvest_total_fund)

  #=== Commitment Totals ===#

  # Total Committed Cash And Reinvestment Amount of the fund_as_of commitments of type LP
  def total_comm_lp = committed_cash_lp + committed_reinvest_lp
  memoize :total_comm_lp

  # Total Committed Cash And Reinvestment Amount of the fund_as_of commitments of type GP
  def total_comm_gp = committed_cash_gp + committed_reinvest_gp
  memoize :total_comm_gp

  # Total Committed Cash And Reinvestment Amount of the fund_as_of commitments
  def total_comm_fund = total_comm_lp + total_comm_gp
  memoize :total_comm_fund

  # Total Committed Cash And Reinvestment Amount of the commitment
  def total_comm_investor = committed_cash_investor + committed_reinvest_investor
  memoize :total_comm_investor

  # Percentage of total committed cash and reinvestment of the capital commitment relative to the total fund
  def total_comm_investor_percent = percentage(total_comm_investor.cents, total_comm_fund.cents)

  # Total Committed Cash And Reinvestment Amount of the KYC
  def total_comm_kyc = committed_cash_kyc + committed_reinvest_kyc
  memoize :total_comm_kyc

  # Percentage of total committed cash and reinvestment of the KYC relative to the total fund
  def total_comm_kyc_percent = percentage(total_comm_kyc.cents, total_comm_fund.cents)

  #=== Reinvestment Ratios ===#
  # Percentage of committed reinvestment to committed cash of type LP and GP
  def percent_reinvest_to_cash_lp = percentage(committed_reinvest_lp, committed_cash_lp)
  def percent_reinvest_to_cash_gp = percentage(committed_reinvest_gp, committed_cash_gp)
  # Percentage of total committed reinvestment to total committed cash
  def percent_reinvest_to_cash_total = percentage(committed_reinvest_lp + committed_reinvest_gp, committed_cash_total_fund)
  # Percentage of investor's committed reinvestment to investor's committed cash
  def percent_reinvest_to_cash_investor = percentage(committed_reinvest_investor, committed_cash_investor)
  # Percentage of KYC's committed reinvestment to KYC's committed cash
  def percent_reinvest_to_cash_kyc = percentage(committed_reinvest_kyc, committed_cash_kyc)

  #=== Drawdowns ===#

  # Remittance Call amount of the fund_as_of remittances of type LP and GP and of the investor
  def drawdown_cash_lp = money_sum(fund_remittances_lp, :call_amount_cents)
  memoize :drawdown_cash_lp

  def drawdown_cash_gp = money_sum(fund_remittances_gp, :call_amount_cents)
  memoize :drawdown_cash_gp

  def drawdown_cash_total = drawdown_cash_lp + drawdown_cash_gp
  memoize :drawdown_cash_total
  alias drawdown_cash_total_fund drawdown_cash_total

  def total_drawdown_fund = total_drawdown_lp + total_drawdown_gp
  memoize :total_drawdown_fund

  def drawdown_cash_investor = money_sum(investor_remittances_incl, :call_amount_cents)
  memoize :drawdown_cash_investor

  # total_fund_call_amount will be same as drawdown_cash_total/_fund
  def drawdown_cash_investor_percent = percentage(drawdown_cash_investor, drawdown_cash_total)

  # Remittance Call amount / Drawdown amount of the KYC
  # kyc remittances of the same fund
  def drawdown_cash_kyc = money_sum(kyc_remittances, :call_amount_cents)
  memoize :drawdown_cash_kyc

  # Percentage of drawdown cash of the KYC relative to the total fund remittances
  def drawdown_cash_kyc_percent = percentage(drawdown_cash_kyc, drawdown_cash_total)

  # Reinvestment amount of the fund_as_of distribution payments of the investor / commitment
  alias drawdown_reinvest_investor committed_reinvest_investor

  # Percentage of drawdown reinvestment of the investor relative to the total fund reinvestments
  def drawdown_reinvest_investor_percent = percentage(drawdown_reinvest_investor, committed_reinvest_total_fund)

  # Reinvestment amount of the fund_as_of distribution payments of the KYC
  alias drawdown_reinvest_kyc committed_reinvest_kyc

  # Percentage of drawdown reinvestment of the KYC relative to the total fund reinvestments
  def drawdown_reinvest_kyc_percent = percentage(drawdown_reinvest_kyc, committed_reinvest_total_fund)

  # Total of remittance call amount and Reinvestment amount
  def total_drawdown_lp = drawdown_cash_lp + dist_reinvest_lp
  memoize :total_drawdown_lp

  def total_drawdown_gp = drawdown_cash_gp + dist_reinvest_gp
  memoize :total_drawdown_gp

  def total_drawdown_investor = drawdown_cash_investor + drawdown_reinvest_investor
  memoize :total_drawdown_investor

  def total_drawdown_investor_percent = percentage(total_drawdown_investor.cents, total_drawdown_fund.cents)

  def total_drawdown_kyc = drawdown_cash_kyc + drawdown_reinvest_kyc
  memoize :total_drawdown_kyc

  # Percentage of total drawdown of the KYC relative to the total fund
  def total_drawdown_kyc_percent = percentage(total_drawdown_kyc.cents, total_drawdown_fund.cents)

  # Percentage of drawdown cash of type LP and GP, total, investor and KYC
  def percent_drawdown_cash_lp = percentage(drawdown_cash_lp, committed_cash_lp)
  def percent_drawdown_cash_gp = percentage(drawdown_cash_gp, committed_cash_gp)
  def percent_drawdown_cash_total = percentage(drawdown_cash_lp + drawdown_cash_gp, committed_cash_total_fund)
  def percent_drawdown_cash_investor = percentage(drawdown_cash_investor, committed_cash_investor)
  def percent_drawdown_cash_kyc = percentage(drawdown_cash_kyc, committed_cash_kyc)

  #=== Undrawn Commitments ===#

  # Undrawn Amount is the difference between the committed cash + commitment reinvestment and the total drawdown amount
  # Percentage of undrawn commitment of type LP and GP, total, investor and KYC
  def undrawn_comm_lp = total_comm_lp - total_drawdown_lp
  memoize :undrawn_comm_lp
  def undrawn_comm_gp = total_comm_gp - total_drawdown_gp
  memoize :undrawn_comm_gp
  def undrawn_comm_total = undrawn_comm_lp + undrawn_comm_gp
  memoize :undrawn_comm_total

  def undrawn_comm_investor = committed_cash_investor - drawdown_cash_investor
  def undrawn_comm_investor_percent = percentage(undrawn_comm_investor, undrawn_comm_total)
  def undrawn_comm_kyc = committed_cash_kyc - drawdown_cash_kyc
  def undrawn_comm_kyc_percent = percentage(undrawn_comm_kyc, undrawn_comm_total)

  # Percentage of undrawn commitment of type LP and GP, total, investor and KYC relative to the total fund commitments
  def percent_undrawn_comm_lp = percentage(undrawn_comm_lp, committed_cash_lp)
  def percent_undrawn_comm_gp = percentage(undrawn_comm_gp, committed_cash_gp)
  def percent_undrawn_comm_total = percentage(undrawn_comm_total, committed_cash_total_fund)
  def percent_undrawn_comm_investor = percentage(undrawn_comm_investor, committed_cash_investor)
  # divide by total kyc commitments
  def percent_undrawn_comm_kyc = percentage(undrawn_comm_kyc.cents, kyc_commitments.sum(:committed_amount_cents))

  # === Distribution Cash ===
  # === Distribution Cash & Reinvestment ===

  # Distribution Cash is the sum of the gross payable amount - reinvestment amount of the distribution payments
  def dist_cash_lp = Money.new(fund_dist_payments_lp.sum(DIST_CASH_SQL), @currency)
  memoize :dist_cash_lp
  def dist_cash_gp = Money.new(fund_dist_payments_gp.sum(DIST_CASH_SQL), @currency)
  memoize :dist_cash_gp

  # For Total we use the distribution payments of the fund_as_of
  def dist_cash_total = dist_cash_lp + dist_cash_gp
  memoize :dist_cash_total
  alias dist_cash_total_fund dist_cash_total

  # For investor we use distribution payments of the capital commitment
  def dist_cash_investor = Money.new(dist_payments.sum(DIST_CASH_SQL), @currency)
  memoize :dist_cash_investor

  def dist_cash_investor_percent = percentage(dist_cash_investor.cents, dist_cash_total.cents)

  # For KYC we use distribution payments of the investor kyc
  # Distribution Cash amount of the KYC
  def dist_cash_kyc = Money.new(kyc_dist_payments.sum(DIST_CASH_SQL), @currency)
  memoize :dist_cash_kyc

  # Percentage of distribution cash of the KYC relative to the total fund distributions
  def dist_cash_kyc_percent = percentage(dist_cash_kyc.cents, dist_cash_total.cents)

  # === Distribution Reinvestment ===

  def dist_reinvest_lp = money_sum(fund_dist_payments_lp, :reinvestment_with_fees_cents)
  memoize :dist_reinvest_lp
  def dist_reinvest_gp = money_sum(fund_dist_payments_gp, :reinvestment_with_fees_cents)
  memoize :dist_reinvest_gp
  alias dist_reinvest_total_fund committed_reinvest_total_fund

  # Reinvestment amount is sum of the reinvestment amount of the distribution payments
  alias dist_reinvest_investor committed_reinvest_investor

  # Percentage of distribution reinvestment of the investor relative to the total fund reinvestments
  def dist_reinvest_investor_percent = percentage(dist_reinvest_investor, committed_reinvest_total_fund)

  # Reinvestment amount of the KYC
  alias dist_reinvest_kyc committed_reinvest_kyc

  # Percentage of distribution reinvestment of the KYC relative to the total fund reinvestments
  def dist_reinvest_kyc_percent = percentage(dist_reinvest_kyc, committed_reinvest_total_fund)

  # ===== Total Distribution =====

  def total_dist_lp = dist_cash_lp + dist_reinvest_lp
  memoize :total_dist_lp
  def total_dist_gp = dist_cash_gp + dist_reinvest_gp
  memoize :total_dist_gp
  def total_dist_fund = total_dist_lp + total_dist_gp
  memoize :total_dist_fund

  def total_dist_investor = dist_cash_investor + dist_reinvest_investor
  def total_dist_investor_percent = percentage(total_dist_investor.cents, total_dist_fund.cents)

  # Total Distribution Amount of the KYC
  def total_dist_kyc = dist_cash_kyc + dist_reinvest_kyc
  memoize :total_dist_kyc

  # Percentage of total distribution of the KYC relative to the total fund
  def total_dist_kyc_percent = percentage(total_dist_kyc.cents, total_dist_fund.cents)

  # === DPI ===
  # DPI is the difference between Distribution Cash and Drawdown Cash
  def dpi_lp = dist_cash_lp / drawdown_cash_lp
  memoize :dpi_lp
  def dpi_gp = dist_cash_gp / drawdown_cash_gp
  memoize :dpi_gp
  def dpi_total_fund = dist_cash_total_fund / drawdown_cash_total_fund

  def dpi_investor = dist_cash_investor / drawdown_cash_investor

  def dpi_kyc = dist_cash_kyc / drawdown_cash_kyc

  # === Recallable Distributions ===
  # Recallable Distribution is the minimum of 20% of committed amount plus reinvestment amount and distribution cash
  def recall_dist_lp = [dist_cash_lp, (0.2 * committed_cash_lp) + committed_reinvest_lp].min
  memoize :recall_dist_lp
  def recall_dist_gp = [dist_cash_gp, (0.2 * committed_cash_gp) + committed_reinvest_gp].min
  memoize :recall_dist_gp
  def recall_dist_total_fund = [dist_cash_total_fund, (0.2 * committed_cash_total_fund) + committed_reinvest_total_fund].min
  memoize :recall_dist_total_fund

  def recall_dist_investor = [dist_cash_investor, (0.2 * committed_cash_investor) + committed_reinvest_investor].min
  memoize :recall_dist_investor

  def recall_dist_investor_percent = percentage(recall_dist_investor, recall_dist_total_fund)

  def recall_dist_kyc = [dist_cash_kyc, (0.2 * committed_cash_kyc) + committed_reinvest_kyc].min
  memoize :recall_dist_kyc

  def recall_dist_kyc_percent = percentage(recall_dist_kyc, recall_dist_total_fund)

  # === Percent Recallable Distributions ===
  # Percentage of Recallable Distribution is the recallable distribution divided by committed amount
  def percent_recall_dist_lp = percentage(recall_dist_lp, committed_cash_lp)
  memoize :percent_recall_dist_lp

  def percent_recall_dist_gp = percentage(recall_dist_gp, committed_cash_gp)
  memoize :percent_recall_dist_gp

  def percent_recall_dist_total_fund = percentage(recall_dist_total_fund, committed_cash_total_fund)

  def percent_recall_dist_investor = percentage(recall_dist_investor, committed_cash_investor)

  def percent_recall_dist_kyc = percentage(recall_dist_kyc, committed_cash_kyc)

  # === LP/GP Fund-level aggregates for Section C template replacement ===
  # These methods replace computed collection fields in the Sablon template with memoized values

  # Drawdown Cash (Computed Amount) - Prior, Current, Including for LP, GP, Total
  def drawdown_cash_prior_lp = money_sum(fund_remittances_lp_prior, :computed_amount_cents)
  memoize :drawdown_cash_prior_lp

  def drawdown_cash_prior_gp = money_sum(fund_remittances_gp_prior, :computed_amount_cents)
  memoize :drawdown_cash_prior_gp

  def drawdown_cash_prior_total = drawdown_cash_prior_lp + drawdown_cash_prior_gp
  memoize :drawdown_cash_prior_total

  # For Drawdown Cash we use Computed Amount as we dont want to include the capital fee in it
  def drawdown_cash_prior_investor
    money_sum(investor_remittances_prior, :computed_amount_cents)
  end
  memoize :drawdown_cash_prior_investor

  def drawdown_cash_prior_investor_percent = percentage(drawdown_cash_prior_investor.cents, drawdown_cash_prior_total.cents)

  # Drawdown Cash of the KYC prior to notice date
  def drawdown_cash_prior_kyc = money_sum(kyc_remittances_prior, :computed_amount_cents)
  memoize :drawdown_cash_prior_kyc

  # Percentage of drawdown cash of the KYC prior to notice date
  def drawdown_cash_prior_kyc_percent = percentage(drawdown_cash_prior_kyc.cents, drawdown_cash_prior_total.cents)

  def drawdown_cash_curr_lp = money_sum(fund_remittances_lp_curr, :computed_amount_cents)
  memoize :drawdown_cash_curr_lp

  def drawdown_cash_curr_gp = money_sum(fund_remittances_gp_curr, :computed_amount_cents)
  memoize :drawdown_cash_curr_gp

  def drawdown_cash_curr_total = drawdown_cash_curr_lp + drawdown_cash_curr_gp
  memoize :drawdown_cash_curr_total

  def drawdown_cash_curr_investor
    if @capital_remittance.present?
      @capital_remittance.computed_amount
    else
      money_sum(investor_remittances_curr, :computed_amount_cents)
    end
  end

  def drawdown_cash_curr_investor_percent
    percentage(
      drawdown_cash_curr_investor,
      drawdown_cash_curr_total
    )
  end

  # Drawdown Cash on the current notice date for the KYC
  def drawdown_cash_curr_kyc = money_sum(kyc_remittances_curr, :computed_amount_cents)
  memoize :drawdown_cash_curr_kyc

  def drawdown_cash_curr_kyc_percent
    percentage(drawdown_cash_curr_kyc.cents, drawdown_cash_curr_total.cents)
  end

  def drawdown_cash_incl_lp = money_sum(fund_remittances_lp, :computed_amount_cents)
  memoize :drawdown_cash_incl_lp

  def drawdown_cash_incl_gp = money_sum(fund_remittances_gp, :computed_amount_cents)
  memoize :drawdown_cash_incl_gp

  def drawdown_cash_incl_total = drawdown_cash_incl_lp + drawdown_cash_incl_gp
  memoize :drawdown_cash_incl_total

  def drawdown_cash_incl_investor = money_sum(investor_remittances_incl, :computed_amount_cents)
  memoize :drawdown_cash_incl_investor

  def drawdown_cash_incl_investor_percent
    percentage(
      drawdown_cash_incl_investor.cents,
      drawdown_cash_incl_total.cents
    )
  end

  def drawdown_cash_incl_kyc = money_sum(kyc_remittances, :computed_amount_cents)
  memoize :drawdown_cash_incl_kyc

  def drawdown_cash_incl_kyc_percent = percentage(drawdown_cash_incl_kyc.cents, drawdown_cash_incl_total.cents)
  memoize :drawdown_cash_incl_kyc_percent

  # === Drawdown Fees ===
  # Capital Fees - Prior, Current, Including for LP, GP, Total
  def drawdown_fees_prior_lp = money_sum(fund_remittances_lp_prior, :capital_fee_cents)
  memoize :drawdown_fees_prior_lp

  def drawdown_fees_prior_gp = money_sum(fund_remittances_gp_prior, :capital_fee_cents)
  memoize :drawdown_fees_prior_gp

  def drawdown_fees_prior_total = drawdown_fees_prior_lp + drawdown_fees_prior_gp
  memoize :drawdown_fees_prior_total

  def drawdown_fees_prior_investor
    money_sum(investor_remittances_prior, :capital_fee_cents)
  end
  memoize :drawdown_fees_prior_investor

  def drawdown_fees_prior_investor_percent = percentage(drawdown_fees_prior_investor.cents, drawdown_fees_prior_total.cents)

  # Drawdown Fees of the KYC prior to notice date
  def drawdown_fees_prior_kyc = money_sum(kyc_remittances_prior, :capital_fee_cents)
  memoize :drawdown_fees_prior_kyc

  # Percentage of drawdown fees of the KYC prior to notice date
  def drawdown_fees_prior_kyc_percent = percentage(drawdown_fees_prior_kyc.cents, drawdown_fees_prior_total.cents)

  def drawdown_fees_curr_lp = money_sum(fund_remittances_lp_curr, :capital_fee_cents)
  memoize :drawdown_fees_curr_lp

  def drawdown_fees_curr_gp = money_sum(fund_remittances_gp_curr, :capital_fee_cents)
  memoize :drawdown_fees_curr_gp

  def drawdown_fees_curr_total = drawdown_fees_curr_lp + drawdown_fees_curr_gp
  memoize :drawdown_fees_curr_total

  def drawdown_fees_curr_investor
    if @capital_remittance.present?
      @capital_remittance.capital_fee
    else
      money_sum(investor_remittances_curr, :capital_fee_cents)
    end
  end

  def drawdown_fees_curr_investor_percent
    percentage(drawdown_fees_curr_investor, drawdown_fees_curr_total)
  end

  # Drawdown Fees on the current notice date for the KYC
  def drawdown_fees_curr_kyc
    money_sum(kyc_remittances_curr, :capital_fee_cents)
  end
  memoize :drawdown_fees_curr_kyc

  # Percentage of drawdown fees of the KYC on the current notice date
  def drawdown_fees_curr_kyc_percent
    percentage(drawdown_fees_curr_kyc.cents, drawdown_fees_curr_total.cents)
  end

  def drawdown_fees_incl_lp = money_sum(fund_remittances_lp, :capital_fee_cents)
  memoize :drawdown_fees_incl_lp

  def drawdown_fees_incl_gp = money_sum(fund_remittances_gp, :capital_fee_cents)
  memoize :drawdown_fees_incl_gp

  def drawdown_fees_incl_total = drawdown_fees_incl_lp + drawdown_fees_incl_gp
  memoize :drawdown_fees_incl_total

  def drawdown_fees_incl_investor = money_sum(investor_remittances_incl, :capital_fee_cents)
  memoize :drawdown_fees_incl_investor

  def drawdown_fees_incl_investor_percent = percentage(drawdown_fees_incl_investor.cents, drawdown_fees_incl_total.cents)

  def drawdown_fees_incl_kyc = money_sum(kyc_remittances, :capital_fee_cents)
  memoize :drawdown_fees_incl_kyc

  def drawdown_fees_incl_kyc_percent = percentage(drawdown_fees_incl_kyc.cents, drawdown_fees_incl_total.cents)

  # Drawdown Other fees

  # === Drawdown Fees ===
  # Capital Fees - Prior, Current, Including for LP, GP, Total
  def other_fees_prior_lp = money_sum(fund_remittances_lp_prior, :other_fee_cents)
  memoize :other_fees_prior_lp

  def other_fees_prior_gp = money_sum(fund_remittances_gp_prior, :other_fee_cents)
  memoize :other_fees_prior_gp

  def other_fees_prior_total = other_fees_prior_lp + other_fees_prior_gp
  memoize :other_fees_prior_total

  def other_fees_prior_investor
    money_sum(investor_remittances_prior, :other_fee_cents)
  end
  memoize :other_fees_prior_investor

  def other_fees_prior_investor_percent = percentage(other_fees_prior_investor.cents, other_fees_prior_total.cents)

  # Other Fees of the KYC prior to notice date
  def other_fees_prior_kyc = money_sum(kyc_remittances_prior, :other_fee_cents)
  memoize :other_fees_prior_kyc

  # Percentage of other fees of the KYC prior to notice date
  def other_fees_prior_kyc_percent = percentage(other_fees_prior_kyc.cents, other_fees_prior_total.cents)

  def other_fees_curr_lp = money_sum(fund_remittances_lp_curr, :other_fee_cents)
  memoize :other_fees_curr_lp

  def other_fees_curr_gp = money_sum(fund_remittances_gp_curr, :other_fee_cents)
  memoize :other_fees_curr_gp

  def other_fees_curr_total = other_fees_curr_lp + other_fees_curr_gp
  memoize :other_fees_curr_total

  def other_fees_curr_investor
    if @capital_remittance.present?
      @capital_remittance.other_fee
    else
      money_sum(investor_remittances_curr, :other_fee_cents)
    end
  end

  def other_fees_curr_investor_percent
    percentage(other_fees_curr_investor, other_fees_curr_total)
  end

  # Other Fees on the current notice date for the KYC
  def other_fees_curr_kyc
    money_sum(kyc_remittances_curr, :other_fee_cents)
  end
  memoize :other_fees_curr_kyc

  # Percentage of other fees of the KYC on the current notice date
  def other_fees_curr_kyc_percent
    percentage(other_fees_curr_kyc.cents, other_fees_curr_total.cents)
  end

  def other_fees_incl_lp = money_sum(fund_remittances_lp, :other_fee_cents)
  memoize :other_fees_incl_lp

  def other_fees_incl_gp = money_sum(fund_remittances_gp, :other_fee_cents)
  memoize :other_fees_incl_gp

  def other_fees_incl_total = other_fees_incl_lp + other_fees_incl_gp
  memoize :other_fees_incl_total

  def other_fees_incl_investor = money_sum(investor_remittances_incl, :other_fee_cents)
  memoize :other_fees_incl_investor

  def other_fees_incl_investor_percent = percentage(other_fees_incl_investor.cents, other_fees_incl_total.cents)

  def other_fees_incl_kyc = money_sum(kyc_remittances, :other_fee_cents)
  memoize :other_fees_incl_kyc

  def other_fees_incl_kyc_percent = percentage(other_fees_incl_kyc.cents, other_fees_incl_total.cents)

  # === Aggregate Drawdowns ===
  # Aggregate Drawdown (Call Amount) - Prior, Current, Including for LP, GP, Total
  # Aggregate Drawdown is the sum of drawdown cash and drawdown fees
  def agg_drawdown_prior_lp = money_sum(fund_remittances_lp_prior, :call_amount_cents)
  memoize :agg_drawdown_prior_lp

  def agg_drawdown_prior_gp = money_sum(fund_remittances_gp_prior, :call_amount_cents)
  memoize :agg_drawdown_prior_gp

  def agg_drawdown_prior_total = agg_drawdown_prior_lp + agg_drawdown_prior_gp
  memoize :agg_drawdown_prior_total

  def agg_drawdown_prior_investor = money_sum(investor_remittances_prior, :call_amount_cents)
  memoize :agg_drawdown_prior_investor

  # Percentage of Aggregate Drawdown of the investor prior to notice date
  def agg_drawdown_prior_investor_percent
    percentage(agg_drawdown_prior_investor.cents, agg_drawdown_prior_total.cents)
  end

  # Aggregate Drawdown of the KYC prior to notice date
  def agg_drawdown_prior_kyc = money_sum(kyc_remittances_prior, :call_amount_cents)
  memoize :agg_drawdown_prior_kyc

  # Percentage of Aggregate Drawdown of the KYC prior to notice date
  def agg_drawdown_prior_kyc_percent = percentage(agg_drawdown_prior_kyc.cents, agg_drawdown_prior_total.cents)

  def agg_drawdown_curr_lp = money_sum(fund_remittances_lp_curr, :call_amount_cents)
  memoize :agg_drawdown_curr_lp

  def agg_drawdown_curr_gp = money_sum(fund_remittances_gp_curr, :call_amount_cents)
  memoize :agg_drawdown_curr_gp

  def agg_drawdown_curr_total = agg_drawdown_curr_lp + agg_drawdown_curr_gp
  memoize :agg_drawdown_curr_total

  def agg_drawdown_curr_investor
    if @capital_remittance.present?
      @capital_remittance.call_amount
    else
      money_sum(investor_remittances_curr, :call_amount_cents)
    end
  end

  def agg_drawdown_curr_investor_percent
    percentage(agg_drawdown_curr_investor, agg_drawdown_curr_total)
  end

  def agg_drawdown_curr_kyc = money_sum(kyc_remittances_curr, :call_amount_cents)
  memoize :agg_drawdown_curr_kyc

  def agg_drawdown_curr_kyc_percent
    percentage(agg_drawdown_curr_kyc.cents, agg_drawdown_curr_total.cents)
  end

  def agg_drawdown_incl_lp = money_sum(fund_remittances_lp, :call_amount_cents)
  memoize :agg_drawdown_incl_lp

  def agg_drawdown_incl_gp = money_sum(fund_remittances_gp, :call_amount_cents)
  memoize :agg_drawdown_incl_gp

  def agg_drawdown_incl_total = agg_drawdown_incl_lp + agg_drawdown_incl_gp
  memoize :agg_drawdown_incl_total

  def agg_drawdown_incl_investor = money_sum(investor_remittances, :call_amount_cents)
  memoize :agg_drawdown_incl_investor

  def agg_drawdown_incl_investor_percent = percentage(agg_drawdown_incl_investor.cents, agg_drawdown_incl_total.cents)

  def agg_drawdown_incl_kyc = money_sum(kyc_remittances, :call_amount_cents)
  memoize :agg_drawdown_incl_kyc

  def agg_drawdown_incl_kyc_percent = percentage(agg_drawdown_incl_kyc.cents, agg_drawdown_incl_total.cents)

  # === Aggregate Drawdowns Total Due Amounts ===
  # Summation of call amount and other fees
  def agg_due_prior_lp = Money.new(fund_remittances_lp_prior.sum(DUE_AMOUNT_SQL), @currency)
  memoize :agg_due_prior_lp

  def agg_due_prior_gp = Money.new(fund_remittances_gp_prior.sum(DUE_AMOUNT_SQL), @currency)
  memoize :agg_due_prior_gp

  def agg_due_prior_total = agg_due_prior_lp + agg_due_prior_gp
  memoize :agg_due_prior_total

  def agg_due_prior_investor = Money.new(investor_remittances_prior.sum(DUE_AMOUNT_SQL), @currency)
  memoize :agg_due_prior_investor

  # Percentage of Aggregate Drawdown of the investor prior to notice date
  def agg_due_prior_investor_percent
    percentage(agg_due_prior_investor.cents, agg_due_prior_total.cents)
  end

  # Aggregate Drawdown of the KYC prior to notice date
  def agg_due_prior_kyc = Money.new(kyc_remittances_prior.sum(DUE_AMOUNT_SQL), @currency)
  memoize :agg_due_prior_kyc

  # Percentage of Aggregate Drawdown of the KYC prior to notice date
  def agg_due_prior_kyc_percent = percentage(agg_due_prior_kyc.cents, agg_due_prior_total.cents)

  def agg_due_curr_lp = Money.new(fund_remittances_lp_curr.sum(DUE_AMOUNT_SQL), @currency)
  memoize :agg_due_curr_lp

  def agg_due_curr_gp = Money.new(fund_remittances_gp_curr.sum(DUE_AMOUNT_SQL), @currency)
  memoize :agg_due_curr_gp

  def agg_due_curr_total = agg_due_curr_lp + agg_due_curr_gp
  memoize :agg_due_curr_total

  def agg_due_curr_investor = Money.new(investor_remittances_curr.sum(DUE_AMOUNT_SQL), @currency)

  def agg_due_curr_investor_percent
    percentage(agg_due_curr_investor, agg_due_curr_total)
  end

  def agg_due_curr_kyc = Money.new(kyc_remittances_curr.sum(DUE_AMOUNT_SQL), @currency)
  memoize :agg_due_curr_kyc

  def agg_due_curr_kyc_percent
    percentage(agg_due_curr_kyc.cents, agg_due_curr_total.cents)
  end

  # Aggregate Due amounts including current notice date
  def agg_due_incl_lp = Money.new(fund_remittances_lp.sum(DUE_AMOUNT_SQL), @currency)
  memoize :agg_due_incl_lp

  def agg_due_incl_gp = Money.new(fund_remittances_gp.sum(DUE_AMOUNT_SQL), @currency)
  memoize :agg_due_incl_gp

  def agg_due_incl_total = agg_due_incl_lp + agg_due_incl_gp
  memoize :agg_due_incl_total

  def agg_due_incl_investor = Money.new(investor_remittances.sum(DUE_AMOUNT_SQL), @currency)
  memoize :agg_due_incl_investor

  def agg_due_incl_investor_percent = percentage(agg_due_incl_investor.cents, agg_due_incl_total.cents)

  def agg_due_incl_kyc = Money.new(kyc_remittances.sum(DUE_AMOUNT_SQL), @currency)
  memoize :agg_due_incl_kyc

  def agg_due_incl_kyc_percent = percentage(agg_due_incl_kyc.cents, agg_due_incl_total.cents)

  # === Aggregated Distribution & Reinvestment Prior / Current / Incl Notice Date ===
  def agg_dist_prior_lp = Money.new(fund_dist_payments_lp_prior.sum(DIST_CASH_SQL), @currency)
  memoize :agg_dist_prior_lp

  def agg_dist_prior_gp = Money.new(fund_dist_payments_gp_prior.sum(DIST_CASH_SQL), @currency)
  memoize :agg_dist_prior_gp

  def agg_dist_prior_total = agg_dist_prior_lp + agg_dist_prior_gp
  memoize :agg_dist_prior_total

  def agg_dist_prior_investor = Money.new(dist_payments.where(payment_date: ..@yesterday_end_of_day).sum(DIST_CASH_SQL), @currency)
  memoize :agg_dist_prior_investor

  # Percentage of distribution cash of the investor prior to the notice date
  def agg_dist_prior_investor_percent = percentage(agg_dist_prior_investor.cents, agg_dist_prior_total.cents)

  # Distribution Cash amount of the KYC prior to notice date
  def agg_dist_prior_kyc
    Money.new(
      kyc_dist_payments.where(payment_date: ..@yesterday_end_of_day).sum(DIST_CASH_SQL),
      @currency
    )
  end
  memoize :agg_dist_prior_kyc

  # Percentage of distribution cash of the KYC prior to the notice date
  def agg_dist_prior_kyc_percent = percentage(agg_dist_prior_kyc.cents, agg_dist_prior_total.cents)

  # Current Notice Date
  def agg_dist_curr_lp = Money.new(fund_dist_payments_lp_curr.sum(DIST_CASH_SQL), @currency)
  memoize :agg_dist_curr_lp

  def agg_dist_curr_gp = Money.new(fund_dist_payments_gp_curr.sum(DIST_CASH_SQL), @currency)
  memoize :agg_dist_curr_gp

  def agg_dist_curr_total = agg_dist_curr_lp + agg_dist_curr_gp
  memoize :agg_dist_curr_total

  def agg_dist_curr_investor = Money.new(dist_payments.where(payment_date: @as_of_date).sum(DIST_CASH_SQL), @currency)
  memoize :agg_dist_curr_investor

  # Percentage of distribution cash of the investor on the notice date
  def agg_dist_curr_investor_percent = percentage(agg_dist_curr_investor.cents, agg_dist_curr_total.cents)

  # Distribution Cash amount of the KYC on the notice date
  def agg_dist_curr_kyc = Money.new(kyc_dist_payments.where(payment_date: @as_of_date).sum(DIST_CASH_SQL), @currency)
  memoize :agg_dist_curr_kyc

  # Percentage of distribution cash of the KYC on the notice date
  def agg_dist_curr_kyc_percent = percentage(agg_dist_curr_kyc.cents, agg_dist_curr_total.cents)

  # Including Current Notice Date
  def agg_dist_incl_lp = Money.new(fund_dist_payments_lp.sum(DIST_CASH_SQL), @currency)
  memoize :agg_dist_incl_lp

  def agg_dist_incl_gp = Money.new(fund_dist_payments_gp.sum(DIST_CASH_SQL), @currency)
  memoize :agg_dist_incl_gp

  def agg_dist_incl_total = agg_dist_incl_lp + agg_dist_incl_gp
  memoize :agg_dist_incl_total

  def agg_dist_incl_investor = Money.new(dist_payments.sum(DIST_CASH_SQL), @currency)
  memoize :agg_dist_incl_investor

  # Percentage of distribution cash of the investor including the notice date
  def agg_dist_incl_investor_percent = percentage(agg_dist_incl_investor.cents, agg_dist_incl_total.cents)

  # Distribution Cash amount of the KYC including the notice date
  alias agg_dist_incl_kyc dist_cash_kyc

  # Percentage of distribution cash of the KYC including the notice date
  def agg_dist_incl_kyc_percent = percentage(agg_dist_incl_kyc.cents, agg_dist_incl_total.cents)

  # === Reinvestment Prior / Curr / Incl ===
  # Reinvestments - Prior, Current, Including for LP, GP, Total
  def agg_reinvest_prior_lp = money_sum(fund_dist_payments_lp_prior, :reinvestment_with_fees_cents)
  memoize :agg_reinvest_prior_lp

  def agg_reinvest_prior_gp = money_sum(fund_dist_payments_gp_prior, :reinvestment_with_fees_cents)
  memoize :agg_reinvest_prior_gp

  def agg_reinvest_prior_total = agg_reinvest_prior_lp + agg_reinvest_prior_gp
  memoize :agg_reinvest_prior_total

  def agg_reinvest_prior_investor = money_sum(dist_payments.where(payment_date: ..@yesterday_end_of_day), :reinvestment_with_fees_cents)
  memoize :agg_reinvest_prior_investor

  # Percentage of reinvestment amount of the investor prior to the notice date
  def agg_reinvest_prior_investor_percent = percentage(agg_reinvest_prior_investor.cents, agg_reinvest_prior_total.cents)

  # Reinvestment amount of the KYC prior to notice date
  def agg_reinvest_prior_kyc
    money_sum(kyc_dist_payments.where(payment_date: ..@yesterday_end_of_day), :reinvestment_with_fees_cents)
  end
  memoize :agg_reinvest_prior_kyc

  # Percentage of reinvestment amount of the KYC prior to the notice date
  def agg_reinvest_prior_kyc_percent = percentage(agg_reinvest_prior_kyc.cents, agg_reinvest_prior_total.cents)

  # Current Notice Date
  def agg_reinvest_curr_lp = money_sum(fund_dist_payments_lp_curr, :reinvestment_with_fees_cents)
  memoize :agg_reinvest_curr_lp

  def agg_reinvest_curr_gp = money_sum(fund_dist_payments_gp_curr, :reinvestment_with_fees_cents)
  memoize :agg_reinvest_curr_gp

  def agg_reinvest_curr_total = agg_reinvest_curr_lp + agg_reinvest_curr_gp
  memoize :agg_reinvest_curr_total

  def agg_reinvest_curr_investor = money_sum(dist_payments.where(payment_date: @as_of_date), :reinvestment_with_fees_cents)
  memoize :agg_reinvest_curr_investor

  def agg_reinvest_curr_investor_percent = percentage(agg_reinvest_curr_investor.cents, agg_reinvest_curr_total.cents)

  # Reinvestment amount of the KYC on the notice date
  def agg_reinvest_curr_kyc
    money_sum(kyc_dist_payments.where(payment_date: @as_of_date), :reinvestment_with_fees_cents)
  end
  memoize :agg_reinvest_curr_kyc

  # Percentage of reinvestment amount of the KYC on the notice date
  def agg_reinvest_curr_kyc_percent = percentage(agg_reinvest_curr_kyc.cents, agg_reinvest_curr_total.cents)

  # Including Current Notice Date
  def agg_reinvest_incl_lp = money_sum(fund_dist_payments_lp, :reinvestment_with_fees_cents)
  memoize :agg_reinvest_incl_lp

  def agg_reinvest_incl_gp = money_sum(fund_dist_payments_gp, :reinvestment_with_fees_cents)
  memoize :agg_reinvest_incl_gp

  def agg_reinvest_incl_total = agg_reinvest_incl_lp + agg_reinvest_incl_gp
  memoize :agg_reinvest_incl_total

  alias agg_reinvest_incl_investor committed_reinvest_investor

  def agg_reinvest_incl_investor_percent = percentage(agg_reinvest_incl_investor.cents, agg_reinvest_incl_total.cents)

  alias agg_reinvest_incl_kyc committed_reinvest_kyc

  def agg_reinvest_incl_kyc_percent = percentage(agg_reinvest_incl_kyc.cents, agg_reinvest_incl_total.cents)

  # === Undrawn Commitments ===
  # Undrawn Amount is the difference between the committed amount and the drawdown amount
  def undrawn_comm_prior_lp
    committed_cash_lp - agg_drawdown_prior_lp
  end
  memoize :undrawn_comm_prior_lp

  def undrawn_comm_prior_gp
    committed_cash_gp - agg_drawdown_prior_gp
  end
  memoize :undrawn_comm_prior_gp

  def undrawn_comm_prior_total = undrawn_comm_prior_lp + undrawn_comm_prior_gp
  memoize :undrawn_comm_prior_total

  def undrawn_comm_prior_investor
    if @capital_remittance.present?
      @capital_remittance.committed_amount - agg_drawdown_prior_investor
    else
      # all before payment date - committed amount from last before payment date
      # latest comm amount before this date
      committed_amount = investor_remittances.order(:remittance_date).last&.committed_amount || Money.new(0, @currency)
      committed_amount - agg_drawdown_prior_investor
    end
  end

  def undrawn_comm_prior_investor_percent
    percentage(undrawn_comm_prior_investor, undrawn_comm_prior_total)
  end

  def undrawn_comm_prior_kyc
    # committed amt accross all remittance where kyc is common of the CURRENT CALL
    if @capital_remittance.present?
      money_sum(kyc_remittances.where(capital_call_id: @capital_remittance.capital_call_id), :committed_amount_cents) - agg_drawdown_prior_kyc
    else
      latest_remitance = kyc_remittances.order(:remittance_date).last
      latest_call_remittances = kyc_remittances.where(capital_call_id: latest_remitance&.capital_call_id)
      money_sum(latest_call_remittances, :committed_amount_cents) - agg_drawdown_prior_kyc
    end
  end

  def undrawn_comm_prior_kyc_percent
    percentage(undrawn_comm_prior_kyc, undrawn_comm_prior_total)
  end

  # Current Notice Date
  def undrawn_comm_curr_lp
    committed_cash_lp - money_sum(fund_remittances_lp, :call_amount_cents)
  end
  memoize :undrawn_comm_curr_lp

  def undrawn_comm_curr_gp
    committed_cash_gp - money_sum(fund_remittances_gp, :call_amount_cents)
  end
  memoize :undrawn_comm_curr_gp

  def undrawn_comm_curr_total = undrawn_comm_curr_lp + undrawn_comm_curr_gp
  memoize :undrawn_comm_curr_total

  def undrawn_comm_curr_investor
    if @capital_remittance.present?
      @capital_remittance.committed_amount - agg_drawdown_incl_investor
    else
      committed_amount = investor_remittances.order(:remittance_date).last&.committed_amount || Money.new(0, @currency)
      committed_amount - agg_drawdown_incl_investor
    end
  end
  memoize :undrawn_comm_curr_investor

  def undrawn_comm_curr_investor_percent
    percentage(undrawn_comm_curr_investor, undrawn_comm_curr_total)
  end
  memoize :undrawn_comm_curr_investor_percent

  def undrawn_comm_curr_kyc
    if @capital_remittance.present?
      money_sum(kyc_remittances.where(capital_call_id: @capital_remittance.capital_call_id), :committed_amount_cents) - agg_drawdown_incl_investor
    else
      latest_remitance = kyc_remittances.order(:remittance_date).last
      latest_call_remittances = kyc_remittances.where(capital_call_id: latest_remitance&.capital_call_id)
      money_sum(latest_call_remittances, :committed_amount_cents) - agg_drawdown_incl_kyc
    end
  end
  memoize :undrawn_comm_curr_kyc

  def undrawn_comm_curr_kyc_percent
    percentage(undrawn_comm_curr_kyc, undrawn_comm_curr_total)
  end
  memoize :undrawn_comm_curr_kyc_percent

  # Including Current Notice Date
  # Undrawn Commitment INCLUDING current notice date are the same as the current notice date amounts
  alias undrawn_comm_incl_lp undrawn_comm_curr_lp
  alias undrawn_comm_incl_gp undrawn_comm_curr_gp
  alias undrawn_comm_incl_total undrawn_comm_curr_total
  alias undrawn_comm_incl_investor undrawn_comm_curr_investor
  alias undrawn_comm_incl_investor_percent undrawn_comm_curr_investor_percent
  alias undrawn_comm_incl_kyc undrawn_comm_curr_kyc
  alias undrawn_comm_incl_kyc_percent undrawn_comm_curr_kyc_percent

  def kyc_commitments = fund_as_of.capital_commitments.where(investor_kyc_id: @capital_commitment.investor_kyc_id)
  memoize :kyc_commitments

  def kyc_remittances = fund_as_of.capital_remittances.joins(:capital_commitment).merge(kyc_commitments).where(remittance_date: ..@as_of_date)
  memoize :kyc_remittances

  def kyc_remittances_prior = kyc_remittances.where(remittance_date: ..@yesterday_end_of_day, capital_call_id: prior_calls.select(:id))
  memoize :kyc_remittances_prior

  def kyc_remittances_curr
    if @capital_remittance.present?
      kyc_remittances.where(remittance_date: @as_of_date, capital_call_id: @capital_remittance.capital_call_id)
    else
      kyc_remittances.where(remittance_date: @as_of_date)
    end
  end
  memoize :kyc_remittances_curr

  # Investor (commitment-specific) remittance scopes
  # investor_ prefix here is filtering using commitment_id, and one commitment will have only one remittance per call, so investor_remittances will return @capital_remittance
  def investor_remittances = fund_as_of.capital_remittances.where(capital_commitment_id: @capital_commitment.id)
  memoize :investor_remittances

  def investor_remittances_prior = investor_remittances.where(remittance_date: ..@yesterday_end_of_day, capital_call_id: prior_calls.select(:id))
  memoize :investor_remittances_prior

  def investor_remittances_curr
    if @capital_remittance.present?
      investor_remittances.where(remittance_date: @as_of_date, capital_call_id: @capital_remittance.capital_call_id)
    else
      investor_remittances.where(remittance_date: @as_of_date)
    end
  end
  memoize :investor_remittances_curr

  def investor_remittances_incl = investor_remittances.where(remittance_date: ..@as_of_date)
  memoize :investor_remittances_incl

  # ===== Unpaid amounts =====
  #  Unpaid prior to current notice
  def unpaid_prior_lp = agg_drawdown_prior_lp - collected_prior_lp
  memoize :unpaid_prior_lp

  def unpaid_prior_gp = agg_drawdown_prior_gp - collected_prior_gp
  memoize :unpaid_prior_gp

  def unpaid_prior_total = unpaid_prior_lp + unpaid_prior_gp
  memoize :unpaid_prior_total

  def unpaid_prior_investor
    agg_drawdown_prior_investor - collected_prior_investor
  end
  memoize :unpaid_prior_investor

  def unpaid_prior_investor_percent = percentage(unpaid_prior_investor, unpaid_prior_total)

  def unpaid_prior_kyc
    agg_drawdown_prior_kyc - collected_prior_kyc
  end
  memoize :unpaid_prior_kyc

  def unpaid_prior_kyc_percent = percentage(unpaid_prior_kyc, unpaid_prior_total)

  # Unpaid for current notice
  def unpaid_curr_lp = agg_drawdown_curr_lp - collected_curr_lp
  memoize :unpaid_curr_lp

  def unpaid_curr_gp = agg_drawdown_curr_gp - collected_curr_gp
  memoize :unpaid_curr_gp

  def unpaid_curr_total = unpaid_curr_lp + unpaid_curr_gp
  memoize :unpaid_curr_total

  def unpaid_curr_investor
    money_sum(investor_remittances_curr, :call_amount_cents) - collected_curr_investor
  end
  memoize :unpaid_curr_investor

  def unpaid_curr_investor_percent = percentage(unpaid_curr_investor, unpaid_curr_total)

  def unpaid_curr_kyc
    agg_drawdown_curr_kyc - collected_curr_kyc
  end
  memoize :unpaid_curr_kyc

  def unpaid_curr_kyc_percent = percentage(unpaid_curr_kyc, unpaid_curr_total)

  # Unpaid including current notice
  def unpaid_incl_lp
    agg_drawdown_incl_lp - collected_incl_lp
  end
  memoize :unpaid_incl_lp

  def unpaid_incl_gp
    agg_drawdown_incl_gp - collected_incl_gp
  end
  memoize :unpaid_incl_gp

  def unpaid_incl_total = unpaid_incl_lp + unpaid_incl_gp
  memoize :unpaid_incl_total

  def unpaid_incl_investor
    money_sum(investor_remittances_incl, :call_amount_cents) - collected_incl_investor
  end
  memoize :unpaid_incl_investor

  def unpaid_incl_investor_percent = percentage(unpaid_incl_investor, unpaid_incl_total)

  def unpaid_incl_kyc
    money_sum(kyc_remittances, :call_amount_cents) - collected_incl_kyc
  end
  memoize :unpaid_incl_kyc

  def unpaid_incl_kyc_percent = percentage(unpaid_incl_kyc, unpaid_incl_total)

  # ===== Unpaid from due amounts =====
  #  Unpaid prior to current notice
  def unpaid_due_prior_lp = agg_due_prior_lp - collected_prior_lp
  memoize :unpaid_due_prior_lp

  def unpaid_due_prior_gp = agg_due_prior_gp - collected_prior_gp
  memoize :unpaid_due_prior_gp

  def unpaid_due_prior_total = unpaid_due_prior_lp + unpaid_due_prior_gp
  memoize :unpaid_due_prior_total

  def unpaid_due_prior_investor
    agg_due_prior_investor - collected_prior_investor
  end
  memoize :unpaid_due_prior_investor

  def unpaid_due_prior_investor_percent = percentage(unpaid_due_prior_investor, unpaid_due_prior_total)

  def unpaid_due_prior_kyc
    agg_due_prior_kyc - collected_prior_kyc
  end
  memoize :unpaid_due_prior_kyc

  def unpaid_due_prior_kyc_percent = percentage(unpaid_due_prior_kyc, unpaid_due_prior_total)

  # Unpaid for current notice
  def unpaid_due_curr_lp = agg_due_curr_lp - collected_curr_lp
  memoize :unpaid_due_curr_lp

  def unpaid_due_curr_gp = agg_due_curr_gp - collected_curr_gp
  memoize :unpaid_due_curr_gp

  def unpaid_due_curr_total = unpaid_due_curr_lp + unpaid_due_curr_gp
  memoize :unpaid_due_curr_total

  def unpaid_due_curr_investor
    agg_due_curr_investor - collected_curr_investor
  end
  memoize :unpaid_due_curr_investor

  def unpaid_due_curr_investor_percent = percentage(unpaid_due_curr_investor, unpaid_due_curr_total)

  def unpaid_due_curr_kyc
    agg_due_curr_kyc - collected_curr_kyc
  end
  memoize :unpaid_due_curr_kyc

  def unpaid_due_curr_kyc_percent = percentage(unpaid_due_curr_kyc, unpaid_due_curr_total)

  # Unpaid including current notice
  def unpaid_due_incl_lp
    agg_due_incl_lp - collected_incl_lp
  end
  memoize :unpaid_due_incl_lp

  def unpaid_due_incl_gp
    agg_due_incl_gp - collected_incl_gp
  end
  memoize :unpaid_due_incl_gp

  def unpaid_due_incl_total = unpaid_due_incl_lp + unpaid_due_incl_gp
  memoize :unpaid_due_incl_total

  def unpaid_due_incl_investor
    agg_due_incl_investor - collected_incl_investor
  end
  memoize :unpaid_due_incl_investor

  def unpaid_due_incl_investor_percent = percentage(unpaid_due_incl_investor, unpaid_due_incl_total)

  def unpaid_due_incl_kyc
    agg_due_incl_kyc - collected_incl_kyc
  end
  memoize :unpaid_due_incl_kyc

  def unpaid_due_incl_kyc_percent = percentage(unpaid_due_incl_kyc, unpaid_due_incl_total)

  # === Aggregate Collected Amount ===
  # Aggregate Collected prior to current notice
  def collected_prior_lp = money_sum(fund_remittances_lp_prior, :collected_amount_cents)
  memoize :collected_prior_lp

  def collected_prior_gp = money_sum(fund_remittances_gp_prior, :collected_amount_cents)
  memoize :collected_prior_gp

  def collected_prior_total = collected_prior_lp + collected_prior_gp
  memoize :collected_prior_total

  def collected_prior_investor
    money_sum(investor_remittances_prior, :collected_amount_cents)
  end
  memoize :collected_prior_investor

  def collected_prior_investor_percent = percentage(collected_prior_investor, collected_prior_total)

  def collected_prior_kyc = money_sum(kyc_remittances_prior, :collected_amount_cents)
  memoize :collected_prior_kyc

  def collected_prior_kyc_percent = percentage(collected_prior_kyc, collected_prior_total)

  # Aggregate Collected for the current notice
  def collected_curr_lp = money_sum(fund_remittances_lp_curr, :collected_amount_cents)
  memoize :collected_curr_lp

  def collected_curr_gp = money_sum(fund_remittances_gp_curr, :collected_amount_cents)
  memoize :collected_curr_gp

  def collected_curr_total = collected_curr_lp + collected_curr_gp
  memoize :collected_curr_total

  def collected_curr_investor
    money_sum(investor_remittances_curr, :collected_amount_cents)
  end
  memoize :collected_curr_investor

  def collected_curr_investor_percent = percentage(collected_curr_investor, collected_curr_total)

  def collected_curr_kyc
    money_sum(kyc_remittances_curr, :collected_amount_cents)
  end
  memoize :collected_curr_kyc

  def collected_curr_kyc_percent = percentage(collected_curr_kyc, collected_curr_total)

  # Aggregate Collected including current notice

  def collected_incl_lp
    money_sum(fund_remittances_lp, :collected_amount_cents)
  end
  memoize :collected_incl_lp

  # Aggregate Collected including current notice for GP
  def collected_incl_gp
    money_sum(fund_remittances_gp, :collected_amount_cents)
  end
  memoize :collected_incl_gp

  # Total Aggregate Collected including current notice
  def collected_incl_total = collected_incl_lp + collected_incl_gp
  memoize :collected_incl_total

  # Aggregate Collected including current notice for the investor
  def collected_incl_investor
    money_sum(investor_remittances_incl, :collected_amount_cents)
  end
  memoize :collected_incl_investor

  # Percentage of Aggregate Collected including current notice for the investor
  def collected_incl_investor_percent = percentage(collected_incl_investor, collected_incl_total)

  # Aggregate Collected including current notice for the KYC
  def collected_incl_kyc = money_sum(kyc_remittances, :collected_amount_cents)
  memoize :collected_incl_kyc

  # Percentage of Aggregate Collected including current notice for the KYC
  def collected_incl_kyc_percent = percentage(collected_incl_kyc, collected_incl_total)

  # ###########################DISTRIBUTION NOTICE FIELDS############################
  # === INCOME ===

  # PRIOR
  def dist_income_prior_lp = money_sum(fund_dist_payments_lp_prior, :income_with_fees_cents)
  memoize :dist_income_prior_lp

  def dist_income_prior_gp = money_sum(fund_dist_payments_gp_prior, :income_with_fees_cents)
  memoize :dist_income_prior_gp

  def dist_income_prior_total = dist_income_prior_lp + dist_income_prior_gp
  memoize :dist_income_prior_total

  def dist_income_prior_investor = money_sum(comm_dist_payments_prior, :income_with_fees_cents)
  memoize :dist_income_prior_investor

  def dist_income_prior_investor_percent = percentage(dist_income_prior_investor, dist_income_prior_total)

  def dist_income_prior_kyc = money_sum(kyc_dist_payments_prior, :income_with_fees_cents)
  memoize :dist_income_prior_kyc

  def dist_income_prior_kyc_percent = percentage(dist_income_prior_kyc, dist_income_prior_total)

  # CURRENT
  def dist_income_curr_lp = money_sum(fund_dist_payments_lp_curr, :income_with_fees_cents)
  memoize :dist_income_curr_lp

  def dist_income_curr_gp = money_sum(fund_dist_payments_gp_curr, :income_with_fees_cents)
  memoize :dist_income_curr_gp

  def dist_income_curr_total = dist_income_curr_lp + dist_income_curr_gp
  memoize :dist_income_curr_total

  def dist_income_curr_investor = money_sum(comm_dist_payments_curr, :income_with_fees_cents)
  memoize :dist_income_curr_investor

  def dist_income_curr_investor_percent = percentage(dist_income_curr_investor, dist_income_curr_total)

  def dist_income_curr_kyc = money_sum(kyc_dist_payments_curr, :income_with_fees_cents)
  memoize :dist_income_curr_kyc

  def dist_income_curr_kyc_percent = percentage(dist_income_curr_kyc, dist_income_curr_total)

  # INCLUDING Current Notice Date
  def dist_income_incl_lp = money_sum(fund_dist_payments_lp, :income_with_fees_cents)
  memoize :dist_income_incl_lp

  def dist_income_incl_gp = money_sum(fund_dist_payments_gp, :income_with_fees_cents)
  memoize :dist_income_incl_gp

  def dist_income_incl_total = dist_income_incl_lp + dist_income_incl_gp
  memoize :dist_income_incl_total

  def dist_income_incl_investor = money_sum(comm_dist_payments, :income_with_fees_cents)
  memoize :dist_income_incl_investor

  def dist_income_incl_investor_percent = percentage(dist_income_incl_investor, dist_income_incl_total)

  def dist_income_incl_kyc = money_sum(kyc_dist_payments, :income_with_fees_cents)
  memoize :dist_income_incl_kyc

  def dist_income_incl_kyc_percent = percentage(dist_income_incl_kyc, dist_income_incl_total)

  # === Face Value for Rededmption ===
  # === Cost of Investment with fees ===

  # PRIOR
  def dist_fvr_prior_lp = money_sum(fund_dist_payments_lp_prior, :cost_of_investment_with_fees_cents)
  memoize :dist_fvr_prior_lp

  def dist_fvr_prior_gp = money_sum(fund_dist_payments_gp_prior, :cost_of_investment_with_fees_cents)
  memoize :dist_fvr_prior_gp

  def dist_fvr_prior_total = dist_fvr_prior_lp + dist_fvr_prior_gp
  memoize :dist_fvr_prior_total

  def dist_fvr_prior_investor = money_sum(comm_dist_payments_prior, :cost_of_investment_with_fees_cents)
  memoize :dist_fvr_prior_investor

  def dist_fvr_prior_investor_percent = percentage(dist_fvr_prior_investor, dist_fvr_prior_total)

  def dist_fvr_prior_kyc = money_sum(kyc_dist_payments_prior, :cost_of_investment_with_fees_cents)
  memoize :dist_fvr_prior_kyc

  def dist_fvr_prior_kyc_percent = percentage(dist_fvr_prior_kyc, dist_fvr_prior_total)

  # CURRENT

  def dist_fvr_curr_lp = money_sum(fund_dist_payments_lp_curr, :cost_of_investment_with_fees_cents)
  memoize :dist_fvr_curr_lp

  def dist_fvr_curr_gp = money_sum(fund_dist_payments_gp_curr, :cost_of_investment_with_fees_cents)
  memoize :dist_fvr_curr_gp

  def dist_fvr_curr_total = dist_fvr_curr_lp + dist_fvr_curr_gp
  memoize :dist_fvr_curr_total

  def dist_fvr_curr_investor = money_sum(comm_dist_payments_curr, :cost_of_investment_with_fees_cents)
  memoize :dist_fvr_curr_investor

  def dist_fvr_curr_investor_percent = percentage(dist_fvr_curr_investor, dist_fvr_curr_total)

  def dist_fvr_curr_kyc = money_sum(kyc_dist_payments_curr, :cost_of_investment_with_fees_cents)
  memoize :dist_fvr_curr_kyc

  def dist_fvr_curr_kyc_percent = percentage(dist_fvr_curr_kyc, dist_fvr_curr_total)

  # INCLUDING Current Notice Date
  def dist_fvr_incl_lp = money_sum(fund_dist_payments_lp, :cost_of_investment_with_fees_cents)
  memoize :dist_fvr_incl_lp

  def dist_fvr_incl_gp = money_sum(fund_dist_payments_gp, :cost_of_investment_with_fees_cents)
  memoize :dist_fvr_incl_gp

  def dist_fvr_incl_total = dist_fvr_incl_lp + dist_fvr_incl_gp
  memoize :dist_fvr_incl_total

  def dist_fvr_incl_investor = money_sum(comm_dist_payments, :cost_of_investment_with_fees_cents)
  memoize :dist_fvr_incl_investor

  def dist_fvr_incl_investor_percent = percentage(dist_fvr_incl_investor, dist_fvr_incl_total)

  def dist_fvr_incl_kyc = money_sum(kyc_dist_payments, :cost_of_investment_with_fees_cents)
  memoize :dist_fvr_incl_kyc

  def dist_fvr_incl_kyc_percent = percentage(dist_fvr_incl_kyc, dist_fvr_incl_total)

  # === Reinvestment with fees ===
  # we can use agg_reinvest amounts here

  # ============ Net Payable ===========

  # PRIOR
  def dist_net_prior_lp = money_sum(fund_dist_payments_lp_prior, :net_payable_cents)
  memoize :dist_net_prior_lp

  def dist_net_prior_gp = money_sum(fund_dist_payments_gp_prior, :net_payable_cents)
  memoize :dist_net_prior_gp

  def dist_net_prior_total = dist_net_prior_lp + dist_net_prior_gp
  memoize :dist_net_prior_total

  def dist_net_prior_investor = money_sum(comm_dist_payments_prior, :net_payable_cents)
  memoize :dist_net_prior_investor

  def dist_net_prior_investor_percent = percentage(dist_net_prior_investor, dist_net_prior_total)

  def dist_net_prior_kyc = money_sum(kyc_dist_payments_prior, :net_payable_cents)
  memoize :dist_net_prior_kyc

  def dist_net_prior_kyc_percent = percentage(dist_net_prior_kyc, dist_net_prior_total)

  # CURRENT
  def dist_net_curr_lp = money_sum(fund_dist_payments_lp_curr, :net_payable_cents)
  memoize :dist_net_curr_lp

  def dist_net_curr_gp = money_sum(fund_dist_payments_gp_curr, :net_payable_cents)
  memoize :dist_net_curr_gp

  def dist_net_curr_total = dist_net_curr_lp + dist_net_curr_gp
  memoize :dist_net_curr_total

  def dist_net_curr_investor = money_sum(comm_dist_payments_curr, :net_payable_cents)
  memoize :dist_net_curr_investor

  def dist_net_curr_investor_percent = percentage(dist_net_curr_investor, dist_net_curr_total)

  def dist_net_curr_kyc = money_sum(kyc_dist_payments_curr, :net_payable_cents)
  memoize :dist_net_curr_kyc

  def dist_net_curr_kyc_percent = percentage(dist_net_curr_kyc, dist_net_curr_total)

  # INCLUDING Current Notice Date
  def dist_net_incl_lp = money_sum(fund_dist_payments_lp, :net_payable_cents)
  memoize :dist_net_incl_lp

  def dist_net_incl_gp = money_sum(fund_dist_payments_gp, :net_payable_cents)
  memoize :dist_net_incl_gp

  def dist_net_incl_total = dist_net_incl_lp + dist_net_incl_gp
  memoize :dist_net_incl_total

  def dist_net_incl_investor = money_sum(comm_dist_payments, :net_payable_cents)
  memoize :dist_net_incl_investor

  def dist_net_incl_investor_percent = percentage(dist_net_incl_investor, dist_net_incl_total)

  def dist_net_incl_kyc = money_sum(kyc_dist_payments, :net_payable_cents)
  memoize :dist_net_incl_kyc

  def dist_net_incl_kyc_percent = percentage(dist_net_incl_kyc, dist_net_incl_total)

  # ================== Gross Payable ==================

  # PRIOR
  def dist_gross_prior_lp = money_sum(fund_dist_payments_lp_prior, :gross_payable_cents)
  memoize :dist_gross_prior_lp

  def dist_gross_prior_gp = money_sum(fund_dist_payments_gp_prior, :gross_payable_cents)
  memoize :dist_gross_prior_gp

  def dist_gross_prior_total = dist_gross_prior_lp + dist_gross_prior_gp
  memoize :dist_gross_prior_total

  def dist_gross_prior_investor = money_sum(comm_dist_payments_prior, :gross_payable_cents)
  memoize :dist_gross_prior_investor

  def dist_gross_prior_investor_percent = percentage(dist_gross_prior_investor, dist_gross_prior_total)

  def dist_gross_prior_kyc = money_sum(kyc_dist_payments_prior, :gross_payable_cents)
  memoize :dist_gross_prior_kyc

  def dist_gross_prior_kyc_percent = percentage(dist_gross_prior_kyc, dist_gross_prior_total)

  # CURRENT
  def dist_gross_curr_lp = money_sum(fund_dist_payments_lp_curr, :gross_payable_cents)
  memoize :dist_gross_curr_lp

  def dist_gross_curr_gp = money_sum(fund_dist_payments_gp_curr, :gross_payable_cents)
  memoize :dist_gross_curr_gp

  def dist_gross_curr_total = dist_gross_curr_lp + dist_gross_curr_gp
  memoize :dist_gross_curr_total

  def dist_gross_curr_investor = money_sum(comm_dist_payments_curr, :gross_payable_cents)
  memoize :dist_gross_curr_investor

  def dist_gross_curr_investor_percent = percentage(dist_gross_curr_investor, dist_gross_curr_total)

  def dist_gross_curr_kyc = money_sum(kyc_dist_payments_curr, :gross_payable_cents)
  memoize :dist_gross_curr_kyc

  def dist_gross_curr_kyc_percent = percentage(dist_gross_curr_kyc, dist_gross_curr_total)

  # INCLUDING Current Notice Date
  def dist_gross_incl_lp = money_sum(fund_dist_payments_lp, :gross_payable_cents)
  memoize :dist_gross_incl_lp

  def dist_gross_incl_gp = money_sum(fund_dist_payments_gp, :gross_payable_cents)
  memoize :dist_gross_incl_gp

  def dist_gross_incl_total = dist_gross_incl_lp + dist_gross_incl_gp
  memoize :dist_gross_incl_total

  def dist_gross_incl_investor = money_sum(comm_dist_payments, :gross_payable_cents)
  memoize :dist_gross_incl_investor

  def dist_gross_incl_investor_percent = percentage(dist_gross_incl_investor, dist_gross_incl_total)

  def dist_gross_incl_kyc = money_sum(kyc_dist_payments, :gross_payable_cents)
  memoize :dist_gross_incl_kyc

  def dist_gross_incl_kyc_percent = percentage(dist_gross_incl_kyc, dist_gross_incl_total)

  # ================== DIST TAX ==================

  # PRIOR
  def dist_tax_prior_lp = money_sum(fund_dist_payments_lp_prior, :tax_with_fees_cents)
  memoize :dist_tax_prior_lp

  def dist_tax_prior_gp = money_sum(fund_dist_payments_gp_prior, :tax_with_fees_cents)
  memoize :dist_tax_prior_gp

  def dist_tax_prior_total = dist_tax_prior_lp + dist_tax_prior_gp
  memoize :dist_tax_prior_total

  def dist_tax_prior_investor = money_sum(comm_dist_payments_prior, :tax_with_fees_cents)
  memoize :dist_tax_prior_investor

  def dist_tax_prior_investor_percent = percentage(dist_tax_prior_investor, dist_tax_prior_total)

  def dist_tax_prior_kyc = money_sum(kyc_dist_payments_prior, :tax_with_fees_cents)
  memoize :dist_tax_prior_kyc

  def dist_tax_prior_kyc_percent = percentage(dist_tax_prior_kyc, dist_tax_prior_total)

  # CURRENT
  def dist_tax_curr_lp = money_sum(fund_dist_payments_lp_curr, :tax_with_fees_cents)
  memoize :dist_tax_curr_lp

  def dist_tax_curr_gp = money_sum(fund_dist_payments_gp_curr, :tax_with_fees_cents)
  memoize :dist_tax_curr_gp

  def dist_tax_curr_total = dist_tax_curr_lp + dist_tax_curr_gp
  memoize :dist_tax_curr_total

  def dist_tax_curr_investor = money_sum(comm_dist_payments_curr, :tax_with_fees_cents)
  memoize :dist_tax_curr_investor

  def dist_tax_curr_investor_percent = percentage(dist_tax_curr_investor, dist_tax_curr_total)

  def dist_tax_curr_kyc = money_sum(kyc_dist_payments_curr, :tax_with_fees_cents)
  memoize :dist_tax_curr_kyc

  def dist_tax_curr_kyc_percent = percentage(dist_tax_curr_kyc, dist_tax_curr_total)

  # INCLUDING Current Notice Date
  def dist_tax_incl_lp = money_sum(fund_dist_payments_lp, :tax_with_fees_cents)
  memoize :dist_tax_incl_lp

  def dist_tax_incl_gp = money_sum(fund_dist_payments_gp, :tax_with_fees_cents)
  memoize :dist_tax_incl_gp

  def dist_tax_incl_total = dist_tax_incl_lp + dist_tax_incl_gp
  memoize :dist_tax_incl_total

  def dist_tax_incl_investor = money_sum(comm_dist_payments, :tax_with_fees_cents)
  memoize :dist_tax_incl_investor

  def dist_tax_incl_investor_percent = percentage(dist_tax_incl_investor, dist_tax_incl_total)

  def dist_tax_incl_kyc = money_sum(kyc_dist_payments, :tax_with_fees_cents)
  memoize :dist_tax_incl_kyc

  def dist_tax_incl_kyc_percent = percentage(dist_tax_incl_kyc, dist_tax_incl_total)

  # ================== DIST Expense ==================

  # PRIOR
  def dist_expense_prior_lp = money_sum(fund_dist_payments_lp_prior, :expense_with_fees_cents)
  memoize :dist_expense_prior_lp

  def dist_expense_prior_gp = money_sum(fund_dist_payments_gp_prior, :expense_with_fees_cents)
  memoize :dist_expense_prior_gp

  def dist_expense_prior_total = dist_expense_prior_lp + dist_expense_prior_gp
  memoize :dist_expense_prior_total

  def dist_expense_prior_investor = money_sum(comm_dist_payments_prior, :expense_with_fees_cents)
  memoize :dist_expense_prior_investor

  def dist_expense_prior_investor_percent = percentage(dist_expense_prior_investor, dist_expense_prior_total)

  def dist_expense_prior_kyc = money_sum(kyc_dist_payments_prior, :expense_with_fees_cents)
  memoize :dist_expense_prior_kyc

  def dist_expense_prior_kyc_percent = percentage(dist_expense_prior_kyc, dist_expense_prior_total)

  # CURRENT
  def dist_expense_curr_lp = money_sum(fund_dist_payments_lp_curr, :expense_with_fees_cents)
  memoize :dist_expense_curr_lp

  def dist_expense_curr_gp = money_sum(fund_dist_payments_gp_curr, :expense_with_fees_cents)
  memoize :dist_expense_curr_gp

  def dist_expense_curr_total = dist_expense_curr_lp + dist_expense_curr_gp
  memoize :dist_expense_curr_total

  def dist_expense_curr_investor = money_sum(comm_dist_payments_curr, :expense_with_fees_cents)
  memoize :dist_expense_curr_investor

  def dist_expense_curr_investor_percent = percentage(dist_expense_curr_investor, dist_expense_curr_total)

  def dist_expense_curr_kyc = money_sum(kyc_dist_payments_curr, :expense_with_fees_cents)
  memoize :dist_expense_curr_kyc

  def dist_expense_curr_kyc_percent = percentage(dist_expense_curr_kyc, dist_expense_curr_total)

  # INCLUDING Current Notice Date
  def dist_expense_incl_lp = money_sum(fund_dist_payments_lp, :expense_with_fees_cents)
  memoize :dist_expense_incl_lp

  def dist_expense_incl_gp = money_sum(fund_dist_payments_gp, :expense_with_fees_cents)
  memoize :dist_expense_incl_gp

  def dist_expense_incl_total = dist_expense_incl_lp + dist_expense_incl_gp
  memoize :dist_expense_incl_total

  def dist_expense_incl_investor = money_sum(comm_dist_payments, :expense_with_fees_cents)
  memoize :dist_expense_incl_investor

  def dist_expense_incl_investor_percent = percentage(dist_expense_incl_investor, dist_expense_incl_total)

  def dist_expense_incl_kyc = money_sum(kyc_dist_payments, :expense_with_fees_cents)
  memoize :dist_expense_incl_kyc

  def dist_expense_incl_kyc_percent = percentage(dist_expense_incl_kyc, dist_expense_incl_total)

  # ================== DIST Display Only ==================

  # PRIOR
  def dist_display_prior_lp = money_sum(fund_dist_payments_lp_prior, :display_only_with_fees_cents)
  memoize :dist_display_prior_lp

  def dist_display_prior_gp = money_sum(fund_dist_payments_gp_prior, :display_only_with_fees_cents)
  memoize :dist_display_prior_gp

  def dist_display_prior_total = dist_display_prior_lp + dist_display_prior_gp
  memoize :dist_display_prior_total

  def dist_display_prior_investor = money_sum(comm_dist_payments_prior, :display_only_with_fees_cents)
  memoize :dist_display_prior_investor

  def dist_display_prior_investor_percent = percentage(dist_display_prior_investor, dist_display_prior_total)

  def dist_display_prior_kyc = money_sum(kyc_dist_payments_prior, :display_only_with_fees_cents)
  memoize :dist_display_prior_kyc

  def dist_display_prior_kyc_percent = percentage(dist_display_prior_kyc, dist_display_prior_total)

  # CURRENT
  def dist_display_curr_lp = money_sum(fund_dist_payments_lp_curr, :display_only_with_fees_cents)
  memoize :dist_display_curr_lp

  def dist_display_curr_gp = money_sum(fund_dist_payments_gp_curr, :display_only_with_fees_cents)
  memoize :dist_display_curr_gp

  def dist_display_curr_total = dist_display_curr_lp + dist_display_curr_gp
  memoize :dist_display_curr_total

  def dist_display_curr_investor = money_sum(comm_dist_payments_curr, :display_only_with_fees_cents)
  memoize :dist_display_curr_investor

  def dist_display_curr_investor_percent = percentage(dist_display_curr_investor, dist_display_curr_total)

  def dist_display_curr_kyc = money_sum(kyc_dist_payments_curr, :display_only_with_fees_cents)
  memoize :dist_display_curr_kyc

  def dist_display_curr_kyc_percent = percentage(dist_display_curr_kyc, dist_display_curr_total)

  # INCLUDING Current Notice Date
  def dist_display_incl_lp = money_sum(fund_dist_payments_lp, :display_only_with_fees_cents)
  memoize :dist_display_incl_lp

  def dist_display_incl_gp = money_sum(fund_dist_payments_gp, :display_only_with_fees_cents)
  memoize :dist_display_incl_gp

  def dist_display_incl_total = dist_display_incl_lp + dist_display_incl_gp
  memoize :dist_display_incl_total

  def dist_display_incl_investor = money_sum(comm_dist_payments, :display_only_with_fees_cents)
  memoize :dist_display_incl_investor

  def dist_display_incl_investor_percent = percentage(dist_display_incl_investor, dist_display_incl_total)

  def dist_display_incl_kyc = money_sum(kyc_dist_payments, :display_only_with_fees_cents)
  memoize :dist_display_incl_kyc

  def dist_display_incl_kyc_percent = percentage(dist_display_incl_kyc, dist_display_incl_total)
end
