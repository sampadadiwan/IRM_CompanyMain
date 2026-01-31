module KpiCumulative
  extend ActiveSupport::Concern

  included do
    attr_accessor :cumulation_errors
  end

  # Generates a key for grouping dates by their fiscal year.
  def fiscal_year_key(date, style: :start_year)
    fy_start = start_of_financial_year_date(date, nil_if_not_set: true) || entity.entity_settings.start_of_financial_year_date(date)
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

  # This is used to cumulate/fill/compute the KPI values over time periods like Quarterly and YTD.
  def cumulate(force: false)
    @cumulation_errors = []
    # Fetch mapping to determine the mode
    mapping = investor_kpi_mapping
    mode = mapping&.cumulate || 'blank'

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

  def perform_cumulation(force: false)
    related_kpis = fetch_related_monthly_kpis
    return if related_kpis.empty?

    process_quarterly_cumulatives(related_kpis, force: force)
    process_yearly_cumulatives(related_kpis, force: force)
  end

  def perform_forward_fill(force: false)
    related_kpis = fetch_related_monthly_kpis
    return if related_kpis.empty?

    process_quarterly_forward_fill(related_kpis, force: force)
    process_yearly_forward_fill(related_kpis, force: force)
  end

  def perform_computation(force: false)
    # This should be called last by the job, but we'll implement the logic here
    # Computation logic typically applies to the current period (Quarter/YTD)
    # and uses values of other KPIs in the same report.

    mapping = investor_kpi_mapping
    return if mapping&.cumulate_formula.blank?

    # We need to compute for all existing Quarterly and YTD reports for this PC
    kpi_reports = KpiReport.where(portfolio_company_id: portfolio_company_id)

    kpi_reports.each do |report|
      # Only compute if value is not already present
      existing_kpi = Kpi.approved.find_by(kpi_report: report, name: name, entity_id: entity_id)

      # If the KPI is missing or has no value, we compute it.
      compute_value_for_report(report, mapping.cumulate_formula, force: force) if existing_kpi.nil? || existing_kpi.value.nil? || force
    end
  end

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
        @cumulation_errors << { kpi: name, report: report.id, as_of: report.as_of, message: error_msg }
      end
    rescue StandardError => e
      Rails.logger.error "--- [#{name}] Error evaluating formula '#{formula}': #{e.message}"
      @cumulation_errors << { kpi: name, report: report.id, as_of: report.as_of, message: "Error evaluating formula '#{formula}': #{e.message}" }
    end
  end

  # Fetches monthly KPIs tagged 'Actual', ordered chronologically
  def fetch_related_monthly_kpis
    entity.kpis.approved.joins(:kpi_report).includes(:kpi_report)
          .where(name: name, portfolio_company_id: portfolio_company_id)
          .where(kpi_reports: { tag_list: 'Actual', period: 'Month' })
          .order("kpi_reports.as_of ASC")
  end

  def process_quarterly_cumulatives(related_kpis, force: false)
    kpis_by_quarter = related_kpis.group_by do |kpi|
      [kpi.kpi_report.as_of.year, ((kpi.kpi_report.as_of.month - 1) / 3) + 1]
    end

    kpis_by_quarter.each do |(year, quarter), kpis_in_quarter|
      quarterly_sum = kpis_in_quarter.sum { |kpi| kpi.value.to_f }
      quarter_end = Date.new(year, ((quarter - 1) * 3) + 1, 1).end_of_quarter
      process_cumulative_kpi(nil, quarterly_sum, 'Quarter', nil, quarter_end, force: force)
    end
  end

  def process_yearly_cumulatives(related_kpis, force: false)
    kpis_by_year = related_kpis.group_by { |kpi| fiscal_year_key(kpi.kpi_report.as_of, style: :start_year) }

    kpis_by_year.each_value do |kpis_in_year|
      ytd_sum = kpis_in_year.sum { |kpi| kpi.value.to_f }
      # We use the date of the last monthly report in that FY as the end date for YTD
      # but typically YTD reports are end of month.
      last_date = kpis_in_year.last.kpi_report.as_of
      process_cumulative_kpi(nil, ytd_sum, 'YTD', nil, last_date, force: force)
    end
  end

  def process_quarterly_forward_fill(related_kpis, force: false)
    kpis_by_quarter = related_kpis.group_by do |kpi|
      [kpi.kpi_report.as_of.year, ((kpi.kpi_report.as_of.month - 1) / 3) + 1]
    end

    kpis_by_quarter.each do |(year, quarter), kpis_in_quarter|
      quarter_end = Date.new(year, ((quarter - 1) * 3) + 1, 1).end_of_quarter
      existing = Kpi.approved.joins(:kpi_report).where(name: name, entity_id: entity_id, kpi_reports: { period: 'Quarter', as_of: quarter_end }).last

      if existing.nil? || existing.value.nil? || force
        last_val = kpis_in_quarter.last.value.to_f
        process_cumulative_kpi(nil, last_val, 'Quarter', nil, quarter_end, note: "Auto-generated Forward Fill", force: force)
      end
    end
  end

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

  def process_cumulative_kpi(_curr_kpi, cumulative_sum, period, _start_date, end_date, note: nil, user_id: nil, force: false)
    note ||= "Auto-generated #{period} cumulative"
    Rails.logger.debug { "Kpi:  [#{name}] Processing #{period} KPI for #{end_date}, value: #{cumulative_sum}" }

    cumulative_kpi = Kpi.approved.joins(:kpi_report)
                        .where(entity_id: entity_id, name:, portfolio_company_id: portfolio_company_id)
                        .where(kpi_reports: { period: period })
                        .where(kpi_reports: { as_of: end_date })
                        .last

    if cumulative_kpi
      # Only overwrite if the value is nil or force is true.
      if cumulative_kpi.value.nil? || force
        cumulative_kpi.value = cumulative_sum
        cumulative_kpi.notes = note
        cumulative_kpi.save if cumulative_kpi.changed?
      end
    else
      # Fallback to current kpi's report user if user_id not passed
      user_id ||= respond_to?(:kpi_report) && kpi_report ? kpi_report.user_id : nil

      # We need user_id to create a report. If nil, it might fail validation if user is required.
      # Assuming user might be optional or handled elsewhere if nil.
      # But usually report belongs to user.

      kpi_report = KpiReport.find_or_create_by(period: period, as_of: end_date,
                                               entity_id:, portfolio_company_id:, user_id:)

      kpi = Kpi.approved.find_or_initialize_by(entity_id:, name:, portfolio_company_id:, kpi_report:)
      kpi.value = cumulative_sum
      kpi.notes = note
      kpi.save
    end
  end
end
