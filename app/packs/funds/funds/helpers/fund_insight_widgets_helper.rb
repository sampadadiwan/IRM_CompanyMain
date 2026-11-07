# Data for the Fund Dashboard insight widgets: Remittance Ageing, NAV per Unit Trend and Hedge Expiries.
# Each method runs a fixed number of grouped queries; capital_remittances is a large table, so it is only
# ever read as grouped totals (CLAUDE.md large-table rules).
# Worked examples H14–H16, E33–E44, X9 — openspec/changes/archive/2026-11-07-dashboard-insight-widgets/business-rules.md#5
module FundInsightWidgetsHelper
  # Open = the statuses the remittances grid link filters on, so the widget's count equals the grid's rows (E37)
  AGEING_OPEN_STATUSES = %w[Pending Overdue].freeze
  AGEING_BUCKETS = ["Not yet due", "0–30 days", "31–60 days", "61–90 days", "Over 90 days"].freeze

  # Unpaid amount and count of the fund's open remittances, per bucket of days past the call's due date (H14).
  # Returns { "Not yet due" => { count:, cents: }, ... } with every bucket present.
  def remittance_ageing(fund, today: Date.current)
    # Due = call amount + other fees - collected (E36), the same figure as the remittances grid's Due Amount
    due_sql = "COALESCE(capital_remittances.call_amount_cents, 0) + COALESCE(capital_remittances.other_fee_cents, 0) " \
              "- COALESCE(capital_remittances.collected_amount_cents, 0)"
    # One grouped query: count and due per call due date. Paid and Overpaid are left out by status (E35).
    # Grouping by date (not DATEDIFF) keeps the SQL portable between MySQL and SQLite.
    per_date = fund.capital_remittances.unscope(:order).where(status: AGEING_OPEN_STATUSES).joins(:capital_call)
                   .group("capital_calls.due_date")
                   .pluck(Arel.sql("capital_calls.due_date"), Arel.sql("COUNT(*)"), Arel.sql("SUM(#{due_sql})"))

    buckets = AGEING_BUCKETS.index_with { { count: 0, cents: 0 } }
    per_date.each do |due_date, count, cents|
      bucket = ageing_bucket(due_date, today)
      buckets[bucket][:count] += count.to_i
      buckets[bucket][:cents] += cents.to_d
    end
    buckets
  end

  # E33 — due today is 0 days overdue; E34 — 30/31, 60/61 and 90/91 are the boundaries.
  # A call without a due date is treated as not yet due.
  def ageing_bucket(due_date, today)
    return AGEING_BUCKETS[0] if due_date.nil? || due_date > today

    days = (today - due_date.to_date).to_i
    if days <= 30 then AGEING_BUCKETS[1]
    elsif days <= 60 then AGEING_BUCKETS[2]
    elsif days <= 90 then AGEING_BUCKETS[3]
    else AGEING_BUCKETS[4]
    end
  end

  # Approved NAV per unit per unit class, for the `months` up to the latest approved NAV (H15; E39 drafts left
  # out; E40 the window). Returns chartkick line series [{ name: "Class A", data: { date => per_unit } }].
  def nav_per_unit_series(fund, months:)
    navs = FundNav.approved.where(fund_id: fund.id)
    # One query for the latest approved date; no NAVs means an empty chart (E41)
    latest = navs.maximum(:nav_date)
    return [] unless latest

    # Month ends stay month ends, so 6 months back from 30 Sep is everything after 31 Mar (6 points)
    from = latest.months_ago(months).end_of_month
    rows = navs.where(nav_date: (from + 1.day)..latest).order(:unit_type, :nav_date)
               .pluck(:unit_type, :nav_date, :nav_per_unit_cents)
    rows.group_by(&:first).map do |unit_type, class_rows|
      { name: "Class #{unit_type}", data: class_rows.to_h { |_type, date, cents| [date, (cents.to_d / 100).round(4).to_f] } }
    end
  end

  # Open contracts of the fund expiring within `days`, and open ones already past expiry, soonest first
  # (H16; E42 expired-but-open listed first; E43 beyond the window or closed left out).
  def hedge_expiry_rows(fund, days:, today: Date.current)
    # One query, joined to the underlying instrument for its name; only the columns the table shows
    DerivativeContract.open_contracts.where(fund_id: fund.id, expiry_date: ..(today + days))
                      .left_joins(:underlying_instrument).order(:expiry_date, :id)
                      .pluck(:id, :name, :contract_type, :underlying_name, Arel.sql("investment_instruments.name"),
                             :notional_cents, :currency, :expiry_date)
                      .map do |id, name, type, underlying_name, instrument_name, notional_cents, currency, expiry_date|
                        { id:, name:, type: DerivativeContract::TYPE_LABELS[type] || type.to_s.humanize,
                          underlying: underlying_name.presence || instrument_name, notional_cents:, currency:, expiry_date:,
                          days_left: (expiry_date - today).to_i }
                      end
  end

  # "15 days", "Expires today" or "Expired 10 days ago" (E42)
  def hedge_days_left_label(days_left)
    if days_left.positive? then "#{days_left} #{'day'.pluralize(days_left)}"
    elsif days_left.zero? then "Expires today"
    else "Expired #{-days_left} #{'day'.pluralize(-days_left)} ago"
    end
  end
end
