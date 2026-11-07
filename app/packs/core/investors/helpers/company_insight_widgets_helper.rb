# Data for the company insight widgets on the Portfolio Company Dashboard: Monitoring Status, Investment Timeline
# and Ownership Trend. Worked examples H5, E13, E14, X4, X5 (§2) and H7, H8, E15–E19, X6 (§3) —
# openspec/changes/dashboard-insight-widgets/business-rules.md
module CompanyInsightWidgetsHelper
  # The firm's portfolio company agent, when the viewer may see it; nil hides Monitoring Status (X4)
  def insight_portfolio_company_agent
    # One agent per firm, of the viewer's own firm only (X5 — another firm's agent and reports never match)
    agent = SupportAgent.find_by(entity_id: current_user.entity_id, agent_type: "PortfolioCompanyAgent")
    # The same check the AI Portfolio Company Dashboard makes before showing these reports
    agent if agent && policy(agent).show?
  end

  # The agent's latest report for the company, or nil when the company has not been checked yet (E13, E14)
  def insight_monitoring_report(agent, company)
    SupportAgentReport.where(support_agent: agent, owner: company)
                      # E14 — the report flagged latest wins; among equals, the newest
                      .order(latest: :desc, created_at: :desc, id: :desc)
                      .first
  end

  # The three areas the agent checks, in the order the widget shows them
  MONITORING_AREAS = [
    { key: :kpi, issues_key: "kpi_issues", label: "KPI submissions", icon: "ti-chart-histogram",
      help: "Were the expected KPI reports submitted for the period?" },
    { key: :document, issues_key: "document_issues", label: "Documents", icon: "ti-files",
      help: "Were the required documents received?" },
    { key: :valuation, issues_key: "valuation_issues", label: "Valuations", icon: "ti-scale",
      help: "Is the company's valuation up to date?" }
  ].freeze

  # Rows the "Needs attention" list shows before pointing to the agent report
  MONITORING_ISSUE_ROWS = 6

  # One summary per area of the report: label, icon, help, status text and theme colour (H5).
  # An area with a blocking or missing item has issues; one that only has passing items is All clear;
  # one the agent recorded nothing for has No data — the same reading as the agent dashboard.
  def monitoring_areas(report)
    data = report.json_fields.to_h.with_indifferent_access
    MONITORING_AREAS.map do |area|
      issues = Array(data[area[:issues_key]]).map { |issue| issue.to_h.with_indifferent_access }
      problems = issues.count { |issue| monitoring_problem?(issue) }
      status, color = if problems.positive? then [pluralize(problems, "issue"), "danger"]
                      elsif issues.any? then ["All clear", "success"]
                      else ["No data", "secondary"]
                      end
      area.merge(status:, color:, problems:)
    end
  end

  # The report's problems across the three areas, blocking first: [{ area:, icon:, badge:, css:, message:, detail: }]
  def monitoring_open_issues(report)
    data = report.json_fields.to_h.with_indifferent_access
    rows = MONITORING_AREAS.flat_map do |area|
      Array(data[area[:issues_key]]).map { |issue| issue.to_h.with_indifferent_access }
                                    .select { |issue| monitoring_problem?(issue) }
                                    .map { |issue| monitoring_issue_row(area, issue) }
    end
    rows.sort_by { |row| row[:badge] == "Blocking" ? 0 : 1 }
  end

  # The report's overall result as a badge: Blocked (red), Ready (green), or the stored status otherwise
  def monitoring_status_badge(report)
    status = report.json_fields.to_h.with_indifferent_access[:final_status].presence || report.status.to_s
    css = { "blocked" => "bg-danger-subtle text-danger", "ready" => "bg-success-subtle text-success" }
          .fetch(status.to_s.downcase, "bg-secondary-subtle text-secondary")
    content_tag(:span, status.to_s.titleize, class: "badge #{css}", data: { insight_monitoring_status: true })
  end

  # Investment Timeline: buys and sells of the company per period, in the firm's currency (H7, E15–E17, X6).
  # Returns { periods: [label, ...], bought: { label => cents }, sold: { label => -cents }, skipped: count, currency: }
  def insight_investment_timeline(company, period)
    firm_currency = current_user.entity.currency
    # X6 — only the transactions of funds the viewer can access; just the columns the chart needs
    rows = policy_scope(PortfolioInvestment).where(portfolio_company_id: company.id).joins(:fund).unscope(:order)
                                            .pluck(:investment_date, :quantity, :entity_currency_amount_cents, :amount_cents, "funds.currency")

    timeline = { periods: [], bought: Hash.new(0), sold: Hash.new(0), skipped: 0, currency: firm_currency }
    rows.sort_by(&:first).each do |date, quantity, firm_cents, fund_cents, fund_currency|
      # E15 — the firm-currency amount when the tracking-currency job has set it; a fund in the firm's own currency
      # needs no conversion; a foreign amount with no firm-currency figure cannot be added in and is counted as skipped
      cents = firm_cents.to_i.nonzero? || (fund_currency == firm_currency ? fund_cents.to_i : nil)
      if cents.nil? || date.nil?
        timeline[:skipped] += 1
        next
      end
      # A zero-amount row (e.g. a bonus issue) moves no money, so it adds no period of its own
      next if cents.zero?

      # H7, E16 — the period label: "Q1 2025" by quarter (default) or "2025" by year
      label = period == "year" ? date.year.to_s : "Q#{((date.month - 1) / 3) + 1} #{date.year}"
      timeline[:periods] << label unless timeline[:periods].include?(label)
      # A negative quantity is a sale: shown as a negative amount
      if quantity.to_d.negative?
        timeline[:sold][label] -= cents.abs
      else
        timeline[:bought][label] += cents.abs
      end
    end
    timeline
  end

  # Chartkick series for the timeline, with every period on both series so the bars line up
  def insight_investment_timeline_series(timeline)
    [["Bought", timeline[:bought]], ["Sold", timeline[:sold]]].map do |name, sums|
      { name:, data: timeline[:periods].index_with { |label| sums[label] / 100.0 } }
    end
  end

  # Ownership Trend: total fully diluted % per holder group on each cap-table date (H8, E18, E19).
  # Returns { [date, group] => percentage }, oldest date first
  def insight_ownership_trend(company)
    policy_scope(ShareholderPosition).where(portfolio_company_id: company.id)
                                     # Pending (unapproved) updates are not final yet
                                     .where(status: "approved")
                                     # E18 — a position without a date or a % cannot be plotted
                                     .where.not(position_date: nil).where.not(fully_diluted_percentage: nil)
                                     .unscope(:order)
                                     .group(:position_date, :category)
                                     .sum(:fully_diluted_percentage)
                                     .sort_by { |(date, group), _pct| [date, group.to_s] }
                                     .to_h
  end

  # Chartkick line series: one line per holder group, date → %
  def insight_ownership_series(trend)
    trend.group_by { |(_date, group), _pct| group.presence || "Unspecified" }.map do |group, points|
      { name: group, data: points.to_h { |(date, _group), pct| [date, pct.to_f.round(2)] } }
    end
  end

  private

  # A blocking item, or a missing document, is a problem; passing ("success") items are not
  def monitoring_problem?(issue)
    severity = issue[:severity].to_s
    severity == "blocking" || (severity != "success" && issue[:type].to_s == "missing")
  end

  def monitoring_issue_row(area, issue)
    badge = if issue[:severity].to_s == "blocking" then "Blocking"
            elsif issue[:type].to_s == "missing" then "Missing"
            else issue[:severity].to_s.titleize.presence || "Warning"
            end
    css = badge == "Warning" ? "bg-warning-subtle text-warning" : "bg-danger-subtle text-danger"
    { area: area[:label], icon: area[:icon], badge:, css:, message: issue[:message].presence || "No details recorded",
      detail: issue[:document_name].presence || issue[:period].presence }
  end
end
