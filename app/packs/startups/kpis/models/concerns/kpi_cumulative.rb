module KpiCumulative
  extend ActiveSupport::Concern

  # Calculates the start date of the fiscal year for a given date.
  # @param date [Date|String] The date to check
  # @param offset_months [Integer] Number of months to offset from January (e.g., 0 = Jan, 3 = Apr)
  # @return [Date] The start date of the fiscal year
  def fiscal_year_start(date, offset_months)
    date = date.to_date
    anchor_month = 1 + offset_months # e.g. 3 -> anchor_month = 4 (April)

    # If the month is before the anchor month, it belongs to the previous calendar year's fiscal start
    start_year = date.month >= anchor_month ? date.year : date.year - 1

    Date.new(start_year, 1, 1) + offset_months.months
  end

  # Generates a key for grouping dates by their fiscal year.
  # @param date [Date] The date to check
  # @param offset_months [Integer] The fiscal year offset
  # @param style [Symbol] :start_year (2024), :label ("FY2024-25"), or :range (Date..Date)
  def fiscal_year_key(date, offset_months, style: :start_year)
    fy_start = fiscal_year_start(date, offset_months)
    case style
    when :start_year
      fy_start.year # Returns integer, e.g., 2024 for FY 2024–25
    when :label
      y1 = fy_start.year
      y2 = fy_start.year + 1
      "FY#{y1}-#{(y2 % 100).zero? ? '00' : format('%02d', y2 % 100)}" # Returns string "FY2024-25"
    when :range
      (fy_start..(fy_start.next_year - 1)) # Returns a Date range
    end
  end

  # This is used to cumulate the KPI values over time periods like Quarterly and YTD.
  # It aggregates monthly 'Actual' values into Quarterly and Fiscal Year-to-Date (YTD) totals.
  def cumulate
    Rails.logger.info "--- [#{name}] Starting cumulate for KPI '#{name}' for entity #{entity_id}, pc_id: #{portfolio_company_id}"

    # Find all related monthly KPIs for this entity and name, but only Actuals.
    # We ignore 'Budget' or 'Forecast' for cumulative calculations.
    related_kpis = fetch_related_monthly_kpis

    Rails.logger.info "--- [#{name}] Found #{related_kpis.size} related monthly KPIs"
    return if related_kpis.empty?

    # Calculate and save Calendar Quarterly cumulative values
    process_quarterly_cumulatives(related_kpis)

    # Calculate and save Fiscal Year-to-Date (YTD) cumulative values
    process_yearly_cumulatives(related_kpis)

    Rails.logger.info "--- [#{name}] Cumulate complete for KPI '#{name}'"
  end

  private

  # Fetches monthly KPIs tagged 'Actual', ordered chronologically
  def fetch_related_monthly_kpis
    entity.kpis.joins(:kpi_report).includes(:kpi_report)
          .where(name: name, portfolio_company_id: portfolio_company_id)
          .where(kpi_reports: { tag_list: 'Actual', period: 'Month' })
          .order("kpi_reports.as_of ASC")
  end

  # Groups KPIs by calendar quarter and processes the sum
  def process_quarterly_cumulatives(related_kpis)
    # Group keys: [Year, Quarter Number (1-4)]
    kpis_by_quarter = related_kpis.group_by do |kpi|
      [kpi.kpi_report.as_of.year, ((kpi.kpi_report.as_of.month - 1) / 3) + 1]
    end

    Rails.logger.debug { "Quarterly Groups: #{kpis_by_quarter.keys}" }

    kpis_by_quarter.each do |(year, quarter), kpis_in_quarter|
      quarterly_sum = kpis_in_quarter.sum { |kpi| kpi.value.to_f }

      # Use the last KPI to determine the 'as_of' date logic if needed, or just for context
      last_kpi_in_quarter = kpis_in_quarter.last

      # Calculate quarter date boundaries
      quarter_start = Date.new(year, ((quarter - 1) * 3) + 1, 1)
      quarter_end   = quarter_start.end_of_quarter

      process_cumulative_kpi(last_kpi_in_quarter, quarterly_sum, 'Quarter', quarter_start, quarter_end)
    end
  end

  # Groups KPIs by Fiscal Year and processes the sum
  def process_yearly_cumulatives(related_kpis)
    # Get the financial year offset from company settings (default to 3 for April start)
    offset_months = (portfolio_company.json_fields['month_offset_for_financial_year'] || 3).to_i

    # Group by Fiscal Year Start (e.g., 2024 for FY2024-25)
    kpis_by_year = related_kpis.group_by do |kpi|
      fiscal_year_key(kpi.kpi_report.as_of, offset_months, style: :start_year)
    end

    Rails.logger.debug { "Yearly Groups: #{kpis_by_year.keys}" }

    kpis_by_year.each do |start_year, kpis_in_year|
      ytd_sum = kpis_in_year.sum { |kpi| kpi.value.to_f }
      last_kpi_in_year = kpis_in_year.last

      # Calculate fiscal year boundaries
      year_start = Date.new(start_year, 1, 1) + offset_months.months
      # End date: e.g., if start is Apr 1, 2024, end is Mar 31, 2025
      year_end = Date.new(start_year, 12, 31) + offset_months.months

      process_cumulative_kpi(last_kpi_in_year, ytd_sum, 'YTD', year_start, year_end)
    end
  end

  def process_cumulative_kpi(_curr_kpi, cumulative_sum, period, start_date, end_date)
    Rails.logger.debug { "Kpi:  [#{name}] Processing #{period} KPI for #{start_date} to #{end_date}, cumulative sum: #{cumulative_sum}" }

    cumulative_kpi = Kpi.joins(:kpi_report)
                        .where(entity_id: entity_id, name:, portfolio_company_id: portfolio_company_id)
                        .where(kpi_reports: { period: period })
                        .where(kpi_reports: { as_of: end_date })
                        .last

    if cumulative_kpi
      Rails.logger.debug { "Kpi:  [#{name}] Existing #{period} KPI found (id=#{cumulative_kpi.id}), current value=#{cumulative_kpi.value}, new value=#{cumulative_sum}" }
      cumulative_kpi.value = cumulative_sum
      cumulative_kpi.notes = "Auto-generated #{period} cumulative"
      if cumulative_kpi.changed?
        Rails.logger.info "--- [#{name}] Overwriting #{period} KPI #{cumulative_kpi.id} with new value #{cumulative_sum}"
        cumulative_kpi.save
      else
        Rails.logger.debug { "Kpi:  [#{name}] Skipping save for #{period} KPI #{cumulative_kpi.id} (unchanged)" }
      end

    else
      Rails.logger.info "--- [#{name}] Creating new #{period} KPI with value #{cumulative_sum}"
      user_id = kpi_report.user_id

      kpi_report = KpiReport.find_or_create_by(period: period, as_of: end_date,
                                               entity_id:, portfolio_company_id:, user_id:)

      kpi = Kpi.find_or_initialize_by(entity_id:, name:, portfolio_company_id:, kpi_report:)
      kpi.value = cumulative_sum
      kpi.notes = "Auto-generated #{period} cumulative"
      kpi.save
    end
  end
end
