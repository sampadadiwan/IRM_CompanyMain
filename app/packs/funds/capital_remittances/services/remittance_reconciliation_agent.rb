# frozen_string_literal: true

# RemittanceReconciliationAgent — reconciles bank statement deposits against a
# single CapitalCall's outstanding CapitalRemittance records.
#
# Scoped to one CapitalCall per run, not a whole Fund (unlike RtaReconciliationAgent).
# Remittances are already generated per call, so a run's candidate set is exactly that
# call's remittances — a fund with several open calls is reconciled one run per call.
#
# Phase 1: ingest an uploaded xlsx workbook and parse every deposit narration through the
# bank-specific parser registry (see BankDepositNarrationParser).
#
# Phase 2: load this call's outstanding CapitalRemittance records and score each non-internal
# deposit against them — identity (account number against InvestorKyc/virtual account, else
# name similarity), an independent source-of-funds check (does an exposed account number
# agree with the matched investor's KYC record), and amount-within-tolerance — bucketing each
# into exact / probable / needs_review / no_match / internal.
#
# Phase 3 (this): auto-applies Exact-tier matches as real CapitalRemittancePayment records,
# gated by the auto_apply_exact toggle (default No — a fund opts in explicitly). Idempotent:
# every created payment's reference_no is the bank's own transaction id where the statement
# exposes one (observed: ICICI's "Tran Id" column), else a deterministic hash of the
# narration+amount+sheet - either way stable across re-runs, so re-uploading the same
# statement (or an overlapping one) never creates a duplicate payment.
#
# json_fields configuration:
#   tolerance_amount           — float, absolute (default 500)
#   tolerance_pct              — float, percentage (default 0, disabled) — OR'd with tolerance_amount
#   name_similarity_threshold  — float 0-1 (default 0.90) — minimum score to accept a name-only match
#   auto_apply_exact           — "Yes"/"No" (default No) — whether Exact-tier rows create payments
#
# @see docs/ai/capital_remittance_reconciliation_agent_prd.md
# @see SupportAgentService
# @see BankDepositNarrationParser
class RemittanceReconciliationAgent < SupportAgentService
  DESCRIPTION = "Reconciles a fund's bank statement deposits against one capital call's outstanding remittances."

  LONG_DESCRIPTION = <<~DESC
    Reads an uploaded bank statement workbook (one or more sheets, e.g. one per bank account),
    parses every deposit narration through a bank-specific parser registry, and matches each
    deposit against the outstanding CapitalRemittance records for a single capital call.

    Scoped to one CapitalCall per run — remittances are generated per call, so a fund with
    several open calls is reconciled one run per call, never merged across calls.

    Each deposit is bucketed into Exact (account number matches the investor's KYC record or
    assigned virtual account, amount within tolerance, unambiguous), Probable (name-only match,
    amount within tolerance), Needs review (ambiguous identity, amount outside tolerance, or a
    funding-source discrepancy — an exposed account number that contradicts the matched
    investor's KYC record), No match, or Internal (the fund's own FD/loan movements).

    When auto_apply_exact is Yes, Exact-tier deposits automatically create a
    CapitalRemittancePayment (idempotent — re-running never duplicates one). Every other tier
    is proposed only; nothing is written for them.

    Results are stored in a SupportAgentReport owned by the CapitalCall.
  DESC

  STEP_LABELS = {
    initialize_agent: "Initialize",
    ingest_statement: "Ingest Statement",
    parse_narrations: "Parse Narrations",
    load_candidates: "Load Candidates",
    score_deposits: "Score & Bucket",
    apply_exact_matches: "Apply Exact Matches",
    generate_progress_reports: "Save Report"
  }.freeze

  step :initialize_agent
  step :ingest_statement
  step :parse_narrations
  step :load_candidates
  step :score_deposits
  step :apply_exact_matches
  step :generate_progress_reports

  # Name-only identity is accepted deterministically only when the top match clears the
  # configured threshold *and* leads the runner-up by at least this margin — a top score of
  # 0.95 next to a second-best of 0.94 is not a confident, unambiguous match even though 0.95
  # alone clears the threshold.
  NAME_MATCH_MARGIN = 0.05

  # Legal-entity suffixes are stripped rather than compared, so a narration that dropped
  # "PVT LTD"/"HUF"/etc. under bank truncation isn't penalized for it on either side.
  LEGAL_SUFFIX_RE = /\b(PRIVATE\s+LIMITED|PVT\.?\s*LTD\.?|LIMITED|LTD\.?|LLP|HUF|TRUST)\b/i

  # Setup health check — unset tolerance means zero tolerance (every rounding/wire-fee
  # difference becomes a break), same rationale as RtaReconciliationAgent's own check.
  def self.config_issues(support_agent)
    fields = support_agent.json_fields || {}
    issues = []

    if fields["tolerance_amount"].to_s.strip.blank? && fields["tolerance_pct"].to_s.strip.blank?
      issues << "No tolerance configured ('tolerance_amount' / 'tolerance_pct') — defaulting to ₹500 absolute. " \
                "Set explicitly if this fund's typical wire-fee shortfall differs."
    end

    issues
  end

  # Runs against a single CapitalCall the agent is triggered for.
  def targets(entity_id)
    CapitalCall.where(entity_id: entity_id)
  end

  private

  def initialize_agent(ctx, target:, bank_statement_document_id: nil, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :initialize_agent) if report
    super
    ctx[:capital_call] = target
    ctx[:target_model] = target
    ctx[:issues] = []
    ctx[:deposits] = []
    ctx[:bank_statement_document_id] = bank_statement_document_id
    mark_step_success(report, :initialize_agent) if report
    true
  end

  # Reads the xlsx attached to the agent (a Document, same WithFolder pattern RTA uses for
  # its PDF) and opens it via Roo. Soft-fails (records a :blocking issue, returns true) when
  # no statement is uploaded or the workbook can't be read, so generate_progress_reports still
  # saves a report explaining why rather than the pipeline erroring out.
  def ingest_statement(ctx, bank_statement_document_id: nil, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :ingest_statement) if report

    doc = bank_statement_document_id.present? ? Document.find_by(id: bank_statement_document_id) : nil
    if doc.nil? || doc.file.blank?
      ctx[:issues] << { type: :blocking, message: "No bank statement uploaded. " \
                                                  "Please upload an xlsx statement when running the agent.", severity: :blocking }
      Rails.logger.warn { "[RemittanceReconciliationAgent] No bank statement document for agent #{@support_agent.id}" }
      mark_step_failed(report, :ingest_statement, message: "No statement uploaded") if report
      return true
    end

    # download with no block returns a persistent Tempfile the caller owns (must close! it
    # itself) — the block form always deletes the tempfile the instant the block returns,
    # which would happen before parse_narrations (a later, separate step) ever reads the
    # Roo::Spreadsheet built from it. The tempfile is kept alive in ctx until parse_narrations
    # is done with it (see its `ensure`).
    begin
      tempfile = doc.file.download
    rescue StandardError => e
      Rails.logger.error { "[RemittanceReconciliationAgent] Statement download failed: #{e.message}" }
      ctx[:issues] << { type: :blocking, message: "Could not download the uploaded statement: #{e.message}", severity: :blocking }
      mark_step_failed(report, :ingest_statement, message: "Download error") if report
      return true
    end

    xlsx = open_workbook(doc, tempfile)
    if xlsx.nil? || xlsx.sheets.empty?
      tempfile.close!
      ctx[:issues] << { type: :blocking, message: "Could not read the uploaded workbook.", severity: :blocking }
      mark_step_failed(report, :ingest_statement, message: "Unreadable workbook") if report
      return true
    end

    ctx[:xlsx] = xlsx
    ctx[:workbook_tempfile] = tempfile
    mark_step_success(report, :ingest_statement, message: "#{xlsx.sheets.size} sheet(s) loaded") if report
    true
  end

  # Identifies the issuing bank per sheet (BankDepositNarrationParser.detect_bank, via the
  # statement header's IFSC — never re-derived per row) and parses every deposit narration
  # through that bank's module. Internal FD/loan rows are kept (not dropped) so a reviewer can
  # override a misclassification later; they're just marked `internal: true`.
  def parse_narrations(ctx, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :parse_narrations) if report

    xlsx = ctx[:xlsx]
    unless xlsx
      mark_step_skipped(report, :parse_narrations, message: "No workbook loaded") if report
      return true
    end

    deposits = []
    row_errors = 0

    xlsx.sheets.each do |sheet_name|
      sheet = xlsx.sheet(sheet_name)
      bank = BankDepositNarrationParser.detect_bank(sheet)

      BankDepositNarrationParser.each_deposit_narration(sheet).each do |entry|
        result = bank.parse(entry[:remark].to_s.strip)
        deposits << {
          "sheet" => sheet_name,
          "row" => entry[:row],
          "bank" => bank.name,
          "raw_narration" => result.raw,
          "name" => result.name,
          "account_number" => result.account_number,
          "pattern" => result.pattern,
          "confidence" => result.confidence.to_s,
          "internal" => result.internal,
          "notes" => result.notes,
          "amount" => entry[:amount],
          "tran_id" => entry[:tran_id],
          "value_date" => entry[:value_date]&.iso8601
        }
      rescue StandardError => e
        # A single malformed row must never cost every deposit already parsed on this or
        # an earlier sheet - isolate the failure to this row and keep going.
        row_errors += 1
        Rails.logger.error { "[RemittanceReconciliationAgent] Row #{entry[:row]} on sheet '#{sheet_name}' failed to parse: #{e.message}" }
      end
    rescue StandardError => e
      # Same isolation one level up: a structural problem with one sheet (bad header, etc.)
      # must not discard deposits already collected from other sheets.
      Rails.logger.error { "[RemittanceReconciliationAgent] Sheet '#{sheet_name}' failed to process: #{e.message}" }
      ctx[:issues] << { type: :warning, message: "Sheet '#{sheet_name}' could not be fully processed: #{e.message}", severity: :warning }
    end

    ctx[:deposits] = deposits
    unmatched = deposits.count { |d| d["pattern"] == "UNMATCHED" }
    if unmatched.positive?
      ctx[:issues] << { type: :warning,
                        message: "#{unmatched} deposit(s) didn't match any known narration pattern and need a parser rule",
                        severity: :warning }
    end
    ctx[:issues] << { type: :warning, message: "#{row_errors} row(s) raised an error while parsing and were skipped", severity: :warning } if row_errors.positive?
    mark_step_success(report, :parse_narrations, message: "#{deposits.size} deposit(s) parsed") if report
    true
  rescue StandardError => e
    # Last-resort net for a failure outside the per-row/per-sheet isolation above (e.g.
    # xlsx.sheets itself raising) - still preserve whatever was collected before it.
    Rails.logger.error { "[RemittanceReconciliationAgent] Parsing error: #{e.class}: #{e.message}" }
    ctx[:deposits] = deposits || []
    ctx[:issues] << { type: :blocking, message: "Narration parsing failed: #{e.message}", severity: :blocking }
    mark_step_failed(report, :parse_narrations, message: "Parsing error") if report
    true
  ensure
    ctx[:workbook_tempfile]&.close!
  end

  # Every CapitalRemittance under THIS call only — never fund-wide, never other calls. Eager
  # loads capital_commitment + investor_kyc since scoring needs both for every deposit.
  def load_candidates(ctx, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :load_candidates) if report

    candidates = ctx[:capital_call].capital_remittances.includes(capital_commitment: :investor_kyc).to_a
    ctx[:candidates] = candidates
    mark_step_success(report, :load_candidates, message: "#{candidates.size} remittance(s) under this call") if report
    true
  end

  # Scores every non-internal deposit against ctx[:candidates] and assigns a tier. See the
  # decision table in docs/ai/capital_remittance_reconciliation_agent_prd.md §6.4.
  def score_deposits(ctx, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :score_deposits) if report

    candidates = ctx[:candidates] || []
    tier_counts = Hash.new(0)
    discrepancy_count = 0

    ctx[:deposits].each do |deposit|
      if deposit["internal"]
        deposit["tier"] = "internal"
        tier_counts["internal"] += 1
        next
      end

      identity = resolve_identity(deposit, candidates)

      case identity[:status]
      when :none
        deposit["tier"] = "no_match"
      when :ambiguous
        deposit["tier"] = "needs_review"
        deposit["reasoning"] = identity[:reasoning]
      when :resolved
        apply_resolved_identity(deposit, identity)
        discrepancy_count += 1 if deposit["source_of_funds"] == "discrepancy"
      end

      tier_counts[deposit["tier"]] += 1
    end

    ctx[:tier_counts] = tier_counts
    ctx[:discrepancy_count] = discrepancy_count
    if discrepancy_count.positive?
      ctx[:issues] << { type: :warning,
                        message: "#{discrepancy_count} deposit(s) matched an investor by name but the narration's account " \
                                 "number contradicts their KYC-registered account — always flagged, never auto-applied",
                        severity: :warning }
    end
    mark_step_success(report, :score_deposits, message: tier_counts.map { |k, v| "#{k}: #{v}" }.join(", ")) if report
    true
  end

  # Auto-applies Exact-tier deposits as CapitalRemittancePayment records when auto_apply_exact
  # is Yes (default No — a fund opts in explicitly). Every non-Exact tier is left untouched
  # here regardless of the toggle; only Exact rows are ever eligible to write anything.
  #
  # Delegates the actual build/dedupe/save to RemittanceDepositPaymentApplier, shared with the
  # manual Confirm/Reassign controller actions so every path creates a payment identically.
  def apply_exact_matches(ctx, support_agent:, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :apply_exact_matches) if report

    unless enabled?("auto_apply_exact")
      mark_step_skipped(report, :apply_exact_matches, message: "auto_apply_exact is No — Exact rows queued for confirm") if report
      return true
    end

    fund = ctx[:capital_call].fund
    created = 0
    already_recorded = 0
    failed = 0

    ctx[:deposits].select { |d| d["tier"] == "exact" }.each do |deposit|
      # Scoped through capital_call.capital_remittances (not a bare CapitalRemittance.find_by)
      # as defense in depth: matched_remittance_id is always sourced from ctx[:candidates],
      # itself already scoped to this call, so this can't fire in the normal flow - it's here
      # so a future bug upstream can never apply a payment against the wrong call's remittance.
      remittance = ctx[:capital_call].capital_remittances.find_by(id: deposit["matched_remittance_id"])
      unless remittance
        deposit["payment_status"] = "error"
        deposit["payment_error"] = "matched remittance no longer exists"
        ctx[:issues] << { type: :warning, message: "Matched remittance no longer exists for #{deposit['matched_investor_name']}", severity: :warning }
        failed += 1
        next
      end

      outcome = RemittanceDepositPaymentApplier.call(deposit: deposit, capital_remittance: remittance, fund: fund)
      deposit["payment_id"] = outcome[:payment_id] if outcome[:payment_id]
      deposit["reference_no"] = outcome[:reference_no] if outcome[:reference_no]

      case outcome[:status]
      when :already_recorded
        deposit["payment_status"] = "already_recorded"
        already_recorded += 1
      when :created
        deposit["payment_status"] = "created"
        created += 1
      when :error
        deposit["payment_status"] = "error"
        deposit["payment_error"] = outcome[:error]
        ctx[:issues] << { type: :warning,
                          message: "Failed to auto-apply payment for #{deposit['matched_investor_name']}: #{outcome[:error]}",
                          severity: :warning }
        failed += 1
      end
    end

    ctx[:payments_created] = created
    ctx[:payments_already_recorded] = already_recorded
    ctx[:payments_failed] = failed
    mark_step_success(report, :apply_exact_matches, message: "#{created} created, #{already_recorded} already recorded, #{failed} failed") if report
    true
  end

  # Mutates `deposit` in place for a :resolved identity — separated from score_deposits'
  # main loop purely so that loop stays readable; not meant to be called standalone.
  def apply_resolved_identity(deposit, identity)
    candidate = identity[:candidate]
    via = identity[:via]

    kyc_account = candidate.investor_kyc&.bank_account_number.presence
    narration_account = deposit["account_number"]

    # The narration's account number is only a meaningful "did this come from the investor's
    # own registered account" signal when identity was resolved via name (an account exposed
    # incidentally alongside a name match). A :virtual_account match's "account" *is* the
    # fund-assigned collection account, not the sender's personal bank account, so comparing
    # it to KYC there is comparing two different identifiers that are *expected* to differ,
    # not a genuine source-of-funds check - discrepancy only ever applies to :name matches.
    discrepancy = via == :name && narration_account.present? && kyc_account.present? && kyc_account != narration_account

    amount_ok = amount_within_tolerance?(deposit["amount"], candidate.due_amount.to_f)

    deposit["matched_remittance_id"] = candidate.id
    deposit["matched_commitment_id"] = candidate.capital_commitment_id
    deposit["matched_investor_name"] = candidate.investor_name
    deposit["identity_via"] = via.to_s
    deposit["due_amount"] = candidate.due_amount.to_f
    deposit["reasoning"] = identity[:reasoning]
    deposit["source_of_funds"] =
      if via == :virtual_account
        # Only "confirmed" in the coincidental case where the virtual account happens to
        # equal the investor's own KYC account too - otherwise there's nothing here that
        # actually verifies the sender's personal account, so it stays unverifiable rather
        # than falsely claiming confirmation.
        kyc_account.present? && kyc_account == narration_account ? "confirmed" : "unverifiable"
      elsif narration_account.blank? || kyc_account.blank?
        "unverifiable"
      elsif discrepancy
        "discrepancy"
      else
        "confirmed" # via == :kyc_account (narration_account == kyc_account by construction) or via == :name with no contradiction
      end

    deposit["tier"] =
      if discrepancy || !amount_ok
        "needs_review"
      elsif %i[kyc_account virtual_account].include?(via)
        "exact"
      else
        "probable"
      end
  end

  # Account number first (strong signal, checked against InvestorKyc#bank_account_number then
  # CapitalCommitment#virtual_bank_account), falling back to name similarity. Returns
  # {status: :resolved, candidate:, via:, reasoning:} | {status: :ambiguous, reasoning:} |
  # {status: :none}.
  def resolve_identity(deposit, candidates)
    by_account = resolve_by_account(deposit, candidates)
    return by_account if by_account

    resolve_by_name(deposit, candidates)
  end

  def resolve_by_account(deposit, candidates)
    account = deposit["account_number"]
    return nil if account.blank?

    kyc_matches = candidates.select { |c| c.investor_kyc&.bank_account_number.presence == account }
    if kyc_matches.size == 1
      return { status: :resolved, candidate: kyc_matches.first, via: :kyc_account,
               reasoning: ["account #{account} matches InvestorKyc#bank_account_number"] }
    elsif kyc_matches.size > 1
      return { status: :ambiguous, reasoning: ["account #{account} matches KYC records for #{kyc_matches.size} different investors"] }
    end

    virtual_matches = candidates.select { |c| c.capital_commitment.virtual_bank_account.presence == account }
    if virtual_matches.size == 1
      return { status: :resolved, candidate: virtual_matches.first, via: :virtual_account,
               reasoning: ["account #{account} matches CapitalCommitment#virtual_bank_account"] }
    elsif virtual_matches.size > 1
      return { status: :ambiguous, reasoning: ["account #{account} matches the virtual account of #{virtual_matches.size} different investors"] }
    end

    nil # account present but matches no candidate on this call - fall through to name matching
  end

  def resolve_by_name(deposit, candidates)
    name = deposit["name"]
    return { status: :none } if name.blank?

    ranked = candidates.filter_map { |c| [c, name_similarity(name, c.investor_name)] if c.investor_name.present? }
                       .sort_by { |_, score| -score }
    return { status: :none } if ranked.empty?

    top, top_score = ranked.first
    return { status: :none } if top_score < name_similarity_threshold

    tied = ranked.select { |_, score| (top_score - score) < NAME_MATCH_MARGIN }
    if tied.size > 1
      return { status: :ambiguous,
               reasoning: ["name similarity #{top_score.round(2)} matches #{tied.size} investors within #{NAME_MATCH_MARGIN} of each other"] }
    end

    { status: :resolved, candidate: top, via: :name,
      reasoning: ["name similarity #{top_score.round(2)} to \"#{top.investor_name}\""] }
  end

  def amount_within_tolerance?(deposit_amount, due_amount)
    return false if deposit_amount.nil? || due_amount.nil?

    diff = (deposit_amount - due_amount).abs
    return true if diff <= tolerance_amount

    pct = tolerance_pct
    return false unless pct.positive? && due_amount.nonzero?

    (diff / due_amount.abs * 100) <= pct
  end

  def tolerance_pct
    val = @support_agent.json_fields["tolerance_pct"].to_s.strip
    val.present? ? val.to_f : 0.0
  end

  def tolerance_amount
    val = @support_agent.json_fields["tolerance_amount"].to_s.strip
    val.present? ? val.to_f : 500.0
  end

  def name_similarity_threshold
    val = @support_agent.json_fields["name_similarity_threshold"].to_s.strip
    val.present? ? val.to_f : 0.90
  end

  # Normalized Jaro-Winkler similarity, with a whitespace-stripped fallback for banks that
  # concatenate the beneficiary name entirely (observed in ICICI narrations: "SANDEEPKUMARSINGH"
  # for "Sandeep Kumar Singh") - a plain comparison scores that far lower than it should, so the
  # better of the two comparisons wins.
  def name_similarity(narration_name, investor_name)
    a = normalize_name(narration_name)
    b = normalize_name(investor_name)
    return 0.0 if a.empty? || b.empty?

    direct = jaro_winkler(a, b)
    stripped = jaro_winkler(a.delete(' '), b.delete(' '))
    [direct, stripped].max
  end

  def normalize_name(name)
    normalized = name.to_s.upcase.gsub(/[^A-Z0-9\s]/, ' ')
    normalized = normalized.gsub(LEGAL_SUFFIX_RE, ' ')
    normalized.gsub(/\s+/, ' ').strip
  end

  # Standard Jaro-Winkler string similarity (0.0-1.0). No gem for this in the bundle, and the
  # algorithm is small/self-contained enough that hand-rolling it beats adding a dependency -
  # validated against the canonical reference pairs (Winkler 1990): MARTHA/MARHTA -> 0.961,
  # DWAYNE/DUANE -> 0.840, DIXON/DICKSONX -> 0.813.
  def jaro_winkler(s1, s2, prefix_scale: 0.1)
    jaro_sim = jaro_similarity(s1, s2)
    prefix_length = 0
    [s1.length, s2.length, 4].min.times do |i|
      break unless s1[i] == s2[i]

      prefix_length += 1
    end
    jaro_sim + (prefix_length * prefix_scale * (1 - jaro_sim))
  end

  def jaro_similarity(s1, s2)
    return 1.0 if s1 == s2
    return 0.0 if s1.empty? || s2.empty?

    match_distance = [([s1.length, s2.length].max / 2) - 1, 0].max
    s1_matches = Array.new(s1.length, false)
    s2_matches = Array.new(s2.length, false)

    matches = 0
    s1.chars.each_with_index do |c1, i|
      low = [0, i - match_distance].max
      high = [i + match_distance, s2.length - 1].min
      (low..high).each do |j|
        next if s2_matches[j] || s2[j] != c1

        s1_matches[i] = true
        s2_matches[j] = true
        matches += 1
        break
      end
    end
    return 0.0 if matches.zero?

    k = 0
    transpositions = 0
    s1.chars.each_with_index do |c1, i|
      next unless s1_matches[i]

      k += 1 until s2_matches[k]
      transpositions += 1 if c1 != s2[k]
      k += 1
    end
    transpositions /= 2.0

    ((matches.to_f / s1.length) + (matches.to_f / s2.length) + ((matches - transpositions) / matches)) / 3.0
  end

  def generate_progress_reports(ctx, support_agent:, **)
    step_report = ctx[:support_agent_report]
    mark_step_running(step_report, :generate_progress_reports) if step_report

    deposits     = ctx[:deposits] || []
    has_blocking = ctx[:issues].any? { |i| i[:severity] == :blocking }

    # Always create a new report row so run history accumulates, same as RtaReconciliationAgent —
    # the step_report (from find_or_initialize_by) only drives the live progress panel.
    rpt = SupportAgentReport.new(owner: ctx[:capital_call], support_agent: support_agent)
    rpt.json_fields = {
      "run_at" => step_report&.json_fields&.dig("run_at") || Time.current.iso8601,
      "capital_call_id" => ctx[:capital_call]&.id,
      "source_document_id" => ctx[:bank_statement_document_id],
      "deposits" => deposits,
      "issues" => ctx[:issues],
      "deposit_count" => deposits.size,
      "unmatched_count" => deposits.count { |d| d["pattern"] == "UNMATCHED" },
      "internal_count" => deposits.count { |d| d["internal"] },
      "tier_counts" => ctx[:tier_counts] || {},
      "discrepancy_count" => ctx[:discrepancy_count] || 0,
      "auto_apply_exact" => enabled?("auto_apply_exact"),
      "payments_created" => ctx[:payments_created] || 0,
      "payments_already_recorded" => ctx[:payments_already_recorded] || 0,
      "payments_failed" => ctx[:payments_failed] || 0
    }
    rpt.status = has_blocking ? SupportAgentReport.statuses[:failed] : SupportAgentReport.statuses[:completed]
    rpt.save!

    mark_step_success(step_report, :generate_progress_reports, message: "#{deposits.size} deposit(s)") if step_report
    finalize_report(step_report, status: has_blocking ? "blocked" : "ready") if step_report

    ctx[:support_agent_report] = rpt
    true
  end

  # `tempfile` is the caller's (ingest_statement's) downloaded copy, kept alive across steps —
  # see the comment there. Shrine tempfiles are often extensionless, so Roo needs the original
  # filename's extension passed explicitly (same pattern as KpiWorkbookReader#open_workbook)
  # or it can't tell xlsx from xls/csv.
  def open_workbook(doc, tempfile)
    ext = File.extname(doc.file.original_filename.to_s).delete('.').downcase.presence
    if ext.present? && File.extname(tempfile.path).blank?
      Roo::Spreadsheet.open(tempfile.path, extension: ext)
    else
      Roo::Spreadsheet.open(tempfile.path)
    end
  rescue StandardError => e
    Rails.logger.error { "[RemittanceReconciliationAgent] Workbook read error: #{e.message}" }
    nil
  end
end
