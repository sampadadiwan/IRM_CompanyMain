# Data for the LP versions of the company widgets whose internal screens are for the fund team. Everything is
# limited to what an LP may see: Actual KPIs only (Budget and IC figures never reach LPs — E55, E56) and the
# selected fund's visible holdings (E57).
# Worked examples E55–E57 — openspec/changes/lp-folio-portfolio-dashboard/business-rules.md
class LpWidgetData
  ACTUAL = "Actual".freeze

  def initialize(company:, fund:, visibility:)
    @company = company
    @fund = fund
    @visibility = visibility
  end

  # The LP's visible holdings of the company in the selected fund
  def holdings
    @holdings ||= @visibility.visible_holdings(@company, @fund)
  end

  # Latest Actual KPI reports (oldest first) and { kpi name => { report id => value } }
  def kpi_table(periods: 4)
    reports = @company.portfolio_kpi_reports.where(tag_list: ACTUAL).order(as_of: :desc).limit(periods).to_a.reverse
    values = Kpi.where(kpi_report_id: reports.map(&:id)).pluck(:kpi_report_id, :name, :value)
    rows = values.group_by(&:second).transform_values { |entries| entries.to_h { |report_id, _name, value| [report_id, value] } }
    [reports, rows]
  end

  # Valuations of the instruments the fund holds in the company (E57)
  def valuations(limit: 8)
    Valuation.where(owner: @company, investment_instrument_id: holdings.select(:investment_instrument_id))
             .includes(:investment_instrument).order(valuation_date: :desc).limit(limit)
  end

  # The company's figures in the selected fund only (never across funds — E57)
  def stats
    currency = @fund.currency
    {
      "Bought Amount" => Money.new(PortfolioInvestment.where(aggregate_portfolio_investment_id: holdings.select(:id)).sum(:net_bought_amount_cents), currency),
      "FMV" => Money.new(holdings.sum(:fmv_cents), currency),
      "Cost Of Remaining" => Money.new(holdings.sum(:cost_of_remaining_cents), currency)
    }
  end
end
