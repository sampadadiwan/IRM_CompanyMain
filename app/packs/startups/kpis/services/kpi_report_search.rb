class KpiReportSearch
  def self.perform(kpi_reports, params)
    kpi_reports = kpi_reports.where(id: search_ids(kpi_reports, params)) if params[:search] && params[:search][:value].present?

    # Test cases have static data, hence we load all the kpi_reports, but in production we filter by months
    no_of_periods = params[:no_of_periods].present? ? params[:no_of_periods].to_i : 12
    period = params[:period].presence || 'month'

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
      kpi_reports = kpi_reports.where(as_of: date..)
    end

    if params[:portfolio_company_id].present?
      @portfolio_company = Investor.find(params[:portfolio_company_id])
      # Now either the portfolio_company has uploaded and given access to the kpi_reports
      # Or the fund company has uploaded the kpi_reports for the portfolio_company
      kpi_reports = kpi_reports.where("portfolio_company_id=? or kpi_reports.entity_id=?", @portfolio_company.id, @portfolio_company.investor_entity_id) if @portfolio_company.present?
    end

    kpi_reports = kpi_reports.where(import_upload_id: params[:import_upload_id]) if params[:import_upload_id]

    kpi_reports.distinct
  end

  def self.search_ids(kpi_reports, params)
    query = "#{params[:search][:value]}*"
    kpi_ids = kpi_reports.pluck(:id)

    return [] if kpi_ids.empty? || query.blank?

    KpiReportIndex
      .filter(terms: { id: kpi_ids.map(&:to_s) }) # Convert to string for keyword matching
      .query(query_string: {
               fields: KpiReportIndex::SEARCH_FIELDS,
               query: query,
               default_operator: 'and'
             })
      .per(100)
      .map(&:id)
  end
end
