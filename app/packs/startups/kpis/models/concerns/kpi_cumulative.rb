# This concern provides methods to automatically calculate and store cumulative KPI values
# (Quarterly and YTD) based on monthly 'Actual' data.
# It supports different modes of operation:
# - :cumulate (summing monthly values)
# - :forward_fill (carrying forward the latest value)
# - :compute (evaluating a custom formula)
#
# NOTE: 'Year' cumulative records are only created when exactly 12 monthly 'Actual'
# records exist within the SAME fiscal year. The fiscal year boundary is defined
# by EntitySetting#start_of_financial_year_date (default: April 1st).
module KpiCumulative
  extend ActiveSupport::Concern

  included do
    # Stores errors encountered during the cumulation process.
    attr_accessor :autofill_errors
  end

  # Generates a key or label for grouping dates by their fiscal year.
  #
  # @param date [Date] The date to get the fiscal year key for.
  # @param style [Symbol] The style of the key:
  #   - :start_year: Returns the starting year of the FY (Integer).
  #   - :label: Returns a string representation like "FY2024-25".
  #   - :range: Returns a Date range for the entire fiscal year.
  # @return [Integer, String, Range<Date>]
  def fiscal_year_key(date, style: :start_year)
    # The fiscal year is determined by EntitySetting#start_of_financial_year_date.
    # By default, month_offset_for_fy is 3 (April).
    # Dates from Jan to March (month <= 3) belong to the previous year's fiscal year.
    # Dates from April to Dec (month > 3) belong to the current year's fiscal year.
    fy_start = (respond_to?(:start_of_financial_year_date) && start_of_financial_year_date(date, nil_if_not_set: true)) || (respond_to?(:entity) && entity&.entity_settings&.start_of_financial_year_date(date)) || (respond_to?(:entity_id) && entity_id && EntitySetting.find_by(entity_id: entity_id)&.start_of_financial_year_date(date))
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

  # Entry point for the cumulation process. Determines the mode of operation from the
  # KPI's mapping and executes the appropriate logic to fill Quarterly and YTD reports.
  #
  # @param force [Boolean] If true, overwrites existing cumulative KPI values even if they haven't changed.
  def autofill(force: false)
    @autofill_errors = []
    # Fetch mapping to determine the mode
    mapping = investor_kpi_mapping
    mode = mapping&.autofill || 'blank'

    mode = 'blank' if mode.blank? # Ensure it's not nil

    Rails.logger.info "--- [#{name}] Starting #{mode} for KPI '#{name}' for entity #{entity_id}, pc_id: #{portfolio_company_id} (force: #{force})"

    case mode.to_s
    when 'cumulate'
      perform_cumulation(force: force)
    when 'forward_fill'
      perform_forward_fill(force: force)
    when 'compute'
      perform_computation(force: force)
    else
      Rails.logger.info "--- [#{name}] Mode is '#{mode}', skipping."
    end

    Rails.logger.info "--- [#{name}] Process complete for KPI '#{name}'"
  end

  private

  # Performs cumulation by summing monthly 'Actual' KPI values into Quarterly and YTD reports.
  def perform_cumulation(force: false)
    related_kpis = fetch_related_monthly_kpis
    return if related_kpis.empty?

    process_quarterly_cumulatives(related_kpis, force: force)
    process_yearly_cumulatives(related_kpis, force: force)
  end

  # Performs forward fill by taking the latest monthly 'Actual' KPI value and applying it to
  # Quarterly and YTD reports.
  def perform_forward_fill(force: false)
    related_kpis = fetch_related_monthly_kpis
    return if related_kpis.empty?

    process_quarterly_forward_fill(related_kpis, force: force)
    process_yearly_forward_fill(related_kpis, force: force)
  end

  # Performs computation based on a custom formula defined in the KPI mapping.
  # Evaluates the formula using values of other KPIs in the same report.
  def perform_computation(force: false)
    # This should be called last by the job, but we'll implement the logic here
    # Computation logic typically applies to the current period (Quarter/YTD)
    # and uses values of other KPIs in the same report.

    mapping = investor_kpi_mapping
    return if mapping&.compute_formula.blank?

    # We need to compute for all existing Quarterly and YTD reports for this PC
    kpi_reports = KpiReport.where(portfolio_company_id: portfolio_company_id)

    kpi_reports.each do |report|
      # Only compute if value is not already present
      existing_kpi = Kpi.approved.find_by(kpi_report: report, name: name, entity_id: entity_id)

      # If the KPI is missing or has no value, we compute it.
      compute_value_for_report(report, mapping.compute_formula, force: force) if existing_kpi.nil? || existing_kpi.value.nil? || force
    end
  end

  # Computes a value for a specific KpiReport using a formula string.
  # Replaces KPI names in the formula with their actual values from the report.
  #
  # @param report [KpiReport] The report context for the computation.
  # @param formula [String] The formula to evaluate (e.g., "Revenue - Cost").
  # @param force [Boolean] Whether to overwrite existing values.
  def compute_value_for_report(report, formula, force: false)
    # Simple eval based computation
    # Formula example: Revenue - Cost
    # Replace KPI Names with the value of that KPI in the same report

    clean_formula = formula.dup
    kpis_in_report = Kpi.approved.where(kpi_report: report).index_by(&:name)

    # Sort KPI names by length descending to avoid partial matches (e.g., 'Revenue' before 'Rev')
    kpi_names = kpis_in_report.keys.sort_by(&:length).reverse

    kpi_names.each do |kpi_name|
      next unless clean_formula.include?(kpi_name)

      val = kpis_in_report[kpi_name]&.value.to_f
      # Using regex with word boundaries to ensure we don't replace parts of other words
      # though KPI names might contain spaces, so we handle it carefully.
      clean_formula.gsub!(/\b#{Regexp.escape(kpi_name)}\b/, val.to_s)
    end

    begin
      # Basic safety check: allow only numbers and math operators
      if %r{\A[\d\s+\-*/.()]+\z}.match?(clean_formula)
        computed_val = eval(clean_formula) # rubocop:disable Security/Eval
        process_cumulative_kpi(nil, computed_val, report.period, nil, report.as_of, note: "Auto-generated Computed", user_id: report.user_id, force: force)
      else
        error_msg = "Invalid formula after replacement for report #{report.id} (#{report.period} #{report.as_of}): #{clean_formula}"
        Rails.logger.error "--- [#{name}] #{error_msg}"
        @autofill_errors << { kpi: name, report: report.id, as_of: report.as_of, message: error_msg }
      end
    rescue StandardError => e
      Rails.logger.error "--- [#{name}] Error evaluating formula '#{formula}': #{e.message}"
      @autofill_errors << { kpi: name, report: report.id, as_of: report.as_of, message: "Error evaluating formula '#{formula}': #{e.message}" }
    end
  end

  # Fetches all monthly KPIs with the 'Actual' tag for this specific KPI name and portfolio company.
  # Results are ordered chronologically by the report's as_of date.
  #
  # @return [ActiveRecord::Relation]
  def fetch_related_monthly_kpis
    entity.kpis.approved.joins(:kpi_report).includes(:kpi_report)
          .where(name: name, portfolio_company_id: portfolio_company_id)
          .where(kpi_reports: { tag_list: 'Actual', period: 'Month' })
          .order("kpi_reports.as_of ASC")
  end

  # Groups monthly KPIs by quarter and calculates the sum for each quarter.
  def process_quarterly_cumulatives(related_kpis, force: false)
    kpis_by_quarter = related_kpis.group_by do |kpi|
      [kpi.kpi_report.as_of.year, ((kpi.kpi_report.as_of.month - 1) / 3) + 1]
    end

    kpis_by_quarter.each do |(year, quarter), kpis_in_quarter|
      quarterly_sum = kpis_in_quarter.sum { |kpi| kpi.value.to_f }
      quarter_end = Date.new(year, ((quarter - 1) * 3) + 1, 1).end_of_quarter

      # If the quarter end is in the future and the source monthly KPIs are tagged as 'Actual',
      # skip creating/updating the Quarterly cumulative to avoid generating future-dated Actual records.
      next if quarter_end > Date.current

      process_cumulative_kpi(nil, quarterly_sum, 'Quarter', nil, quarter_end, force: force)
    end
  end

  # Groups monthly KPIs by fiscal year and calculates the YTD sum up to each month.
  # Also creates a 'Year' period KPI if all 12 months of the fiscal year are present.
  def process_yearly_cumulatives(related_kpis, force: false)
    kpis_by_year = related_kpis.group_by { |kpi| fiscal_year_key(kpi.kpi_report.as_of, style: :start_year) }

    kpis_by_year.each_value do |kpis_in_year|
      kpis_in_year.sum { |kpi| kpi.value.to_f }
      # We should use the date of each specific report for YTD to show progress
      # But for 'Year' we want the end of the year.
      kpis_in_year.each_with_index do |kpi, index|
        current_ytd_sum = kpis_in_year[0..index].sum { |k| k.value.to_f }
        as_of = kpi.kpi_report.as_of
        process_cumulative_kpi(nil, current_ytd_sum, 'YTD', nil, as_of, force: force)

        # If it's the 12th month, also create/update the 'Year' record
        process_cumulative_kpi(nil, current_ytd_sum, 'Year', nil, as_of, force: force) if kpis_in_year.size == 12 && index == 11
      end
    end
  end

  # Takes the last monthly value in each quarter and applies it as the Quarterly KPI value.
  def process_quarterly_forward_fill(related_kpis, force: false)
    kpis_by_quarter = related_kpis.group_by do |kpi|
      [kpi.kpi_report.as_of.year, ((kpi.kpi_report.as_of.month - 1) / 3) + 1]
    end

    kpis_by_quarter.each do |(year, quarter), kpis_in_quarter|
      quarter_end = Date.new(year, ((quarter - 1) * 3) + 1, 1).end_of_quarter
      existing = Kpi.approved.joins(:kpi_report).where(name: name, entity_id: entity_id, kpi_reports: { period: 'Quarter', as_of: quarter_end }).last

      # If the quarter end is in the future and the source monthly KPIs are tagged as 'Actual',
      # skip creating/updating the Quarterly forward_fill to avoid generating future-dated Actual records.
      next if quarter_end > Date.current

      if existing.nil? || existing.value.nil? || force
        last_val = kpis_in_quarter.last.value.to_f
        process_cumulative_kpi(nil, last_val, 'Quarter', nil, quarter_end, note: "Auto-generated Forward Fill", force: force)
      end
    end
  end

  # Takes the last monthly value available in the fiscal year and applies it as the YTD KPI value.
  def process_yearly_forward_fill(related_kpis, force: false)
    kpis_by_year = related_kpis.group_by { |kpi| fiscal_year_key(kpi.kpi_report.as_of, style: :start_year) }

    kpis_by_year.each_value do |kpis_in_year|
      last_date = kpis_in_year.last.kpi_report.as_of
      existing = Kpi.approved.joins(:kpi_report).where(name: name, entity_id: entity_id, kpi_reports: { period: 'YTD', as_of: last_date }).last

      if existing.nil? || existing.value.nil? || force
        last_val = kpis_in_year.last.value.to_f
        process_cumulative_kpi(nil, last_val, 'YTD', nil, last_date, note: "Auto-generated Forward Fill", force: force)
      end
    end
  end

  # Core helper that finds or creates the cumulative KPI record for a given period and date.
  #
  # @param _curr_kpi [Kpi] Unused parameter (kept for signature compatibility if needed).
  # @param cumulative_sum [BigDecimal, Float] The calculated value to store.
  # @param period [String] 'Quarter' or 'YTD'.
  # @param _start_date [Date] Unused parameter.
  # @param end_date [Date] The as_of date for the report.
  # @param note [String, nil] Optional note to attach to the KPI.
  # @param user_id [Integer, nil] The user to associate with the report if it needs to be created.
  # @param force [Boolean] If true, updates the value even if it matches the current value.
  def process_cumulative_kpi(_curr_kpi, cumulative_sum, period, _start_date, end_date, note: nil, user_id: nil, force: false)
    note ||= "Auto-generated #{period} cumulative"
    Rails.logger.debug { "Kpi:  [#{name}] Processing #{period} KPI for #{end_date}, value: #{cumulative_sum}" }

    report_for_period = KpiReport.find_by(
      period: period,
      as_of: end_date,
      entity_id: entity_id,
      portfolio_company_id: portfolio_company_id
    )

    cumulative_kpi = report_for_period&.kpis&.approved&.find_by(
      entity_id: entity_id,
      name: name,
      portfolio_company_id: portfolio_company_id
    )

    if cumulative_kpi
      existing_value = cumulative_kpi.value
      same_value = existing_value.to_d.round(6) == cumulative_sum.to_d.round(6)
      return if same_value && !force

      cumulative_kpi.value = cumulative_sum
      cumulative_kpi.notes = note
      cumulative_kpi.save if cumulative_kpi.changed?
      return
    end

    # Fallback to current kpi's report user if user_id not passed
    source_report = respond_to?(:kpi_report) ? kpi_report : nil
    user_id ||= source_report&.user_id

    # We need user_id to create a report. If nil, it might fail validation if user is required.
    # Assuming user might be optional or handled elsewhere if nil.
    # But usually report belongs to user.

    report_for_period ||= KpiReport.find_or_create_by(
      period: period,
      as_of: end_date,
      entity_id: entity_id,
      portfolio_company_id: portfolio_company_id,
      user_id: user_id
    )

    kpi = Kpi.approved.find_or_initialize_by(
      entity_id: entity_id,
      name: name,
      portfolio_company_id: portfolio_company_id,
      kpi_report: report_for_period
    )

    kpi.value = cumulative_sum
    kpi.notes = note
    kpi.save
  end
end
