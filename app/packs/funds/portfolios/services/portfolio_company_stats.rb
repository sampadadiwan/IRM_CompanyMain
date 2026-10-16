# Holding totals for one portfolio company, in a target currency, for the stats cards
# (aggregate_portfolio_investments/_stats_for_portfolio_company: dashboard widget and investor page).
#
# Each figure is summed in SQL per (source currency, conversion date) and each group is converted once.
# ExchangeRate.convert is `rate * amount` with no rounding, so this equals converting row by row, with
# one rate lookup per distinct date instead of one per row and no rows loaded into Ruby.
# A group with no rate converts to 0, as each of its rows did before.
class PortfolioCompanyStats
  FIELDS = ["Bought Amount", "Sold Amount", "FMV", "Cost Of Remaining", "Income", "Sold + FMV"].freeze

  # debug_rates: one row per converted group (field, rows, from, to, date, rate, original/converted cents)
  attr_reader :debug_rates

  def initialize(portfolio_company, target_currency, debug: false)
    @portfolio_company = portfolio_company
    @target_currency = target_currency
    @entity_id = portfolio_company.entity_id
    @debug = debug
    @debug_rates = []
    # The entity's rate sources, resolved once rather than on every convert call
    @policy = ExchangeRate.default_policy(@entity_id)
  end

  # Cents in the target currency for each requested field (all of them when fields is blank).
  # Only the queries those fields need are run; "Sold + FMV" reuses Sold Amount and FMV.
  def cents(fields = nil)
    wanted = fields.presence || FIELDS
    results = {}
    results["Bought Amount"] = bought_cents if wanted.include?("Bought Amount")
    results["Sold Amount"] = sold_cents if wanted.intersect?(["Sold Amount", "Sold + FMV"])
    results["FMV"] = fmv_cents if wanted.intersect?(["FMV", "Sold + FMV"])
    results["Cost Of Remaining"] = cost_of_remaining_cents if wanted.include?("Cost Of Remaining")
    results["Income"] = income_cents if wanted.include?("Income")
    results["Sold + FMV"] = results["Sold Amount"] + results["FMV"] if wanted.include?("Sold + FMV")
    results
  end

  private

  def investments
    @portfolio_company.portfolio_investments.joins(:fund)
  end

  # Buys: amount in the fund's currency, converted as of the investment date
  def bought_cents
    convert_groups("Bought Amount", investments.buys, "funds.currency", "portfolio_investments.investment_date", "portfolio_investments.amount_cents")
  end

  # Sells: as for buys
  def sold_cents
    convert_groups("Sold Amount", investments.sells, "funds.currency", "portfolio_investments.investment_date", "portfolio_investments.amount_cents")
  end

  # FMV: converted as of the linked valuation's date, or the investment date when there is none
  # (the valuation is optional). left_joins keeps Valuation's default scope in the ON clause, so a
  # synthetic valuation counts as none, as pi.valuation did.
  def fmv_cents
    convert_groups("FMV", investments.left_joins(:valuation), "funds.currency",
                   "COALESCE(valuations.valuation_date, portfolio_investments.investment_date)", "portfolio_investments.fmv_cents")
  end

  # Cost of remaining: fund currency, as of the investment date
  def cost_of_remaining_cents
    convert_groups("Cost Of Remaining", investments, "funds.currency", "portfolio_investments.investment_date", "portfolio_investments.cost_of_remaining_cents")
  end

  # Income: cashflows in their instrument's currency, as of the payment date
  def income_cents
    cashflows = @portfolio_company.portfolio_cashflows.joins(:investment_instrument)
    convert_groups("Income", cashflows, "investment_instruments.currency", "portfolio_cashflows.payment_date", "portfolio_cashflows.amount_cents")
  end

  # Sums amount_sql per (currency, date) in one query, converts each group to the target currency
  # and adds them up. Missing rate → nil → 0 for the group.
  def convert_groups(field, relation, currency_sql, date_sql, amount_sql)
    groups = relation.group(Arel.sql(currency_sql), Arel.sql(date_sql))
                     .pluck(Arel.sql(currency_sql), Arel.sql(date_sql), Arel.sql("SUM(#{amount_sql})"), Arel.sql("COUNT(*)"))
    groups.sum do |currency, date, amount_cents, rows|
      converted = ExchangeRate.convert(currency, @target_currency, amount_cents, date, @entity_id, policy: @policy) || 0
      if @debug
        @debug_rates << { field:, rows:, from: currency, to: @target_currency, date:,
                          rate: ExchangeRate.get_rate(currency, @target_currency, date, @entity_id, policy: @policy),
                          original_cents: amount_cents, converted_cents: converted }
      end
      converted
    end
  end
end
