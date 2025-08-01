# Builds the Month/Quarter, YTD and TTM table for a single company
# Usage: rows = KpiReport::PerformanceTableService.call(
#           portfolio_company_id: 42,
#           metric_names: %w[Revenue EBITDA GMV],
#           as_of: Date.new(2025, 3, 31)
#         )
class PerformanceTableService
  # Represents a single row in the performance table, containing KPI values
  # for different periods (monthly, quarterly, YTD, TTM) and their
  # year-over-year growth rates.
  MetricRow = Struct.new(
    :metric,
    :monthly_curr_kpi, :monthly_prev_kpi, :growth_monthly, :growth_monthly_py,
    :quarterly_curr_kpi, :quarterly_prev_kpi, :growth_quarterly,
    :ytd_curr_kpi, :ytd_prev_kpi, :growth_ytd_py,
    :ttm_curr_kpi, :ttm_prev_kpi, :growth_ttm_py,
    :investor_kpi_mapping,
    keyword_init: true
  )
  # Represents a KPI value, primarily used for sums over periods.
  SumKpi = Struct.new(:value, keyword_init: true)

  class << self
    # Class method to create a new instance of the service and call its instance method.
    # This provides a convenient entry point for the service.
    # @param args [Hash] Arguments to initialize the service.
    # @return [Array<MetricRow>] An array of MetricRow objects, each representing a row in the performance table.
    def call(**args)
      new(**args).call
    end
  end

  # Initializes the PerformanceTableService.
  # @param kpi_report [KpiReport] The KPI report object.
  # @param portfolio_company_id [Integer] The ID of the portfolio company.
  # @param metric_names [Array<String>] An array of metric names to include in the report.
  # @param as_of [Date] The date as of which the report should be generated.
  def initialize(kpi_report:, portfolio_company_id:, metric_names:, as_of:)
    @kpi_report = kpi_report
    @metric_names = metric_names
    @as_of = as_of.to_date.end_of_month
    @scope = Kpi.for_company(portfolio_company_id).with_report
    @kpis_by_metric_and_date = fetch_kpis_for_all_metrics
  end

  # Executes the service to build the performance table rows.
  # If `metric_names` are provided during initialization, it builds rows for those specific metrics.
  # Otherwise, it builds rows for all KPIs associated with the `kpi_report`.
  # @return [Array<MetricRow>] An array of MetricRow objects, each representing a row in the performance table.
  def call
    if metric_names.present?
      @investor_kpi_mappings = @kpi_report.portfolio_company.investor_kpi_mappings.where(standard_kpi_name: metric_names).index_by(&:standard_kpi_name)
      metric_names.map { |name| build_row(name, @investor_kpi_mappings[name]) }
    else
      @investor_kpi_mappings = @kpi_report.portfolio_company.investor_kpi_mappings.index_by(&:standard_kpi_name)
      @kpi_report.kpis.map { |kpi| build_row(kpi.name, @investor_kpi_mappings[kpi.name]) }
    end
  end

  private

  attr_reader :metric_names, :as_of, :scope, :kpis_by_metric_and_date, :investor_kpi_mappings

  # --------------------------- Data Fetching --------------------------- #
  # Fetches all relevant KPIs for the specified metrics and date range.
  # It retrieves KPIs for the current reporting date and up to 23 months prior
  # to support TTM (Trailing Twelve Months) calculations.
  # The KPIs are grouped by metric name and report date for efficient lookup.
  # @return [Hash] A hash where keys are `[metric_name, kpi_date]` and values are Kpi objects.
  def fetch_kpis_for_all_metrics
    all_metrics = metric_names.presence || @kpi_report.kpis.pluck(:name)

    # Fetch KPIs for the current reporting date and up to 23 months prior for TTM calculations
    start_date = (as_of - 23.months).beginning_of_month
    end_date = as_of.end_of_quarter

    scope.for_metric(all_metrics).monthly
         .in_date_range(start_date..end_date).includes(:kpi_report)
         .group_by { |kpi| [kpi.name, kpi.kpi_report.as_of] }
         .transform_values(&:first)
  end

  # --------------------------- Row builder --------------------------- #
  # Builds a single MetricRow for a given metric name.
  # It fetches current and previous period KPIs for monthly, quarterly, YTD, and TTM,
  # and calculates their year-over-year growth rates.
  # @param metric_name [String] The name of the metric for which to build the row.
  # @return [MetricRow] A MetricRow object populated with KPI data and growth rates.
  def build_row(metric_name, investor_kpi_mapping)
    monthly_curr_kpi_obj = monthly_kpi(metric_name)
    monthly_prev_kpi_obj = monthly_kpi(metric_name, :prev_month)

    quarterly_curr_kpi_obj = quarterly_kpi(metric_name)
    quarterly_prev_kpi_obj = quarterly_kpi(metric_name, :prev_quarter)

    ytd_curr_kpi_obj = ytd_kpi(metric_name)
    ytd_prev_kpi_obj = ytd_kpi(metric_name, :prev_year)

    ttm_curr_kpi_obj = ttm_kpi(metric_name)
    ttm_prev_kpi_obj = ttm_kpi(metric_name, :prev_ttm)

    MetricRow.new(
      metric: metric_name,
      monthly_curr_kpi: monthly_curr_kpi_obj,
      monthly_prev_kpi: monthly_prev_kpi_obj,
      growth_monthly: growth(monthly_curr_kpi_obj&.value, monthly_prev_kpi_obj&.value),
      growth_monthly_py: growth(monthly_kpi(metric_name)&.value, monthly_kpi(metric_name, :prev_12_months)&.value),
      quarterly_curr_kpi: quarterly_curr_kpi_obj,
      quarterly_prev_kpi: quarterly_prev_kpi_obj,
      growth_quarterly: growth(quarterly_curr_kpi_obj&.value, quarterly_prev_kpi_obj&.value),
      ytd_curr_kpi: ytd_curr_kpi_obj,
      ytd_prev_kpi: ytd_prev_kpi_obj,
      growth_ytd_py: growth(ytd_curr_kpi_obj&.value, ytd_prev_kpi_obj&.value),
      ttm_curr_kpi: ttm_curr_kpi_obj,
      ttm_prev_kpi: ttm_prev_kpi_obj,
      growth_ttm_py: growth(ttm_curr_kpi_obj&.value, ttm_prev_kpi_obj&.value),
      investor_kpi_mapping: investor_kpi_mapping
    )
  end

  # --------------------------- Maths helpers ------------------------ #
  # Retrieves the value of a KPI for a given metric name and date.
  # Returns 0 if the KPI is not found for the specified date.
  # @param name [String] The name of the metric.
  # @param date [Date] The date for which to retrieve the KPI value.
  # @return [Numeric] The KPI value or 0 if not found.
  def value_on(name, date)
    kpi_on(name, date)&.value || 0
  end

  # Retrieves a KPI object for a given metric name and date from the pre-fetched data.
  # @param name [String] The name of the metric.
  # @param date [Date] The date for which to retrieve the KPI object.
  # @return [Kpi, nil] The Kpi object if found, otherwise nil.
  def kpi_on(name, date)
    kpis_by_metric_and_date[[name.to_s, date.to_date]]
  end

  # Calculates the sum of KPI values for a given metric within a specified date range.
  # This method performs a sum query on the database.
  # @param name [String] The name of the metric.
  # @param from_date [Date] The start date of the range (inclusive).
  # @param to_date [Date] The end date of the range (inclusive).
  # @return [Numeric] The sum of KPI values for the specified range, or 0 if no KPIs are found.
  def range_sum(name, from_date, to_date)
    # This method still performs a sum query, but it's for a range, not single KPIs.
    # If performance is still an issue, this could be optimized by pre-calculating sums
    # or using a more complex preloading strategy.
    scope.for_metric(name)
         .in_date_range(from_date..to_date)
         .sum(:value) || 0
  end

  # Calculates the percentage growth between a current and previous value.
  # Returns nil if the previous value is zero or current is nil to avoid division by zero or invalid calculations.
  # @param current [Numeric] The current value.
  # @param previous [Numeric] The previous value.
  # @return [Float, nil] The growth percentage, or nil if calculation is not possible.
  def growth(current, previous)
    return nil unless previous.to_f.nonzero? && current

    ((current.to_f / previous) - 1) * 100
  end

  # --------------------------- Period logic ------------------------- #
  # Determines the date of the previous reporting period.
  # If the current `as_of` date is the end of a quarter, it returns the previous quarter's end date.
  # Otherwise, it returns the previous month's end date.
  # @return [Date] The date of the previous period.
  def previous_period_date
    if [3, 6, 9, 12].include?(as_of.month) && as_of.end_of_month?
      as_of.prev_quarter
    else
      as_of.prev_month
    end
  end

  # Calculates the Year-to-Date (YTD) KPI for a given metric.
  # It sums up KPI values from the beginning of the year up to the `as_of` date.
  # Can calculate for the current year or the previous year.
  # @param name [String] The name of the metric.
  # @param which [Symbol] Specifies whether to calculate for `:current` year or `:prev_year`.
  # @return [SumKpi] A SumKpi object containing the calculated YTD value.
  def ytd_kpi(name, which = :current)
    date = which == :prev_year ? as_of.prev_year : as_of
    start_of_year = date.beginning_of_year.to_date
    end_of_period = date.to_date

    sum = kpis_by_metric_and_date.sum do |(metric_name, kpi_date), kpi|
      if metric_name == name.to_s && kpi_date >= start_of_year && kpi_date <= end_of_period
        kpi.value
      else
        0
      end
    end
    SumKpi.new(value: sum)
  end

  # Calculates the Trailing Twelve Months (TTM) KPI for a given metric.
  # It sums up KPI values for the past 12 months relative to the `as_of` date.
  # Can calculate for the current TTM period or the previous TTM period (year prior).
  # @param name [String] The name of the metric.
  # @param which [Symbol] Specifies whether to calculate for `:current` TTM or `:prev_ttm`.
  # @return [SumKpi] A SumKpi object containing the calculated TTM value.
  def ttm_kpi(name, which = :current)
    case which
    when :current
      start_date = (as_of - 11.months).to_date
      end_of_period = as_of.to_date
    when :prev_ttm
      start_date = (as_of - 23.months).to_date
      end_of_period = (as_of - 12.months).to_date
    end

    sum = kpis_by_metric_and_date.sum do |(metric_name, kpi_date), kpi|
      if metric_name == name.to_s && kpi_date >= start_date && kpi_date <= end_of_period
        kpi.value
      else
        0
      end
    end
    SumKpi.new(value: sum)
  end

  # Retrieves the monthly KPI object for a given metric name.
  # Can retrieve for the current month or the previous month.
  # @param name [String] The name of the metric.
  # @param which [Symbol] Specifies whether to retrieve for `:current` month or `:prev_month`.
  # @return [Kpi, nil] The Kpi object if found, otherwise nil.
  def monthly_kpi(name, which = :current)
    case which
    when :current
      date = as_of
    when :prev_month
      date = as_of.prev_month.end_of_month
    when :prev_year
      date = as_of.prev_year.end_of_month
    when :prev_12_months
      date = as_of.prev_month(12).end_of_month
    end
    kpi_on(name, date)
  end

  # Calculates the quarterly KPI for a given metric name.
  # It sums up KPI values for the entire quarter containing the `as_of` date.
  # Can calculate for the current quarter or the previous quarter.
  # @param name [String] The name of the metric.
  # @param which [Symbol] Specifies whether to calculate for `:current` quarter or `:prev_quarter`.
  # @return [SumKpi] A SumKpi object containing the calculated quarterly value.
  def quarterly_kpi(name, which = :current)
    date = which == :prev_quarter ? as_of.prev_quarter.end_of_quarter : as_of

    # Ensure we are always looking at the full quarter for the given date
    start_of_quarter = date.beginning_of_quarter.to_date
    end_of_quarter = date.end_of_quarter.to_date

    sum = kpis_by_metric_and_date.sum do |(metric_name, kpi_date), kpi|
      if metric_name == name.to_s && kpi_date >= start_of_quarter && kpi_date <= end_of_quarter
        kpi.value
      else
        0
      end
    end
    SumKpi.new(value: sum)
  end
end
