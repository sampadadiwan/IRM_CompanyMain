# ⑤ One compliance run of one fund: for every attached pack, move the version forward, evaluate each
# applicable check, store the results (append-only), update the register and schedule duties.
# One transaction per fund with a repeatable-read snapshot on MySQL, so a payment saved mid-run is
# either fully in or fully out (R21, E134). Nightly runs are idempotent per fund and date; a second
# Run now while one is running returns the running one (E18).
# Worked examples H19, H20, H22, E9, E17, E18, E19, E21, E24, E86, X24, X28 — openspec/changes/archive/2026-11-06-fund-compliance-monitoring/business-rules.md
class ComplianceRunOperation < Trailblazer::Operation
  step :load_fund
  step :start_run
  step :evaluate_packs
  step :finish
  left :mark_failed

  # Closed (soft-deleted) funds are never run (E19)
  def load_fund(ctx, fund_id:, **)
    ctx[:fund] = Fund.find_by(id: fund_id)
    ctx[:setup] = ComplianceEntitySetup.for(ctx[:fund].entity) if ctx[:fund]
    ctx[:fund].present?
  end

  def start_run(ctx, fund:, run_date:, trigger: "nightly", **)
    existing = ComplianceRun.where(fund_id: fund.id).where(status: "running").order(:id).last
    # E18: a second Run now while one is in flight gets the same run
    if existing && trigger == "run_now"
      ctx[:run] = existing
      ctx[:already_running] = true
      return true
    end
    # Nightly runs are unique per fund and date
    if trigger == "nightly" && ComplianceRun.exists?(fund_id: fund.id, run_date:, trigger: "nightly", status: "succeeded")
      ctx[:run] = ComplianceRun.where(fund_id: fund.id, run_date:, trigger: "nightly").last
      ctx[:already_ran] = true
      return true
    end
    ctx[:run] = ComplianceRun.create!(entity_id: fund.entity_id, fund:, run_date:, trigger:, status: "running")
  end

  def evaluate_packs(ctx, fund:, run:, setup:, run_at: Time.current, **)
    return true if ctx[:already_running] || ctx[:already_ran]

    ctx[:events] = []
    snapshot do
      # Preloaded for the version mover and evaluator (fund, current version, the pack's versions) and the
      # override/disable requests of every attachment in one query — no queries per pack (R176)
      fps = FundCompliancePack.active.where(fund_id: fund.id).order(:id)
                              .includes(:fund, :compliance_pack_version, compliance_pack: :versions).to_a
      FundCompliancePack.preload_requests(fps)
      # Every attachment's open register items in one query (ComplianceRegisterUpdater reads them per result)
      open_items = ComplianceRegisterItem.open_items.where(fund_compliance_pack_id: fps.map(&:id)).group_by(&:fund_compliance_pack_id)
      fps.each do |fp|
        fp.run_open_items = (open_items[fp.id] || []).index_by(&:check_key)
        evaluate_pack(ctx, fp, run, setup, run_at)
      end
    end
    true
  end

  def finish(ctx, run:, setup:, **)
    return true if ctx[:already_running] || ctx[:already_ran]

    run.update!(status: "succeeded", finished_at: Time.current)
    record_digest_notes(setup, ctx[:events])
    true
  end

  # X28: the run is marked failed; the amber banner and the failure email follow from it
  def mark_failed(ctx, run: nil, exception: nil, **)
    return unless run && run.status == "running"

    run.update!(status: "failed", finished_at: Time.current, error_summary: (ctx[:error] || exception&.class&.name).to_s.truncate(500))
    ComplianceNotices.run_failed(run)
  end

  # Wrap the operation so an exception is a failed run, not a crashed job (LLD › Error Mapping)
  def self.call_safely(**)
    call(**)
  rescue StandardError => e
    run = ComplianceRun.where(fund_id: kwargs_fund_id(**), status: "running").order(:id).last
    run&.update!(status: "failed", finished_at: Time.current, error_summary: e.class.name)
    ComplianceNotices.run_failed(run) if run
    Rails.logger.error("[Compliance] run failed fund #{kwargs_fund_id(**)}: #{e.class}")
    nil
  end

  def self.kwargs_fund_id(fund_id: nil, **)
    fund_id
  end

  # E134 / R21: the isolation a fund run reads with — one repeatable-read snapshot on MySQL
  def self.snapshot_isolation(adapter_name)
    adapter_name.to_s.downcase.include?("mysql") || adapter_name.to_s.downcase.include?("trilogy") ? :repeatable_read : nil
  end

  private

  # Version moves, dropped overrides and late publications appear once in the next digest (E2, E114)
  def record_digest_notes(setup, events)
    notes = Array(events).filter_map do |e|
      next e["message"] if e["message"]
      next "#{e['to']} applied — published late" if e["kind"] == "version_moved" && e["published_late"]
    end
    return if notes.empty?

    setup.update!(digest_notes: Array(setup.digest_notes) + notes)
  end

  # Repeatable read on MySQL; SQLite (tests) is single-writer (R21, E134)
  def snapshot(&)
    isolation = self.class.snapshot_isolation(ActiveRecord::Base.connection.adapter_name)
    isolation ? ActiveRecord::Base.transaction(isolation:, &) : ActiveRecord::Base.transaction(&)
  end

  def evaluate_pack(ctx, fund_pack, run, setup, run_at)
    state = ComplianceVersionMover.call(fund_pack, run_at:)
    # A version move may drop or archive overrides — read them fresh after one
    fund_pack.clear_preloaded_requests if state.events.any?
    ctx[:events].concat(state.events.map { |e| e.merge("fund_pack_id" => fund_pack.id) })
    return if state.status == :retired
    # E9: no classification → no checks run (shown amber on the dashboard)
    return if fund_pack.classification.blank?

    version = state.version
    checks = applicable_checks(fund_pack, version)
    return store_all_could_not_check(run, fund_pack, version, checks, "Could not check — missing: fund start date") if state.status == :missing_start_date

    context = ComplianceMeasureQuery.context(fund: fund_pack.fund, as_of: run.run_date, setup:, version:)
    overrides = fund_pack.active_overrides
    pending = fund_pack.pending_override_keys
    disabled = fund_pack.disabled_check_keys

    checks.each do |check|
      # H15: disabled checks stop running
      next if disabled.include?(check["key"])

      if check["tested"] == "on_record"
        evaluate_on_record(run, fund_pack, version, check, context, overrides, pending, state)
      else
        outcome = ComplianceCheckEvaluator.call(check, context:, override: overrides[check["key"]],
                                                       pending_override: pending.include?(check["key"]),
                                                       transition_until: state.transition_until)
        store(run, fund_pack, version, check, outcome)
        check_duties(fund_pack, version, check, outcome, run.run_date, setup)
      end
    end
    ComplianceDutyScheduler.call(fund_pack, version:, run_date: run.run_date, setup:)
  end

  def applicable_checks(fund_pack, version)
    version.checks.select do |c|
      next false if c["kind"] == "manual"

      applies = c["applies_to"]
      applies.nil? || applies == "all" || Array(applies).include?(fund_pack.classification)
    end
  end

  # E21: a check tested "when a record is made" tests each new record once and is never reopened
  # by later changes. Each record's result carries it as the subject.
  def evaluate_on_record(run, fund_pack, version, check, context, overrides, pending, state)
    source = check["record_source"].presence || "portfolio_investments"
    model = ComplianceDataCatalog.model(source)
    tested_ids = ComplianceResult.where(fund_compliance_pack_id: fund_pack.id, check_key: check["key"], subject_type: model.name).pluck(:subject_id)
    model.where(entity_id: fund_pack.entity_id, fund_id: fund_pack.fund_id).where.not(id: tested_ids).find_each do |rec|
      outcome = ComplianceCheckEvaluator.call(check, context:, override: overrides[check["key"]],
                                                     pending_override: pending.include?(check["key"]),
                                                     transition_until: state.transition_until)
      store(run, fund_pack, version, check, outcome, subject: rec)
    end
  end

  # E55: a content check that names a duty (SEBI check 7 → enhanced due diligence) opens one occurrence per
  # failing subject; the duty's unique key means later runs do not add it again
  def check_duties(fund_pack, version, check, outcome, run_date, setup)
    subjects = Array(outcome.working["duty_subjects"])
    duty = version.duties.detect { |d| d["key"] == check["duty"] } if check["duty"].present?
    return if duty.nil? || subjects.empty? || outcome.outcome == "pass"

    now = Time.current
    rows = subjects.map do |investor_id|
      { entity_id: fund_pack.entity_id, fund_compliance_pack_id: fund_pack.id, duty_key: duty["key"], period_key: "",
        subject_type: "Investor", subject_id: investor_id, due_on: run_date + (duty.dig("due", "n") || check["time_to_fix_days"] || 30).to_i.days,
        owner_id: setup&.owner_id, created_at: now, updated_at: now }
    end
    # Duplicates skipped by idx_cduty_unique (no unique_by: — MySQL does not support it)
    ComplianceDuty.insert_all(rows)
  end

  def store_all_could_not_check(run, fund_pack, version, checks, message)
    checks.each do |check|
      outcome = ComplianceCheckEvaluator::Outcome.new(outcome: "could_not_check", working: { "message" => message, "lines" => [message], "missing" => "fund start date" })
      store(run, fund_pack, version, check, outcome)
    end
  end

  # The attachment's open register items by check, loaded once per fund run (R176). Kept on the
  # attachment record, which this run loaded fresh, so nothing outlives the run.
  def open_items_for(fund_pack)
    fund_pack.run_open_items ||= ComplianceRegisterItem.open_items.where(fund_compliance_pack_id: fund_pack.id).index_by(&:check_key)
  end

  def store(run, fund_pack, version, check, outcome, subject: nil)
    working = outcome.working.merge("version" => version.label, "classification" => fund_pack.classification,
                                    "check_name" => check["name"], "citation" => check["citation"])
    # entity as the run's loaded record, not an id — the belongs_to check would load it once per result
    result = ComplianceResult.create!(
      entity: run.entity, compliance_run: run, fund_compliance_pack: fund_pack, compliance_pack_version: version,
      check_key: check["key"], subject_type: subject&.class&.name, subject_id: subject&.id,
      outcome: outcome.outcome, figure: outcome.figure, limit_value: outcome.limit_value, working:
    )
    ComplianceRegisterUpdater.call(result, check:, run_date: run.run_date, open_items: open_items_for(fund_pack))
    result
  end
end
