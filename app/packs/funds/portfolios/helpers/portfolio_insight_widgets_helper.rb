# Data for the Portfolio Dashboard / Aggregated Portfolio Dashboard insight widgets: Valuation Freshness,
# Winners & Losers and Sector Exposure. Each method runs a fixed number of grouped queries, whatever the
# number of companies (no per-row lookups).
# Worked examples H9–H12, E20–E30, X7 — openspec/changes/dashboard-insight-widgets/business-rules.md#4
module PortfolioInsightWidgetsHelper
  FRESHNESS_STATUSES = %w[Current Due Stale Never].freeze
  # Bootstrap theme colour per status, used for the count cards and row badges
  FRESHNESS_COLORS = { "Current" => "success", "Due" => "warning", "Stale" => "danger", "Never" => "secondary" }.freeze

  # The companies Valuation Freshness covers.
  # - Portfolio Dashboard: the companies the fund still holds (H9; E23 — a fully exited holding is left out)
  # - Aggregated Portfolio Dashboard: the companies listed on that page (H10)
  # Returns [[id, name], ...] in one query.
  def freshness_companies(fund: nil, investors: nil)
    if fund
      # Holdings with a positive quantity left; snapshots are already excluded by WithSnapshot's default scope
      held_ids = fund.aggregate_portfolio_investments.unscope(:order).where("aggregate_portfolio_investments.quantity > 0")
                     .select(:portfolio_company_id)
      Investor.where(id: held_ids).pluck(:id, :investor_name)
    else
      # The aggregated page's own filtered, policy-scoped list of portfolio companies
      investors.unscope(:order).pluck(:id, :investor_name).uniq
    end
  end

  # One row per company: last valuation date, days since and status, stalest first (Never, then oldest).
  # H9, E20–E22, E25; X7 — only the firm's own valuations count.
  def valuation_freshness_rows(companies, entity_id:, current_days:, due_days:, today: Date.current)
    # Due must reach at least as far as Current, so a smaller Due setting cannot hide the Due band
    due_days = [due_days, current_days].max
    ids = companies.map(&:first)
    # One grouped query: latest valuation date per company (synthetic valuations are left out by
    # Valuation's default scope)
    last_dates = Valuation.unscope(:order).where(entity_id:, owner_type: "Investor", owner_id: ids)
                          .group(:owner_id).maximum(:valuation_date)

    rows = companies.map do |id, name|
      last_date = last_dates[id]
      # E25 — a future-dated valuation counts as 0 days old
      days = last_date && [(today - last_date).to_i, 0].max
      { id:, name:, last_date:, days:, status: freshness_status(days, current_days, due_days) }
    end
    # Never valued first, then the oldest valuation, then by name for a stable order
    rows.sort_by { |row| [row[:days].nil? ? 0 : 1, -(row[:days] || 0), row[:name].to_s] }
  end

  # E20 — exactly current_days is Current; E21 — up to due_days is Due, older is Stale
  def freshness_status(days, current_days, due_days)
    return "Never" if days.nil?
    return "Current" if days <= current_days
    return "Due" if days <= due_days

    "Stale"
  end

  # Average days in a month, for turning a day count into months
  AVG_DAYS_PER_MONTH = 30.44

  # E64 — the age a person reads: days up to 30, then months, then years and months (the exact days are in the
  # cell's tooltip). 29 → "29 days", 92 → "3 months", 273 → "9 months", 1369 → "3 years 9 months"
  def freshness_age_label(days)
    return "—" if days.nil?
    return pluralize(days, "day") if days <= 30

    # Whole months to the nearest month, then split into years and the months left over
    months = (days / AVG_DAYS_PER_MONTH).round
    years, rest = months.divmod(12)
    return pluralize(months, "month") if years.zero?

    [pluralize(years, "year"), (pluralize(rest, "month") if rest.positive?)].compact.join(" ")
  end

  # Count of companies per status, every status present (zero when none) — the cards above the table
  def freshness_counts(rows)
    FRESHNESS_STATUSES.index_with { |status| rows.count { |row| row[:status] == status } }
  end

  # Unrealised gain per company, summed across the fund's instruments (E28), split into the top gains and the
  # top losses (H11). Zero totals are in neither list (E26). Amounts in cents, fund currency.
  def winners_and_losers(fund, top_n:)
    # One grouped query: total unrealised gain per company
    totals = fund.aggregate_portfolio_investments.unscope(:order).group(:portfolio_company_id).sum(:unrealized_gain_cents)
    # One query for the names of the companies that made either list
    gains = totals.select { |_id, cents| cents.to_d.positive? }.sort_by { |_id, cents| -cents }.first(top_n)
    losses = totals.select { |_id, cents| cents.to_d.negative? }.sort_by { |_id, cents| cents }.first(top_n)
    names = Investor.where(id: (gains + losses).map(&:first)).pluck(:id, :investor_name).to_h
    to_rows = ->(pairs) { pairs.map { |id, cents| { id:, name: names[id], cents: } } }
    { gains: to_rows.call(gains), losses: to_rows.call(losses) }
  end

  # FMV (or cost of the holdings still held) per portfolio company sector, largest first (H12, E29).
  # A blank sector is "Unassigned". Returns [{ sector:, cents:, percent: }] or [] when the total is not positive (E30).
  def sector_exposure_rows(fund, measure:)
    column = measure == "cost" ? :cost_of_remaining_cents : :fmv_cents
    # One grouped query, joined to the company for its sector
    sums = fund.aggregate_portfolio_investments.unscope(:order).joins(:portfolio_company)
               .group("investors.sector").sum("aggregate_portfolio_investments.#{column}")
    # Blank and nil sectors fold into one "Unassigned" row
    by_sector = sums.each_with_object(Hash.new(0)) { |(sector, cents), acc| acc[sector.presence || "Unassigned"] += cents.to_d }
    total = by_sector.values.sum
    return [] unless total.positive?

    by_sector.reject { |_sector, cents| cents.zero? }
             .sort_by { |sector, cents| [-cents, sector] }
             .map { |sector, cents| { sector:, cents:, percent: (cents / total * 100).round(2) } }
  end
end
