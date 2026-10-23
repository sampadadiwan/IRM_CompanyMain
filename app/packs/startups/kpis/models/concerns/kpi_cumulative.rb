# This concern provides methods to automatically calculate and store cumulative KPI values
# (Quarter, YTD and Year) from a KPI's approved month and Quarter figures.
# It supports different modes of operation:
# - :cumulate (summing figures)
# - :forward_fill (carrying a balance forward)
# - :compute (evaluating a custom formula)
#
# Cumulate and forward fill work in two steps, one fiscal year at a time: KpiCumulationPlanner works out which
# Quarter, YTD and Year rows should exist (pure arithmetic), then #reconcile_cumulative_kpis makes the saved rows match.
# A Quarter, YTD or Year row a person uploaded or entered is never overwritten; only rows marked as calculated
# (Kpi#calculated_cumulative?) are rewritten.
#
# The fiscal year comes from KpiDateUtils.resolve_fiscal_year_start_month (portfolio company, then entity setting,
# then the regional default: April on the India server, January on the US server).
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
    # One definition of the fiscal year: the portfolio company's own setting, then the entity setting, then the
    # regional default (KpiDateUtils). The old lookup asked this Kpi first, which always answered with the
    # regional default, so company and entity settings were never read.
    fy_start = KpiDateUtils.fiscal_year_start(date, fiscal_start_month)
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
    @fiscal_start_month = nil
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

  # 1-based fiscal-year start month for this KPI's company, resolved once per autofill run
  def fiscal_start_month
    @fiscal_start_month ||= KpiDateUtils.resolve_fiscal_year_start_month(portfolio_company, entity_id)
  end

  # Performs cumulation: the planner works out the Quarter, YTD and Year figures from the approved month and Quarter
  # figures, one fiscal year at a time, and the reconciler makes the saved rows match.
  def perform_cumulation(force: false)
    plan_and_reconcile(:sum, force: force)
  end

  # Performs forward fill for balance KPIs (cash, headcount): the same plan-then-reconcile as cumulation, but a figure is
  # the balance at its date rather than a running total. See KpiCumulationPlanner (:last).
  #
  # @param force [Boolean] when true, overwrites existing values
  def perform_forward_fill(force: false)
    plan_and_reconcile(:last, force: force, note: "Auto-generated Forward Fill")
  end

  # The target reports and KPIs process_cumulative_kpi writes into, read once for this KPI name instead of
  # once per (period, as_of). Lives only for one perform_cumulation / perform_forward_fill call (cleared in
  # ensure), so nothing outlives the autofill that read it.
  # E4: without a tag the target lookup matches any tag, so a blank tag keeps the live queries (no lookup).
  # Worked examples H3, E1, E4 - openspec/changes/bulk-path-query-optimisation/business-rules.md
  def with_cumulation_lookup
    tag = kpi_report&.tag_list
    @cumulation_lookup = tag.present? ? build_cumulation_lookup(tag) : nil
    yield
  ensure
    @cumulation_lookup = nil
  end

  def build_cumulation_lookup(tag)
    # First by id per key, as KpiReport.find_by would pick among duplicates (the natural key isn't unique)
    reports = {}
    KpiReport.where(entity_id: entity_id, portfolio_company_id: portfolio_company_id, tag_list: tag, period: %w[Quarter YTD Year])
             .order(:id).each { |report| reports[cumulation_lookup_key(report.period, report.as_of)] ||= report }

    # Reports only, not their KPIs: saving one cumulative KPI runs the RAG cascade, which rewrites the next
    # period's rag_status through a fresh copy (update_column). A KPI object held here would keep the old
    # rag_status, and its own recompute_rag_status! compares against that - so it could skip a write it needs.
    # The KPI is still looked up per target, fresh, as before.
    { tag_list: tag, reports: reports }
  end

  # Periods compared the way MySQL's case-insensitive collation compared them in the find_by this replaces:
  # stored periods are not all one case ('Quarter' vs 'quarter'), and an exact-case miss would send
  # process_cumulative_kpi to find_or_create_by, which also filters on user_id and could create a second report
  def cumulation_lookup_key(period, as_of)
    [period.to_s.downcase, as_of&.to_date]
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

  # G33: the portfolio company's KPI names (standard names, as stored on Kpi#name) that the formula uses,
  # matched as whole words like the replacement below. Memoized for the reports of one computation.
  # G38: unscope(:order) — InvestorKpiMapping's default scope orders by position, and MySQL rejects
  # DISTINCT with an ORDER BY on a column it does not select (SQLite, the test DB, accepts it)
  def formula_components(formula)
    @formula_components ||= {}
    @formula_components[formula] ||= begin
      names = InvestorKpiMapping.where(investor_id: investor_kpi_mapping&.investor_id)
                                .unscope(:order).distinct.pluck(:standard_kpi_name) - [name]
      # Longest first, blanking each match, so a name inside a longer one ("Cash" in "Operating Cash
      # Flow", "Others" in "Others Mgt Opn Trainers") is not taken as a component of its own
      remaining = formula.dup
      names.sort_by { |n| -n.length }.select { |n| remaining.gsub!(/\b#{Regexp.escape(n)}\b/, ' ') }
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

    # G33 (client onboarding): a report holding none of the formula's KPIs cannot hold this one either —
    # a P&L sum on a balance-sheet-only report. Skip it; only a partial set is an error (below).
    components = formula_components(formula)
    missing = components - kpis_in_report.keys
    return if components.any? && missing.size == components.size

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
        process_cumulative_kpi(nil, computed_val, report.period, nil, report.as_of, note: "Auto-generated Computed", user_id: report.user_id, force: force, tag_list: report.tag_list)
      else
        error_msg = "Invalid formula after replacement for report #{report.id} (#{report.period} #{report.as_of}): #{clean_formula}"
        # G33: say which KPIs the report is missing
        error_msg += " — missing #{missing.join(', ')}" if missing.any?
        Rails.logger.error "--- [#{name}] #{error_msg}"
        @autofill_errors << { kpi: name, report: report.id, as_of: report.as_of, message: error_msg }
      end
    rescue StandardError => e
      Rails.logger.error "--- [#{name}] Error evaluating formula '#{formula}': #{e.message}"
      @autofill_errors << { kpi: name, report: report.id, as_of: report.as_of, message: "Error evaluating formula '#{formula}': #{e.message}" }
    end
  end

  # Fetches all monthly KPIs matching this KPI's report tag (Actual/Budget/IC) for the same
  # name and portfolio company. Results are ordered chronologically by the report's as_of date.
  # Uses kpi_report.tag_list so cumulation stays within the same tag family — Budget monthly
  # KPIs cumulate into Budget quarterly/YTD, IC into IC, etc.
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
          .where(kpi_reports: { tag_list: kpi_report.tag_list, period: 'Month' })
          .order("kpi_reports.as_of ASC")
  end

  # Plans the Quarter, YTD and Year rows this KPI should have and saves them.
  # @param mode [Symbol] :sum (cumulate) or :last (forward fill), see KpiCumulationPlanner
  def plan_and_reconcile(mode, force: false, note: nil)
    with_cumulation_lookup do
      existing = fetch_existing_cumulative_kpis.to_a
      planned = KpiCumulationPlanner.plan(
        months: fetch_related_monthly_kpis.map { |kpi| { as_of: kpi.kpi_report.as_of, value: kpi.value } },
        quarters: existing.select { |kpi| kpi.kpi_report.period.casecmp?("Quarter") }
                          .map { |kpi| { as_of: kpi.kpi_report.as_of, value: kpi.value, calculated: kpi.calculated_cumulative? } },
        fy_start_month: fiscal_start_month, mode: mode, today: Date.current, tag: kpi_report.tag_list
      )
      reconcile_cumulative_kpis(planned, existing, force: force, note: note)
    end
  end

  # Makes the saved Quarter, YTD and Year rows match what the planner says should exist: adds the missing rows, updates
  # the ones whose value differs and removes calculated rows that are no longer expected. A row a person wrote is never
  # updated or removed. Everything for this KPI runs in one transaction, so a failure leaves no half-applied walk.
  #
  # @param expected [Array<Hash>] the planner's rows, [{ period:, as_of:, value: }]
  # @param existing [Array<Kpi>] the approved Quarter, YTD and Year rows already saved, with their reports loaded
  # @param note [String, nil] note for written rows (process_cumulative_kpi's default when nil)
  def reconcile_cumulative_kpis(expected, existing, force: false, note: nil)
    existing_by_key = existing.index_by { |kpi| cumulation_lookup_key(kpi.kpi_report.period, kpi.kpi_report.as_of) }
    expected_keys = expected.to_set { |row| cumulation_lookup_key(row[:period], row[:as_of]) }
    @autofill_errors ||= []
    errors_before = @autofill_errors.size
    removed = []

    Kpi.transaction(requires_new: true) do
      expected.each do |row|
        current = existing_by_key[cumulation_lookup_key(row[:period], row[:as_of])]
        # E5, E14: a figure a person uploaded or entered is never overwritten. This is decided here, not in
        # process_cumulative_kpi, because the compute path also calls that for every period and keeps its own rows.
        next if current && !current.calculated_cumulative?

        process_cumulative_kpi(nil, row[:value], row[:period], nil, row[:as_of], note: note, force: force)
      end

      # E12, E13: a calculated row the plan no longer expects goes (hard delete: Kpi has no audit trail). A row a person
      # wrote is not calculated, so it is never here (E14).
      existing.each do |kpi|
        next unless kpi.calculated_cumulative?
        next if expected_keys.include?(cumulation_lookup_key(kpi.kpi_report.period, kpi.kpi_report.as_of))

        if kpi.destroy
          removed << kpi
          Rails.logger.info "--- [#{name}] Removed #{kpi.kpi_report.period} #{kpi.kpi_report.as_of} (no longer expected)"
        else
          record_autofill_destroy_error(kpi)
        end
      end

      # X1: any failure above undoes this KPI's whole reconcile; the others in the job are unaffected
      if @autofill_errors.size > errors_before
        removed.clear
        raise ActiveRecord::Rollback
      end
    end

    Rails.logger.info "--- [#{name}] Reconciled #{expected.size} expected rows, removed #{removed.size}"
    refresh_rag_status_after_removal(removed)
  end

  # A save re-judges the rows that were judged against it (Kpi#cascade_dependent_rag_recompute!), a delete did not.
  # Once the removal has committed, do it for each removed row, and only where the KPI has RAG rules (E37).
  def refresh_rag_status_after_removal(removed)
    removed.each do |kpi|
      kpi.cascade_dependent_rag_recompute! if kpi.investor_kpi_mapping&.rag_configured?
    end
  end

  # The approved Quarter, YTD and Year rows already saved for this name, company and tag. The planner reads the Quarter
  # ones as input (uploaded ones count, calculated ones do not) and the reconciler compares all of them with what should
  # exist. Same preload-not-includes and composite-index reasoning as fetch_related_monthly_kpis above.
  #
  # @return [ActiveRecord::Relation]
  def fetch_existing_cumulative_kpis
    entity.kpis.approved.joins(:kpi_report).preload(:kpi_report, :investor_kpi_mapping)
          .where(name: name, portfolio_company_id: portfolio_company_id)
          .where(kpi_reports: { tag_list: kpi_report.tag_list, period: Kpi::CUMULATIVE_PERIODS })
          .order("kpi_reports.as_of ASC")
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
  # @param tag_list [String, nil] report tag (Actual/Budget/IC) to scope the target report lookup.
  #   Callers in the cumulation/forward_fill path pass nil (falls back to self.kpi_report.tag_list);
  #   the compute path passes the report's tag explicitly because the in-memory Kpi has no kpi_report.
  def process_cumulative_kpi(_curr_kpi, cumulative_sum, period, _start_date, end_date, note: nil, user_id: nil, force: false, tag_list: nil)
    note ||= "Auto-generated #{period} cumulative"
    tag_list ||= kpi_report&.tag_list
    Rails.logger.debug { "Kpi:  [#{name}] Processing #{period} KPI for #{end_date}, value: #{cumulative_sum}, tag: #{tag_list}" }

    # The autofill's lookup (with_cumulation_lookup) answers the report find below when it was read for this
    # tag; an explicit other tag (the compute path) or a blank tag (E4) asks the database as before
    lookup = @cumulation_lookup if @cumulation_lookup && tag_list.present? && tag_list == @cumulation_lookup[:tag_list]
    lookup_key = cumulation_lookup_key(period, end_date)

    find_conditions = { period: period, as_of: end_date, entity_id: entity_id, portfolio_company_id: portfolio_company_id }
    find_conditions[:tag_list] = tag_list if tag_list.present?
    report_for_period = lookup ? lookup[:reports][lookup_key] : KpiReport.find_by(find_conditions)

    # Fresh every time (not from the lookup): see build_cumulation_lookup for why KPIs aren't held
    cumulative_kpi = report_for_period&.kpis&.approved&.find_by(
      entity_id: entity_id,
      name: name,
      portfolio_company_id: portfolio_company_id
    )

    if cumulative_kpi
      # Backfill mapping on existing cumulated KPIs that predate mapping inheritance.
      # Without the mapping the grid view cannot match the KPI to its row and shows N/A.
      cumulative_kpi.investor_kpi_mapping ||= investor_kpi_mapping || fallback_investor_kpi_mapping
      # A legacy calculated row (note prefix, no marker) gets the marker when it is kept, not only when it changes
      cumulative_kpi.source = Kpi::AUTO_CUMULATION_SOURCE if cumulative_kpi.calculated_cumulative?

      existing_value = cumulative_kpi.value
      same_value = existing_value.to_d.round(6) == cumulative_sum.to_d.round(6)
      return if same_value && !force && !cumulative_kpi.changed?

      cumulative_kpi.source = Kpi::AUTO_CUMULATION_SOURCE
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

    create_conditions = { period: period, as_of: end_date, entity_id: entity_id, portfolio_company_id: portfolio_company_id, user_id: user_id }
    create_conditions[:tag_list] = tag_list if tag_list.present?
    report_for_period ||= KpiReport.find_or_create_by(create_conditions)
    # E1: a report created here is what a later step's find_by would now return - add it to the lookup
    # (only once saved: a report that failed to save would not be found by find_by either)
    lookup[:reports][lookup_key] ||= report_for_period if lookup && report_for_period.persisted?

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

    kpi.source = Kpi::AUTO_CUMULATION_SOURCE
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

  def record_autofill_destroy_error(kpi)
    msg = "Could not remove #{kpi.kpi_report.period} cumulative for '#{name}' as of #{kpi.kpi_report.as_of}: #{kpi.errors.full_messages.join(', ')}"
    Rails.logger.error "--- [#{name}] #{msg}"
    (@autofill_errors ||= []) << { kpi: name, period: kpi.kpi_report.period, as_of: kpi.kpi_report.as_of, message: msg }
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
