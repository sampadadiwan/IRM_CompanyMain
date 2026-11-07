# Data for the KPI insight widgets: KPI Movers and KPI Threshold Watch (Portfolio Company Dashboard) and
# Peer KPI Comparison (Aggregated Portfolio Dashboard).
# Worked examples H3–H6, E3–E12, H13, E31, E32, X8 — openspec/changes/archive/2026-11-07-dashboard-insight-widgets/business-rules.md#2
module KpiInsightWidgetsHelper
  # Columns the widgets read from kpis — the table carries wide json/notes columns we never need here
  INSIGHT_KPI_COLUMNS = %i[id name value percentage_change rag_status portfolio_company_id kpi_report_id investor_kpi_mapping_id].freeze

  # Order in which KPI Threshold Watch lists its flags (red, amber, below, above — H6)
  INSIGHT_FLAG_ORDER = { red: 0, amber: 1, below: 2, above: 3 }.freeze

  # E8 — the KPI widgets render only when the viewer can open KPI reports (the firm has the KPI module)
  def insight_kpis_visible?
    policy(KpiReport).index?
  end

  # The report tag and period a KPI widget reads, from its settings (defaults Actual and Quarter — E6)
  def insight_kpi_report_settings(args)
    { tag: insight_str_arg(args, :tag_list, "Actual"), period: insight_str_arg(args, :period, "Quarter") }
  end

  # E7 — the empty-state sentence when the company has no report with the configured tag and period
  def insight_no_kpi_report_message(settings)
    "No #{settings[:tag]} #{settings[:period]} KPI report for this company yet."
  end

  # The company's latest KPI report with the given tag and period that the viewer may see (E3, E6), or nil (E7)
  def insight_latest_kpi_report(company, settings)
    # Reports the viewer may see, for this company, matching the tag and period whatever their letter case
    insight_kpi_reports_for(company.id, settings)
      # The latest report only (E3)
      .order(as_of: :desc)
      .first
  end

  # KPI Movers rows: the report's KPIs that have a stored change, biggest change first, ties by name (H3, H4, E4, E5)
  def insight_kpi_movers(report, top_n)
    # The KPIs of this report only, with their mapping for formatting and threshold colours (one preload query)
    Kpi.where(kpi_report_id: report.id)
       # E4 — a KPI with no stored change has nothing to rank
       .where.not(percentage_change: nil)
       .select(*INSIGHT_KPI_COLUMNS)
       .includes(:investor_kpi_mapping)
       # H3, E5 — size of change first (a fall counts as much as a rise), then name
       .order(Arel.sql("ABS(kpis.percentage_change) DESC"), :name)
       # H4 — at most top_n rows
       .limit(top_n)
  end

  # KPI Threshold Watch rows: [kpi, [flags]] for the report's KPIs outside their limits, in flag order (H6, E9–E12)
  def insight_kpi_threshold_flags(report)
    # The report's KPIs with their mapping, loaded once — a report holds tens of KPIs, not thousands
    kpis = Kpi.where(kpi_report_id: report.id).select(*INSIGHT_KPI_COLUMNS).includes(:investor_kpi_mapping).order(:name).to_a

    # Work out each KPI's flags, keep only the flagged ones
    flagged = kpis.filter_map do |kpi|
      flags = insight_kpi_flags(kpi)
      [kpi, flags] if flags.any?
    end

    # H6 — red first, then amber, below and above threshold; ties keep the name order loaded above
    flagged.sort_by.with_index { |(_kpi, flags), index| [flags.map { |flag| INSIGHT_FLAG_ORDER[flag[:kind]] }.min, index] }
  end

  # The flags of one KPI: its RAG status (red / amber) and any threshold its change breaks
  def insight_kpi_flags(kpi)
    flags = []
    # E12 — red and amber are flags, green is not
    rag = kpi.rag_status.to_s.delete('"').downcase
    flags << { kind: rag.to_sym, label: rag.titleize, css: rag_status_badge_class(rag) } if %w[red amber].include?(rag)

    # The threshold rule is the KPI grid's own (kpi_percentage_class): a threshold counts only when above zero (E10),
    # and a change equal to the threshold is not a breach (E9)
    mapping = kpi.investor_kpi_mapping
    change = kpi.percentage_change
    return flags if change.nil? || mapping.nil?

    lower = mapping.lower_threshold
    upper = mapping.upper_threshold
    flags << { kind: :below, label: "Below #{insight_threshold_text(lower)} % threshold", css: "bg-danger-subtle text-danger" } if lower&.positive? && change < lower
    flags << { kind: :above, label: "Above #{insight_threshold_text(upper)} % threshold", css: "bg-success-subtle text-success" } if upper&.positive? && change > upper
    flags
  end

  # 10.0 → "10", 12.5 → "12.5"
  def insight_threshold_text(value)
    number_with_precision(value, precision: 2, strip_insignificant_zeros: true)
  end

  # Peer KPI Comparison rows: one per company that has the KPI on its latest matching report, biggest change first.
  # Each row: { company_name:, kpi:, as_of: }. H13, E31, E32
  def insight_peer_kpi_rows(company_ids, kpi_name, settings)
    # The latest report per company with this tag and period: pluck the small columns once, pick the newest in Ruby
    latest = {}
    insight_kpi_reports_for(company_ids, settings).pluck(:id, :portfolio_company_id, :as_of).each do |id, company_id, as_of|
      latest[company_id] = [id, as_of] if latest[company_id].nil? || as_of > latest[company_id][1]
    end
    return [] if latest.empty?

    # The KPI on those reports, matched by its reported name or its mapping's standard name, ignoring case (E31)
    name = kpi_name.downcase
    kpis = Kpi.where(kpi_report_id: latest.values.map(&:first))
              .includes(:investor_kpi_mapping).references(:investor_kpi_mappings)
              .where("LOWER(kpis.name) = :name OR LOWER(investor_kpi_mappings.standard_kpi_name) = :name", name:)
              .order("kpis.name")
              .to_a

    # One KPI per company (the first by name if a company reports it twice); companies without it drop out (E32)
    by_company = kpis.group_by(&:portfolio_company_id).transform_values(&:first)
    names = Investor.where(id: by_company.keys).pluck(:id, :investor_name).to_h

    # Biggest change first; companies with no stored change go last
    by_company.map { |company_id, kpi| { company_name: names[company_id], kpi:, as_of: latest[company_id][1] } }
              .sort_by { |row| [row[:kpi].percentage_change.nil? ? 1 : 0, -row[:kpi].percentage_change.to_f, row[:company_name].to_s] }
  end

  # Chart data for Peer KPI Comparison: company name → change %
  def insight_peer_kpi_chart_data(rows)
    rows.reject { |row| row[:kpi].percentage_change.nil? }.to_h { |row| [row[:company_name], row[:kpi].percentage_change.to_f] }
  end

  private

  # KPI reports the viewer may see, for these companies, with the tag and period from the settings (case-insensitive)
  def insight_kpi_reports_for(company_ids, settings)
    policy_scope(KpiReport)
      .where(portfolio_company_id: company_ids)
      .where("LOWER(kpi_reports.tag_list) = ? AND LOWER(kpi_reports.period) = ?", settings[:tag].downcase, settings[:period].downcase)
  end
end
