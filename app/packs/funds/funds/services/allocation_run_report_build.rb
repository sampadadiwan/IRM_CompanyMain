# Runs the allocation run checker over one finished AllocationRun and writes the result into
# its AllocationRunReport. See docs/business_requirements/allocation_run_checker.md.
#
#   AllocationRunReportBuild.call(report: report)
#
# Only sections 1 (did the run happen correctly) and 2 (do the numbers add up) are built —
# section 3 (do the numbers look reasonable) is not implemented.
#
# Every check is arithmetic or a lookup against the primary database, so the same run always
# produces the same answer. The operation itself never fails: a run that is riddled with
# problems is still a valid, fully described report. Only an unexpected exception — caught by
# AllocationRunReportJob — leaves the report in Error.
#
# Each check deliberately reproduces the engine's own query rather than a tidier version of
# it, because the point is to detect drift between what the engine computed at run time and
# what is in the ledger now. Where a check departs from the engine, the comment says why.
class AllocationRunReportBuild < Trailblazer::Operation
  # Decimal amounts are summed by the database, so an exact match is expected; the epsilon
  # absorbs last-place noise from formula chains involving division (percentages, FX rates),
  # which can leave a remainder of a few millionths after DECIMAL(30,8) arithmetic — bigger
  # than a single last-place unit, but many orders of magnitude below a cent. 0.005 is half
  # the smallest unit `fmt` displays (2dp), so a difference this check now passes always
  # rounds to "0.00" on screen too — no more "the report says Fail but I see no difference".
  AMOUNT_EPSILON = BigDecimal("0.005")

  # ComputeCustomPercentage rounds to a float before storing, so a fund with several thousand
  # folios can legitimately land a little either side of 100.
  PERCENTAGE_EPSILON = BigDecimal("0.01")

  # The entry_type ComputeCustomPercentage stamps on every percentage it generates.
  PERCENTAGE_ENTRY_TYPE = "Percentage".freeze

  # Pre/post-run check kinds as RunChecks stores them, with the finding code and label each gets.
  RUN_CHECK_KINDS = { "pre" => ["1.5", "Pre-run"], "post" => ["1.6", "Post-run"] }.freeze

  # RunChecks' "warn" is the report's "warn"; every other result name is already a severity.
  RUN_CHECK_SEVERITY = { "pass" => "pass", "warn" => "warn", "fail" => "fail", "skipped" => "skipped" }.freeze

  # What RunFormulas sets when it starts, and leaves behind if the worker dies mid-run.
  RUNNING_STATUS = "Pending".freeze

  # Every check is computed after the fact from the ledger, so it can be run over a run of any
  # age — but two of the columns it reads did not always exist, and a run older than they are
  # would be judged on evidence that was never recorded.
  #
  # `account_entries.allocation_run_id` arrives with 20250329041725_add_allocation_run_to_
  # account_entry. Entries written before it carry no run id, so checks 1.2, 1.3 and 2.1 —
  # the ones that ask "what did THIS run produce?" — would find nothing and report that every
  # formula was silent and every folio was missed. The allocation screen already draws the same
  # line for its "Account Entries" link.
  ENTRY_TAGGING_STARTED_ON = Date.new(2025, 3, 29)

  # `allocation_runs.status` arrives with 20240728065555_add_status_to_allocation_run. A run
  # older than that has a NULL status because the column did not exist, not because it failed.
  STATUS_RECORDED_FROM = Date.new(2024, 7, 28)

  # One row of the report. severity is "pass", "warn", "fail" or "skipped"; group is "run"
  # (section 1) or "arithmetic" (section 2).
  #
  # The affected folios and entry names are stored as a `columns` list plus a `rows` list of
  # value arrays, not as hashes: MySQL's JSON type reorders an object's keys, so a report
  # written as hashes would come back with its columns shuffled (and shuffled differently
  # from SQLite, which preserves insertion order).
  # `filters` runs parallel to `rows`: each entry is either nil or a list of
  # [field, predicate, value] triples ready for ransack_query_params_multiple, narrowing the
  # account entries screen to exactly what that row is about. The operation builds them rather
  # than the view because only it knows each check's window — 2.1 spans the period, 2.2 runs
  # from inception, 2.3 is the period end alone. A reviewer looking at "Setup Fee is out by
  # 599" wants the entries behind it, not a search box.
  Finding = Struct.new(:code, :title, :group, :severity, :summary, :columns, :rows, :filters,
                       :truncated, keyword_init: true) do
    def to_h
      { "code" => code, "title" => title, "group" => group, "severity" => severity,
        "summary" => summary, "columns" => columns || [], "rows" => rows || [],
        "filters" => filters || [], "truncated" => truncated.to_i }
    end
  end

  step :setup
  step :check_run_status          # 1.1
  step :check_silent_formulas     # 1.2
  step :check_missing_folios      # 1.3
  step :check_period_continuity   # 1.4
  step :check_run_checks          # 1.5.n / 1.6.n
  step :check_fund_totals         # 2.1
  step :check_cumulative_totals   # 2.2
  step :check_percentages         # 2.3
  step :persist

  def setup(ctx, report:, **)
    ctx[:started_at]      = Time.current
    ctx[:findings]        = []
    ctx[:allocation_run]  = report.allocation_run
    ctx[:fund]            = report.fund
    # A run with run_allocations off only generated investor statements — it produced no
    # account entries at all, so every check below section 1.1 has nothing to look at.
    ctx[:allocations_run] = ctx[:allocation_run].run_allocations?
    # A run still at "Pending" has written only part of its entries. Reconciling a half-written
    # ledger produces a page of failures that say nothing about the run, so every check below
    # 1.1 sits this one out and the reviewer is told to check again when it has finished.
    ctx[:ledger_complete] = ctx[:allocations_run] && ctx[:allocation_run].status != RUNNING_STATUS
    # A run stopped by a failed pre-run check never deleted, loaded or computed anything, so it
    # has no entries of its own either: 1.2 would list every formula as silent and 1.3 every folio
    # as missed. The stored results are the only evidence; they are what check_run_checks shows.
    ctx[:pre_checks_failed] = report.run_checks.any? { |r| r["kind"] == "pre" && r["result"] == "fail" }
    ctx[:ledger_complete] &&= !ctx[:pre_checks_failed]
    # Whether this run is young enough for the columns each check reads to have existed.
    created_on = ctx[:allocation_run].created_at&.to_date || Date.current
    ctx[:entries_tagged] = created_on >= ENTRY_TAGGING_STARTED_ON
    ctx[:status_recorded] = created_on >= STATUS_RECORDED_FROM
    true
  end

  ############################################################
  # 1. Did the run happen correctly?
  ############################################################

  # 1.1 The engine sets status "Success" only after every formula finished; any other value is
  # the error message of the step that stopped it (see RunFormulas), and a blank status means
  # the run never got as far as reporting one.
  def check_run_status(ctx, allocation_run:, **)
    unless ctx[:allocations_run]
      return skipped(ctx, "1.1", "The run finished with status Success",
                     "This run did not run allocation formulas, so it never reports a status.")
    end

    if allocation_run.status == "Success"
      pass(ctx, "1.1", "The run finished with status Success", "Status: Success.")
    elsif allocation_run.status == RUNNING_STATUS
      # RunFormulas sets "Pending" when it starts and "Success" when it ends, so this is either
      # a run that is still going or one whose worker died without reporting. It cannot be told
      # which, and calling a healthy in-flight run a failure would be worse than saying so.
      warning(ctx, "1.1", "The run finished with status Success",
              "This run has not finished — it is either still running or it stopped without " \
              "reporting. Check it again once it has finished.")
    elsif allocation_run.status.present?
      failure(ctx, "1.1", "The run finished with status Success", "The run stopped with: #{allocation_run.status}")
    elsif !ctx[:status_recorded]
      skipped(ctx, "1.1", "The run finished with status Success", predates_message(allocation_run, "record a run's status"))
    else
      failure(ctx, "1.1", "The run finished with status Success",
              "The run never reported a status, so it did not finish.")
    end
  end

  # 1.5.n / 1.6.n The fund's own pre-run and post-run checks (FundFormulas with rule type
  # PreRunCheck / PostRunCheck). Unlike every other check here they cannot be recomputed from the
  # ledger -- they describe the data at the moment the run happened -- so they are read back from
  # what AccountEntryAllocation::RunFormulas stored on this report, one finding per check, rows
  # and all. See docs/business_requirements/allocation_run_checks.md.
  #
  # The engine only stores results when a check failed or warned. For a kind with nothing stored,
  # a single summary finding says what can still be concluded from the run's status.
  def check_run_checks(ctx, report:, allocation_run:, fund:, **)
    stored = report.run_checks

    RUN_CHECK_KINDS.each do |kind, (code, label)|
      results = stored.select { |r| r["kind"] == kind }
      if results.any?
        results.each_with_index { |result, index| add_run_check(ctx, "#{code}.#{index + 1}", result) }
      else
        summarise_unrecorded_run_checks(ctx, kind, code, label, allocation_run, fund)
      end
    end
    true
  end

  # 1.2 The formulas in scope are exactly the ones the engine would have picked up for this
  # run's rule_for and tags (RunFormulas#get_formulas). A formula that produced nothing is
  # usually a condition that never matched, which is legitimate — hence a warning.
  def check_silent_formulas(ctx, allocation_run:, fund:, **)
    return skipped_no_allocations(ctx, "1.2", "Every enabled formula produced at least one entry") unless ctx[:ledger_complete]
    return skipped_untagged(ctx, "1.2", "Every enabled formula produced at least one entry") unless ctx[:entries_tagged]

    # Checks never write entries, so every one of them would otherwise be listed as silent.
    formulas = FundFormula.enabled.without_run_checks.where(fund_id: fund.id).order(sequence: :asc)
    formulas = formulas.where(rule_for: allocation_run.rule_for) if allocation_run.rule_for.present?
    # Split exactly as RunFormulas#get_formulas does — no strip. with_tags matches with
    # LIKE '%tag%', so stripping would widen the match and pull in formulas the run never had
    # in scope, which this check would then report as having produced nothing.
    formulas = formulas.with_tags(allocation_run.tag_list.split(",")) if allocation_run.tag_list.present?
    formulas = formulas.to_a

    if formulas.empty?
      return skipped(ctx, "1.2", "Every enabled formula produced at least one entry",
                     "No enabled formula matched this run's scope, so there was nothing to produce entries.")
    end

    produced = AccountEntry.where(allocation_run_id: allocation_run.id).distinct.pluck(:fund_formula_id).compact.to_set
    silent   = formulas.reject { |f| produced.include?(f.id) }

    if silent.empty?
      pass(ctx, "1.2", "Every enabled formula produced at least one entry",
           "All #{formulas.size} formulas in scope produced entries.")
    else
      warning(ctx, "1.2", "Every enabled formula produced at least one entry",
              "#{silent.size} of #{formulas.size} formulas in scope produced no entries.",
              silent.map { |f| { "Formula" => f.name, "Entry type" => f.entry_type, "Sequence" => f.sequence } })
    end
  end

  # 1.3 The folios the engine would have loaded (RunFormulas#get_commitments): every commitment
  # dated on or before the period end, or the explicit sample list when the fund carries one.
  #
  # A "sample" run — the debugging option that caps the engine at three folios — is not
  # recorded on allocation_runs, so it cannot be told apart here from a run that genuinely
  # missed every other folio. That is exactly what this warning is for.
  def check_missing_folios(ctx, allocation_run:, fund:, **)
    return skipped_no_allocations(ctx, "1.3", "Every folio committed by the period end received entries") unless ctx[:ledger_complete]
    return skipped_untagged(ctx, "1.3", "Every folio committed by the period end received entries") unless ctx[:entries_tagged]

    sample_ids = fund.custom_fields[:sample_commitment_ids_for_allocation]
    expected = if sample_ids.present?
                 CapitalCommitment.where(fund_id: fund.id, id: sample_ids.split(",").map(&:strip))
               else
                 CapitalCommitment.where(fund_id: fund.id, commitment_date: ..allocation_run.end_date)
               end

    expected_ids = expected.distinct.pluck(:id)
    if expected_ids.empty?
      return skipped(ctx, "1.3", "Every folio committed by the period end received entries",
                     "The fund has no commitments dated on or before #{l_date(allocation_run.end_date)}.")
    end

    # Deduped in SQL — the fund's whole ledger for the run would be far too much to load.
    produced_ids = AccountEntry.where(allocation_run_id: allocation_run.id)
                               .where.not(capital_commitment_id: nil)
                               .distinct.pluck(:capital_commitment_id)
    missing_ids = expected_ids - produced_ids

    if missing_ids.empty?
      pass(ctx, "1.3", "Every folio committed by the period end received entries",
           "All #{expected_ids.size} folios received entries.")
    else
      shown = CapitalCommitment.where(id: missing_ids.first(AllocationRunReport::MAX_ROWS_PER_FINDING))
                               .pluck(:folio_id, :commitment_date)
      warning(ctx, "1.3", "Every folio committed by the period end received entries",
              "#{missing_ids.size} of #{expected_ids.size} folios received no entries from this run.",
              shown.map { |folio_id, date| { "Folio" => folio_id, "Committed" => l_date(date) } },
              missing_ids.size - shown.size,
              shown.map { |folio_id, _date| folio_filter(allocation_run, folio_id) })
    end
  end

  # 1.4 A locked run is the fund's accounting history, so the next period should start the day
  # after the last locked one ended. A gap loses a period; an overlap double-counts it.
  def check_period_continuity(ctx, allocation_run:, fund:, **)
    title = "The period follows on from the previous locked run"
    # A statements-only run is not part of the fund's accounting sequence, and re-generating
    # statements for a period that is already locked is a normal thing to do — warning that it
    # "overlaps a locked run" would describe nothing wrong.
    unless ctx[:allocations_run]
      return skipped(ctx, "1.4", title,
                     "This run did not run allocation formulas, so its period is not part of the accounting sequence.")
    end

    overlapping = AllocationRun.where(fund_id: fund.id).locked
                               .where.not(id: allocation_run.id)
                               .where(start_date: ..allocation_run.end_date, end_date: allocation_run.start_date..)
                               .order(start_date: :asc).first
    if overlapping
      return warning(ctx, "1.4", title,
                     "This period overlaps a locked run.",
                     [{ "Locked run" => "#{l_date(overlapping.start_date)} – #{l_date(overlapping.end_date)}",
                        "This run" => "#{l_date(allocation_run.start_date)} – #{l_date(allocation_run.end_date)}" }])
    end

    previous = AllocationRun.where(fund_id: fund.id).locked
                            .where.not(id: allocation_run.id)
                            .where(end_date: ...allocation_run.start_date)
                            .order(end_date: :desc).first
    return skipped(ctx, "1.4", title, "There is no earlier locked run on this fund to follow on from.") if previous.nil?

    expected_start = previous.end_date + 1
    if allocation_run.start_date == expected_start
      pass(ctx, "1.4", title,
           "Starts #{l_date(allocation_run.start_date)}, the day after the previous locked run ended.")
    else
      gap_days = (allocation_run.start_date - expected_start).to_i
      warning(ctx, "1.4", title,
              "There is a #{gap_days.abs}-day gap between the previous locked run and this one.",
              [{ "Previous locked run ended" => l_date(previous.end_date),
                 "Expected start" => l_date(expected_start),
                 "Actual start" => l_date(allocation_run.start_date) }])
    end
  end

  ############################################################
  # 2. Do the numbers add up?
  ############################################################

  # 2.1 RollupAsFundAccountEntry creates each fund-level entry as the sum of the fund's
  # non-cumulative entries for that name and entry type over the period. The two therefore
  # agreed the moment the run finished; a mismatch now means the ledger moved underneath the
  # rollup — an entry edited, deleted, or added by a later run over the same window.
  #
  # The folio-side query has to mirror the engine's exactly: it is NOT scoped to this run's
  # allocation_run_id (the rollup sums whatever is in the window, whoever put it there) and it
  # does NOT exclude fund-level rows (portfolio-investment entries carry no commitment and are
  # part of that sum).
  def check_fund_totals(ctx, allocation_run:, fund:, **)
    title = "Each fund-level total equals the sum of its folio entries"
    return skipped_no_allocations(ctx, "2.1", title) unless ctx[:ledger_complete]
    return skipped_untagged(ctx, "2.1", title) unless ctx[:entries_tagged]

    # parent_id: nil is what separates a rollup from the other fund-level cumulative entries a
    # run writes. GeneratePortfolioNumbersForFund and AllocateForPortfolioCompany (with
    # for_folios false) both create rows with no commitment, cumulative true, generated true,
    # this run's id and this reporting date — one per portfolio company, all sharing a name.
    # Without this filter they would be grouped together and compared against folio entries
    # that do not exist, failing a perfectly healthy run. Only the rollup step writes a
    # fund-level cumulative with no parent.
    rollups = AccountEntry.fund_entries
                          .where(fund_id: fund.id, entity_id: fund.entity_id,
                                 reporting_date: allocation_run.end_date,
                                 generated: true, cumulative: true, parent_id: nil,
                                 allocation_run_id: allocation_run.id)
                          .group(:name, :entry_type).sum(:amount_cents)

    return skipped(ctx, "2.1", title, "This run produced no fund-level rollup entries.") if rollups.empty?

    mismatches = []
    rollups.each do |(name, entry_type), fund_total|
      folio_total = AccountEntry.where(fund_id: fund.id, entity_id: fund.entity_id,
                                       name: name, entry_type: entry_type,
                                       generated: true, cumulative: false)
                                .where(reporting_date: allocation_run.start_date..allocation_run.end_date)
                                .sum(:amount_cents)
      difference = fund_total - folio_total
      next if difference.abs <= AMOUNT_EPSILON

      mismatches << { "Entry name" => name, "Entry type" => entry_type,
                      "Fund total" => fmt(fund_total), "Sum of entries" => fmt(folio_total),
                      "Difference" => fmt(difference),
                      # Not shown as a column — carried out to the drill-down link below.
                      :filter => period_filter(allocation_run, name: name, entry_type: entry_type) }
    end

    if mismatches.empty?
      pass(ctx, "2.1", title, "All #{rollups.size} fund-level totals match the entries beneath them.")
    else
      shown = mismatches.first(AllocationRunReport::MAX_ROWS_PER_FINDING)
      failure(ctx, "2.1", title,
              "#{mismatches.size} of #{rollups.size} fund-level totals do not match the entries beneath them.",
              shown.map { |row| row.except(:filter) },
              mismatches.size - AllocationRunReport::MAX_ROWS_PER_FINDING,
              shown.pluck(:filter))
    end
  end

  # 2.2 CommitmentAccountEntry#rollup_account_entries builds a folio's cumulative entry as the
  # sum of every non-cumulative entry for that name and entry type from inception up to the
  # period end — not as "last period's cumulative plus this period's movement". Checking it
  # from inception is the same test where nothing changed, and a stronger one where something
  # did: it also catches an entry back-dated into an already-locked period.
  #
  # These rows cannot be found by allocation_run_id — CumulateAccountEntries inserts them
  # without one (only BulkInsertData sets it) — so they are found by fund and period end, the
  # way the engine itself looks them up.
  def check_cumulative_totals(ctx, allocation_run:, fund:, **)
    title = "Each folio's cumulative equals the entries that make it up"
    return skipped_no_allocations(ctx, "2.2", title) unless ctx[:ledger_complete]

    # parent_id: nil for the same reason as 2.1, and it matters more here:
    # AllocateForPortfolioCompany-Folio writes one cumulative row per portfolio company PER
    # commitment, all sharing a name and reporting date. Grouped by commitment they would be
    # added together and compared against that one folio's entries — a guaranteed mismatch.
    # rollup_account_entries, which is what this check reconciles, sets no parent.
    cumulative_scope = AccountEntry.where(fund_id: fund.id, entity_id: fund.entity_id,
                                          reporting_date: allocation_run.end_date,
                                          generated: true, cumulative: true, parent_id: nil)
                                   .where.not(capital_commitment_id: nil)

    pairs = cumulative_scope.distinct.pluck(:name, :entry_type)
    return skipped(ctx, "2.2", title, "This run produced no folio-level cumulative entries.") if pairs.empty?

    mismatches = []
    checked = 0
    # One pair at a time: a fund with thousands of folios and dozens of entry names would
    # otherwise build a single hash with hundreds of thousands of keys.
    pairs.each do |name, entry_type|
      actual = cumulative_scope.where(name: name, entry_type: entry_type)
                               .group(:capital_commitment_id).sum(:amount_cents)
      # No `generated` filter — the engine sums imported entries into the cumulative too.
      expected = AccountEntry.where(fund_id: fund.id, name: name, entry_type: entry_type,
                                    cumulative: false, capital_commitment_id: actual.keys)
                             .where(reporting_date: ..allocation_run.end_date)
                             .group(:capital_commitment_id).sum(:amount_cents)

      actual.each do |commitment_id, cumulative_amount|
        checked += 1
        difference = cumulative_amount - (expected[commitment_id] || 0)
        next if difference.abs <= AMOUNT_EPSILON

        mismatches << { "commitment_id" => commitment_id, "Entry name" => name,
                        "Cumulative" => fmt(cumulative_amount),
                        "Sum of entries" => fmt(expected[commitment_id] || 0),
                        "Difference" => fmt(difference) }
      end
    end

    return pass(ctx, "2.2", title, "All #{checked} folio cumulative entries match the entries beneath them.") if mismatches.empty?

    shown = mismatches.first(AllocationRunReport::MAX_ROWS_PER_FINDING)
    failure(ctx, "2.2", title,
            "#{mismatches.size} of #{checked} folio cumulative entries do not match the entries beneath them.",
            with_folio_ids(shown),
            mismatches.size - AllocationRunReport::MAX_ROWS_PER_FINDING,
            cumulative_filters(allocation_run, shown))
  end

  # 2.3 ComputeCustomPercentage divides each folio's amount by the fund total, so the folios
  # under one percentage name must add up to 100. The one legitimate exception is a base field
  # that summed to zero: the engine then writes 0 for every folio rather than dividing by zero.
  def check_percentages(ctx, allocation_run:, fund:, **)
    title = "Percentage allocations across folios sum to 100%"
    return skipped_no_allocations(ctx, "2.3", title) unless ctx[:ledger_complete]

    totals = AccountEntry.where(fund_id: fund.id, entity_id: fund.entity_id,
                                entry_type: PERCENTAGE_ENTRY_TYPE,
                                reporting_date: allocation_run.end_date,
                                generated: true, cumulative: false)
                         .where.not(capital_commitment_id: nil)
                         .group(:name).sum(:amount_cents)

    return skipped(ctx, "2.3", title, "This run produced no percentage entries.") if totals.empty?

    mismatches = totals.filter_map do |name, total|
      # All-zero is how the engine records "the base field summed to zero", not a defect.
      next if total.zero?
      next if (total - 100).abs <= PERCENTAGE_EPSILON

      { "Entry name" => name, "Sums to" => "#{fmt(total)}%", "Difference from 100%" => fmt(total - 100),
        :filter => end_date_filter(allocation_run, name: name, entry_type: PERCENTAGE_ENTRY_TYPE) }
    end

    if mismatches.empty?
      pass(ctx, "2.3", title, "All #{totals.size} percentage allocations sum to 100%.")
    else
      shown = mismatches.first(AllocationRunReport::MAX_ROWS_PER_FINDING)
      failure(ctx, "2.3", title,
              "#{mismatches.size} of #{totals.size} percentage allocations do not sum to 100%.",
              shown.map { |row| row.except(:filter) },
              mismatches.size - AllocationRunReport::MAX_ROWS_PER_FINDING,
              shown.pluck(:filter))
    end
  end

  ############################################################
  # Result
  ############################################################

  # The worst finding decides the report: any Fail makes the report Fail, otherwise any Warn
  # makes it Warn. Skipped checks never change the result.
  def persist(ctx, report:, **)
    findings = ctx[:findings]
    worst = findings.map { |f| AllocationRunReport::SEVERITY_RANK[f.severity] }.max || 0
    status = case worst
             when AllocationRunReport::SEVERITY_RANK["fail"] then "Fail"
             when AllocationRunReport::SEVERITY_RANK["warn"] then "Warn"
             else "Pass"
             end

    # Merged into what is stored now, not what was loaded when this build started: the allocation
    # engine can record run_checks on this row while the build is running, and a wholesale
    # replace from the stale copy would erase them for good.
    stored = report.class.where(id: report.id).pick(:json_fields) || {}
    report.update!(
      status: status,
      checked_at: Time.current,
      message: nil,
      json_fields: stored.merge(
        "findings" => findings.map(&:to_h),
        "duration_ms" => ((Time.current - ctx[:started_at]) * 1000).round
      )
    )
    true
  end

  private

  # Adds the folio each mismatched cumulative belongs to, resolved in one query rather than
  # per row, and drops the internal id from what the report shows.
  def with_folio_ids(rows)
    folios = CapitalCommitment.where(id: rows.pluck("commitment_id")).pluck(:id, :folio_id).to_h
    rows.map do |row|
      { "Folio" => folios[row["commitment_id"]] }.merge(row.except("commitment_id"))
    end
  end

  # The drill-down filters for 2.2, built alongside the displayed rows so they stay in step.
  def cumulative_filters(allocation_run, rows)
    folios = CapitalCommitment.where(id: rows.pluck("commitment_id")).pluck(:id, :folio_id).to_h
    rows.map do |row|
      inception_filter(allocation_run, name: row["Entry name"], folio_id: folios[row["commitment_id"]])
    end
  end

  # ── Drill-down filters ───────────────────────────────────────────────────────
  # Each returns [field, predicate, value] triples for ransack_query_params_multiple. Dates go
  # out in the database's own format so the link does not depend on the reader's locale.

  # Everything for one entry name over the run's period — the window 2.1's rollup summed.
  def period_filter(allocation_run, name:, entry_type:)
    [%w[fund_id eq] << allocation_run.fund_id,
     %w[name eq] << name,
     %w[entry_type eq] << entry_type,
     %w[reporting_date gteq] << allocation_run.start_date.to_fs(:db),
     %w[reporting_date lteq] << allocation_run.end_date.to_fs(:db)]
  end

  # Everything for one folio and entry name since inception — what 2.2's cumulative sums.
  def inception_filter(allocation_run, name:, folio_id:)
    [%w[fund_id eq] << allocation_run.fund_id,
     %w[name eq] << name,
     %w[folio_id eq] << folio_id,
     %w[reporting_date lteq] << allocation_run.end_date.to_fs(:db)]
  end

  # One entry name at the period end alone — where 2.3's percentages live.
  def end_date_filter(allocation_run, name:, entry_type:)
    [%w[fund_id eq] << allocation_run.fund_id,
     %w[name eq] << name,
     %w[entry_type eq] << entry_type,
     %w[reporting_date eq] << allocation_run.end_date.to_fs(:db)]
  end

  # One folio's entries up to the period end — for a folio 1.3 says received nothing.
  def folio_filter(allocation_run, folio_id)
    [%w[fund_id eq] << allocation_run.fund_id,
     %w[folio_id eq] << folio_id,
     %w[reporting_date lteq] << allocation_run.end_date.to_fs(:db)]
  end

  def pass(ctx, code, title, summary)
    add(ctx, code, title, "pass", summary)
  end

  # Named `warning` rather than `warn` so it does not shadow Kernel#warn inside this class.
  def warning(ctx, code, title, summary, rows = [], truncated = 0, filters = [])
    add(ctx, code, title, "warn", summary, rows, truncated, filters)
  end

  # Named `failure` rather than `fail` so it does not shadow Kernel#fail inside this class.
  def failure(ctx, code, title, summary, rows = [], truncated = 0, filters = [])
    add(ctx, code, title, "fail", summary, rows, truncated, filters)
  end

  def skipped(ctx, code, title, summary)
    add(ctx, code, title, "skipped", summary)
  end

  # Why a check below 1.1 had nothing to look at: either the run never ran formulas, or it has
  # not finished writing the entries this check would reconcile.
  # A check that asks what this particular run produced cannot answer for a run whose entries
  # were never tagged with a run id. Saying so is the honest answer; guessing would report
  # every formula as silent and every folio as missed.
  def skipped_untagged(ctx, code, title)
    skipped(ctx, code, title, predates_message(ctx[:allocation_run], "tag entries with the run that made them"))
  end

  def predates_message(allocation_run, capability)
    "This run is from #{l_date(allocation_run.created_at&.to_date)}, before the system began to " \
      "#{capability}, so there is nothing recorded to check it against."
  end

  def skipped_no_allocations(ctx, code, title)
    reason = if ctx[:pre_checks_failed]
               "This run was stopped by a failed pre-run check before it computed anything, so there are no entries to check."
             elsif ctx[:allocations_run]
               "This run has not finished, so its entries are not complete enough to check."
             else
               "This run did not run allocation formulas, so it produced no entries to check."
             end
    skipped(ctx, code, title, reason)
  end

  # A stored check result is already laid out as columns + value rows + parallel filters (see
  # AccountEntryAllocation::CheckFailed), so it becomes a Finding as-is rather than through #add.
  def add_run_check(ctx, code, result)
    ctx[:findings] << Finding.new(code:, title: result["name"], group: "run",
                                  severity: RUN_CHECK_SEVERITY.fetch(result["result"], "fail"),
                                  summary: result["summary"], columns: result["columns"],
                                  rows: result["rows"], filters: result["filters"],
                                  truncated: [result["truncated"].to_i, 0].max)
  end

  # Nothing stored for this kind. Because a failed check stops the run and a failed or warning
  # check always gets stored, the run's status is enough to say whether every check passed:
  #   - no check of this kind in scope             -> skipped
  #   - run not run allocations / still running    -> skipped
  #   - pre-run: the run got past its checks       -> pass (any status other than Pending/blank
  #     means the steps after run_pre_checks ran, and a pre-run failure would have been stored)
  #   - post-run: the run finished with Success    -> pass; otherwise the run stopped before its
  #     post-run checks ran -> skipped
  # Only check formulas created before the run count: one added since could not have run.
  def summarise_unrecorded_run_checks(ctx, kind, code, label, allocation_run, fund)
    title = "#{label} checks passed"
    checks = FundFormula.enabled.where(fund_id: fund.id, rule_type: kind == "pre" ? FundFormula::PRE_RUN_CHECK : FundFormula::POST_RUN_CHECK)
                        .where(created_at: ..allocation_run.created_at)
    checks = checks.where(rule_for: allocation_run.rule_for) if allocation_run.rule_for.present?
    # Split exactly as RunFormulas#formulas_in_scope does -- see check_silent_formulas.
    checks = checks.with_tags(allocation_run.tag_list.split(",")) if allocation_run.tag_list.present?
    count = checks.count

    return skipped(ctx, code, title, "This fund had no #{label.downcase} checks in scope for this run.") if count.zero?
    return skipped(ctx, code, title, "This run did not run allocation formulas, so it ran no checks.") unless ctx[:allocations_run]

    status = allocation_run.status
    return skipped(ctx, code, title, "This run has not finished, so its #{label.downcase} checks have no result yet.") if status.blank? || status == RUNNING_STATUS

    checks_noun = "#{count} #{label.downcase} #{'check'.pluralize(count)}"
    if kind == "pre" || status == "Success"
      pass(ctx, code, title, "The run got past its #{checks_noun}, so none of them failed. " \
                             "Individual results are only kept when a check fails or warns.")
    else
      skipped(ctx, code, title, "The run stopped before its #{checks_noun} ran.")
    end
  end

  # Checks build their rows as hashes because that reads better at the call site; the column
  # order of the first row wins, and every later row is read in that same order so a row whose
  # keys were built in a different order still lines up under the right headers.
  def add(ctx, code, title, severity, summary, rows = [], truncated = 0, filters = [])
    columns = rows.first&.keys || []
    ctx[:findings] << Finding.new(code:, title:, group: code.start_with?("1") ? "run" : "arithmetic",
                                  severity:, summary:, columns:,
                                  rows: rows.map { |row| columns.map { |column| row[column] } },
                                  filters: filters,
                                  truncated: [truncated, 0].max)
    true
  end

  # Amounts are DECIMAL(30,8); two places is what the report needs to read.
  def fmt(amount)
    ActiveSupport::NumberHelper.number_to_rounded(amount, precision: 2, delimiter: ",")
  end

  # Dates are formatted into the finding when it is built, not when it is read, because the
  # report renders rows as opaque label/value pairs and cannot tell a date from any other
  # string. A report therefore carries the date format of the locale it was built under.
  def l_date(date)
    date.present? ? I18n.l(date) : "—"
  end
end
