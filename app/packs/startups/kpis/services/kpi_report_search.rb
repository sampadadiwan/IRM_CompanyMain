class KpiReportSearch
  def self.perform(kpi_reports, params)
    kpi_reports = kpi_reports.where(id: search_ids(kpi_reports, params)) if params[:search] && params[:search][:value].present?

    kpi_reports = filter_by_portfolio_company(kpi_reports, params)

    if params[:budget_view].blank?
      no_val = params[:no_of_periods].to_s.strip
      no_of_periods = no_val.present? && no_val.to_i > 0 ? no_val.to_i : 12
      period = params[:period].presence || 'month'
    end

    if no_of_periods.present? && !Rails.env.test?
      case period.downcase
      when 'month'
        delta = no_of_periods.months
      when 'quarter'
        delta = (no_of_periods * 3).months
      when 'year', 'ytd'
        delta = (no_of_periods * 12).months
      when 'half year'
        delta = (no_of_periods * 6).months
      end
      date = Time.zone.today - delta

      latest_kpi_report = kpi_reports.order(as_of: :desc).first

      date = (latest_kpi_report.as_of - delta).end_of_month + 1.day if latest_kpi_report.present? && latest_kpi_report.as_of.present?
      kpi_reports = kpi_reports.where(kpi_reports: { as_of: date.. })
    end

    kpi_reports = kpi_reports.where(kpi_reports: { import_upload_id: params[:import_upload_id] }) if params[:import_upload_id]

    kpi_reports.distinct
  end

  def self.filter_by_portfolio_company(kpi_reports, params)
    if params[:portfolio_company_id].present?
      portfolio_company = Investor.find_by(id: params[:portfolio_company_id])
      kpi_reports = kpi_reports.where("kpi_reports.portfolio_company_id=? or kpi_reports.entity_id=?", portfolio_company.id, portfolio_company.investor_entity_id) if portfolio_company.present?
    end
    kpi_reports.distinct
  end

  def self.search_ids(kpi_reports, params)
    query = "#{params[:search][:value]}*"
    kpi_ids = kpi_reports.unscope(:order).pluck("kpi_reports.id")

    return [] if kpi_ids.empty? || query.blank?

    KpiReportIndex
      .filter(terms: { id: kpi_ids.map(&:to_s) }) # Convert to string for keyword matching
      .query(simple_query_string: {
               fields: KpiReportIndex::SEARCH_FIELDS,
               query: query,
               default_operator: 'and'
             })
      .per(100)
      .map(&:id)
  end
end
