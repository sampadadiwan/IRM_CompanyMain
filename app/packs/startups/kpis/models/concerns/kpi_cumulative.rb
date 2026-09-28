# This concern provides methods to automatically calculate and store cumulative KPI values
# (Quarterly and YTD) based on monthly 'Actual' data.
# It supports different modes of operation:
# - :cumulate (summing monthly values)
# - :forward_fill (carrying forward the latest value)
# - :compute (evaluating a custom formula)
#
# NOTE: 'Year' cumulative records are only created when exactly 12 monthly 'Actual'
# records exist within the SAME fiscal year. The fiscal year boundary is defined
# by EntitySetting#start_of_financial_year_date (default: April 1st on the India server,
# January 1st on the US server, per EntitySetting.geo_default_month_offset_for_fy).
#
# Entities that report Actuals directly at Quarter granularity (no monthly 'Actual' data)
# get YTD and Year derived from their quarters instead - see
# #process_quarterly_derived_cumulatives. Any fiscal year that already has monthly Actual
# data is skipped in that path, so the two sources never compute the same period twice.
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
    # When month_offset_for_fy isn't explicitly set, it falls back to
    # EntitySetting.geo_default_month_offset_for_fy (April on the India server, January on US).
    # Dates on/before the fiscal-year-start month belong to the previous year's fiscal year;
    # dates after it belong to the current year's fiscal year.
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
    monthly_years = related_kpis.to_set { |kpi| fiscal_year_key(kpi.kpi_report.as_of, style: :start_year) }

    unless related_kpis.empty?
      process_quarterly_cumulatives(related_kpis, force: force)
      process_yearly_cumulatives(related_kpis, force: force)
    end

    # Some entities report directly at Quarter granularity (no monthly 'Actual' data).
    # Derive YTD (as quarters accumulate) and Year (once all 4 quarters are present) from
    # their sum, but only for fiscal years that don't already have monthly Actual data,
    # so we never compute the same period from both sources.
    process_quarterly_derived_cumulatives(force: force, skip_years: monthly_years)
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
  # entity_id/portfolio_company_id/status/name here are covered by a single composite index
  # (see 20260924160000_add_sort_memory_fix_indexes.rb) so MySQL can satisfy this WHERE with one
  # index lookup instead of an index_merge across the entity_id and portfolio_company_id indexes.
  # The merge itself was never the sort-memory problem (index_merge_intersect doesn't touch
  # sort_buffer_size - it merges already-ordered rowid streams). What matters is that without the
  # composite, the merge step ran against every kpi this entity/company has ever had, and ALL of
  # those rows then had to be filesorted for the ORDER BY kpi_reports.as_of below - a sort that no
  # index on kpis can avoid, since as_of lives on the joined table (see the preload note below).
  # The composite index shrinks the candidate set the unavoidable filesort has to work over, from
  # "every kpi for this entity/company" down to just the ones matching this name too.
  #
  # preload (not includes) deliberately: combining .joins(:kpi_report) with .includes(:kpi_report)
  # makes ActiveRecord eager_load the association (a LEFT OUTER JOIN pulling every kpi_reports
  # column - analysis, json_fields, validation_result, etc - into the same result set that then
  # gets sorted by as_of), which reintroduces the exact wide-row-filesort problem the composite
  # index above doesn't touch. .joins still gives us the INNER JOIN needed for the WHERE and the
  # ORDER BY; .preload loads kpi_report via a separate, narrow "WHERE id IN (...)" query instead,
  # so the sort only ever has to buffer bare `kpis` rows.
  #
  # @return [ActiveRecord::Relation]
  def fetch_related_monthly_kpis
    entity.kpis.approved.joins(:kpi_report).preload(:kpi_report)
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

  # Fetches all quarterly KPIs with the 'Actual' tag for this specific KPI name and portfolio
  # company. These are directly-reported Quarter figures (not auto-generated cumulative ones,
  # which never carry the 'Actual' tag), so this only matches genuine quarterly source data.
  #
  # Same index_merge/sort-memory concern, same composite index, and same eager_load-vs-preload
  # fix as fetch_related_monthly_kpis above.
  #
  # @return [ActiveRecord::Relation]
  def fetch_related_quarterly_kpis
    entity.kpis.approved.joins(:kpi_report).preload(:kpi_report)
          .where(name: name, portfolio_company_id: portfolio_company_id)
          .where(kpi_reports: { tag_list: 'Actual', period: 'Quarter' })
          .order("kpi_reports.as_of ASC")
  end

  # Returns which fiscal quarter (1-4) a date falls into, based on the entity's
  # fiscal year start month (from fiscal_year_key).
  def fiscal_quarter_number(date)
    fy_start = fiscal_year_key(date, style: :range).first
    months_since_start = ((date.year - fy_start.year) * 12) + (date.month - fy_start.month)
    (months_since_start / 3) + 1
  end

  # Groups directly-reported quarterly 'Actual' KPIs by fiscal year and derives:
  #  - a 'YTD' cumulative after each quarter that comes in (sum of Q1..that quarter)
  #  - a 'Year' cumulative once all 4 fiscal quarters are present (sum of Q1..Q4)
  # This covers entities that report at Quarter granularity without underlying monthly
  # 'Actual' data. Fiscal years already covered by monthly data are skipped via `skip_years`
  # so YTD/Year are never computed twice for the same period.
  def process_quarterly_derived_cumulatives(force: false, skip_years: [])
    related_quarters = fetch_related_quarterly_kpis
    return if related_quarters.empty?

    quarters_by_year = related_quarters.group_by { |kpi| fiscal_year_key(kpi.kpi_report.as_of, style: :start_year) }

    quarters_by_year.each do |fiscal_year, kpis_in_year|
      next if skip_years.include?(fiscal_year)

      quarters_present = kpis_in_year.index_by { |kpi| fiscal_quarter_number(kpi.kpi_report.as_of) }

      quarters_present.keys.sort.each do |quarter|
        # YTD only makes sense as a contiguous run from Q1, otherwise a missing earlier
        # quarter would silently be treated as zero.
        next unless (1..quarter).all? { |q| quarters_present.key?(q) }

        as_of = quarters_present[quarter].kpi_report.as_of
        next if as_of > Date.current

        ytd_sum = (1..quarter).sum { |q| quarters_present[q].value.to_f }
        process_cumulative_kpi(nil, ytd_sum, 'YTD', nil, as_of, note: "Auto-generated YTD cumulative (from quarters)", force: force)
      end

      next unless (1..4).all? { |q| quarters_present.key?(q) }

      year_sum = quarters_present.values.sum { |kpi| kpi.value.to_f }
      fy_end = fiscal_year_key(quarters_present[4].kpi_report.as_of, style: :range).last

      next if fy_end > Date.current

      process_cumulative_kpi(nil, year_sum, 'Year', nil, fy_end, note: "Auto-generated Year cumulative (from quarters)", force: force)
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
      # Backfill mapping on existing cumulated KPIs that predate mapping inheritance.
      # Without the mapping the grid view cannot match the KPI to its row and shows N/A.
      cumulative_kpi.investor_kpi_mapping ||= investor_kpi_mapping || fallback_investor_kpi_mapping

      existing_value = cumulative_kpi.value
      same_value = existing_value.to_d.round(6) == cumulative_sum.to_d.round(6)
      return if same_value && !force && !cumulative_kpi.investor_kpi_mapping_id_changed?

      cumulative_kpi.value = cumulative_sum
      cumulative_kpi.notes = note
      # Surface a failed update instead of swallowing it — otherwise the cumulative total
      # silently keeps its old value with no trace of why.
      record_autofill_save_error(cumulative_kpi, period, end_date) if cumulative_kpi.changed? && !cumulative_kpi.save
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

    # Cumulative KPIs inherit the source KPI's mapping (same name/entity, just a different
    # period). Without a mapping the new record fails Kpi's investor_kpi_mapping_id presence
    # validation (required for records created after MAPPING_ID_REQUIRED_FROM) and nothing would
    # be written. Legacy sources that predate mapping assignment may not be linked even though a
    # mapping exists for the company, so fall back to looking it up by standard name.
    # Applied to both new and existing records: existing cumulated KPIs created before mapping
    # inheritance was added may still have a nil mapping_id, which breaks grid view display.
    kpi.investor_kpi_mapping ||= investor_kpi_mapping || fallback_investor_kpi_mapping

    kpi.value = cumulative_sum
    kpi.notes = note
    # A failed save must be surfaced, not swallowed: a silently dropped cumulative means the
    # company's Quarter/YTD/Year totals just stop updating with no trace. The error lands in
    # @autofill_errors, which KpiCumulateJob rolls into its danger toast and error email.
    record_autofill_save_error(kpi, period, end_date) unless kpi.save
  end

  # Legacy source KPIs (created before mapping assignment existed) may drive cumulation without
  # being linked to their mapping. `name` on a cumulating KPI is already the standard KPI name,
  # so the (entity, investor, standard_kpi_name) lookup finds the right mapping to inherit.
  def fallback_investor_kpi_mapping
    InvestorKpiMapping.find_by(entity_id: entity_id, investor_id: portfolio_company_id, standard_kpi_name: name)
  end

  # Records a cumulative KPI that failed to save into @autofill_errors so KpiCumulateJob reports
  # it (danger notification + error email) instead of the failure disappearing silently.
  def record_autofill_save_error(kpi, period, end_date)
    msg = "Could not save #{period} cumulative for '#{name}' as of #{end_date}: #{kpi.errors.full_messages.join(', ')}"
    # A missing mapping is user-fixable — tell them the fix, not just the failure.
    msg += ". Upload a KPI mapping for '#{name}' for this portfolio company." if kpi.errors[:investor_kpi_mapping_id].present?
    Rails.logger.error "--- [#{name}] #{msg}"
    (@autofill_errors ||= []) << { kpi: name, period: period, as_of: end_date, message: msg }
  end
end
