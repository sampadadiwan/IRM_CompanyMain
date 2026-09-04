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
#   send_report                — "Yes"/"No" (default Yes) — email the run summary to notify_email
#   notify_email               — string — recipient of the reconciliation summary email
#   llm_fuzzy_matching         — "Yes"/"No" (default No) — reserved for Phase 5 (AI-assisted
#                                scoring of the ambiguous name band); read nowhere yet, so it has
#                                no effect on a run until that phase lands
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
    assigned virtual account, unambiguous), Probable (name-only match), Needs review (ambiguous
    identity, an overpayment beyond tolerance, or a funding-source discrepancy — an exposed
    sender account number that contradicts the matched investor's KYC record), No match, or
    Internal (the fund's own FD/loan movements). A partial payment (short of the due amount
    beyond tolerance) keeps its tier — the payment is recorded for the amount received and the
    remittance carries the shortfall.

    When send_report is Yes, the run summary (tier counts, every discrepancy, every row needing
    review) is emailed to notify_email.

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
    send_reconciliation_report: "Email Report",
    generate_progress_reports: "Save Report"
  }.freeze

  step :initialize_agent
  step :ingest_statement
  step :parse_narrations
  step :load_candidates
  step :score_deposits
  step :apply_exact_matches
  step :send_reconciliation_report
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

    issues + missing_toggle_issues(support_agent, "send_report" => "the reconciliation report email")
  end

  # Deliberately empty: every run needs a bank statement uploaded for one specific CapitalCall
  # (the run modal on the capital call page), so there is no meaningful "run for every call"
  # batch — an untargeted run from the Support Agents index, or a scheduled AgentSchedule run,
  # would otherwise create one failed "No bank statement uploaded" report per capital call in
  # the entity. Still a CapitalCall relation (not nil) because the support agents UI infers the
  # agent's target type from `targets(...).model`. Scheduled/batch runs are Phase 7.
  def targets(entity_id)
    CapitalCall.where(entity_id: entity_id).none
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
    already_recorded = 0
    recorded_elsewhere = 0
    existing_by_ref = existing_payments_by_reference(ctx)

    ctx[:deposits].each do |deposit|
      if deposit["internal"]
        deposit["tier"] = "internal"
        tier_counts["internal"] += 1
        next
      end

      # A deposit this fund has ALREADY recorded a payment for (same bank reference) must be
      # recognised before its amount is scored: the earlier payment reduced the remittance's
      # due amount, so a re-run of the same statement would otherwise read its own payment as
      # an overpayment and push the row to Needs review.
      deposit["reference_no"] = RemittanceDepositPaymentApplier.reference_no_for(deposit)
      existing = existing_by_ref[deposit["reference_no"]]
      if existing && existing.capital_remittance&.capital_call_id == ctx[:capital_call].id
        apply_recorded_payment(deposit, existing)
        already_recorded += 1
        tier_counts[deposit["tier"]] += 1
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

      # Same reference already applied under a DIFFERENT call of this fund: keep the tiering
      # (so the reviewer sees who it matched here) but flag it — never re-applied, no Undo here.
      if existing
        other_call = existing.capital_remittance&.capital_call
        deposit["payment_status"] = "recorded_elsewhere"
        deposit["payment_error"] = "already recorded as a payment against #{other_call&.name || 'another capital call'} (payment ##{existing.id})"
        ctx[:issues] << { type: :warning,
                          message: "Deposit for #{deposit['matched_investor_name'] || deposit['name']} was #{deposit['payment_error']} — not re-applied to this call",
                          severity: :warning }
        recorded_elsewhere += 1
      end

      tier_counts[deposit["tier"]] += 1
    end

    ctx[:tier_counts] = tier_counts
    ctx[:discrepancy_count] = discrepancy_count
    ctx[:payments_already_recorded] = already_recorded
    ctx[:payments_recorded_elsewhere] = recorded_elsewhere
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
    already_recorded = ctx[:payments_already_recorded] || 0
    recorded_elsewhere = ctx[:payments_recorded_elsewhere] || 0
    failed = 0

    # Exact rows with no payment outcome yet — score_deposits already settled the ones whose
    # reference was found on this fund (already_recorded / recorded_elsewhere).
    ctx[:deposits].select { |d| d["tier"] == "exact" && d["payment_status"].blank? }.each do |deposit|
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
      deposit["reference_no"] = outcome[:reference_no] if outcome[:reference_no]
      # payment_id is only recorded for a payment that belongs to THIS call — a
      # :recorded_elsewhere payment lives under another call's remittance, and the panel
      # treats a present payment_id as "recorded here, offer Undo".
      deposit["payment_id"] = outcome[:payment_id] if outcome[:payment_id] && outcome[:status] != :recorded_elsewhere

      case outcome[:status]
      when :already_recorded
        deposit["payment_status"] = "already_recorded"
        already_recorded += 1
      when :recorded_elsewhere
        deposit["payment_status"] = "recorded_elsewhere"
        deposit["payment_error"] = outcome[:error]
        ctx[:issues] << { type: :warning,
                          message: "Deposit for #{deposit['matched_investor_name']} was #{outcome[:error]} — not re-applied to this call",
                          severity: :warning }
        recorded_elsewhere += 1
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
    ctx[:payments_recorded_elsewhere] = recorded_elsewhere
    ctx[:payments_failed] = failed
    if report
      mark_step_success(report, :apply_exact_matches,
                        message: "#{created} created, #{already_recorded} already recorded, #{recorded_elsewhere} recorded on another call, #{failed} failed")
    end
    true
  end

  # Emails the run summary (tier counts, every discrepancy, every Needs review row) to
  # notify_email when send_report is Yes. Runs before generate_progress_reports so the email
  # reflects exactly what that step is about to persist. Soft-fails: a mail error becomes a
  # warning on the report, never a pipeline failure.
  def send_reconciliation_report(ctx, support_agent:, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :send_reconciliation_report) if report

    email = support_agent.json_fields["notify_email"].to_s.strip
    unless enabled?("send_report") && email.present?
      mark_step_skipped(report, :send_reconciliation_report, message: "Disabled or no email configured") if report
      return true
    end

    RemittanceReconciliationMailer.reconciliation_report(support_agent, ctx[:capital_call], ctx).deliver_now
    Rails.logger.info { "[RemittanceReconciliationAgent] Report emailed to #{email}" }
    mark_step_success(report, :send_reconciliation_report, message: "Sent to #{email}") if report
    true
  rescue StandardError => e
    Rails.logger.error { "[RemittanceReconciliationAgent] Email failed: #{e.message}" }
    ctx[:issues] << { type: :warning, message: "Report email failed: #{e.message}", severity: :warning }
    mark_step_failed(report, :send_reconciliation_report, message: "Email error: #{e.message}") if report
    true
  end

  # One query for every payment on this fund whose reference_no matches a deposit on the
  # statement, keyed by reference. Loads the remittance too since the caller needs its call.
  def existing_payments_by_reference(ctx)
    refs = ctx[:deposits].reject { |d| d["internal"] }.map { |d| RemittanceDepositPaymentApplier.reference_no_for(d) }.uniq
    return {} if refs.empty?

    CapitalRemittancePayment.where(fund_id: ctx[:capital_call].fund_id, reference_no: refs)
                            .includes(capital_remittance: :capital_call)
                            .index_by(&:reference_no)
  end

  # Marks a deposit as the payment this call already holds for it: identity comes from the
  # payment's own remittance (no re-matching needed), the amount is judged against the due
  # amount as it stood BEFORE that payment, and the row is tagged already_recorded so the
  # apply step skips it and the panel offers Undo rather than Confirm.
  def apply_recorded_payment(deposit, payment)
    remittance = payment.capital_remittance
    due_before_payment = remittance.due_amount.to_f + payment.amount.to_f
    amount_status, amount_line = classify_amount(deposit["amount"], due_before_payment)

    deposit["matched_remittance_id"] = remittance.id
    deposit["matched_commitment_id"] = remittance.capital_commitment_id
    deposit["matched_investor_name"] = remittance.investor_name
    deposit["identity_via"] = "recorded_payment"
    deposit["kyc_account_number"] = remittance.investor_kyc&.bank_account_number.presence
    deposit["due_amount"] = due_before_payment
    deposit["amount_status"] = amount_status.to_s
    deposit["source_of_funds"] = "unverifiable"
    deposit["reasoning"] = ["already recorded as payment ##{payment.id} on #{I18n.l(payment.payment_date)} (reference #{payment.reference_no})", amount_line]
    deposit["payment_id"] = payment.id
    deposit["payment_status"] = "already_recorded"
    deposit["tier"] = "exact"
  end

  # Mutates `deposit` in place for a :resolved identity — separated from score_deposits'
  # main loop purely so that loop stays readable; not meant to be called standalone.
  def apply_resolved_identity(deposit, identity)
    candidate = identity[:candidate]
    via = identity[:via]

    kyc_account = candidate.investor_kyc&.bank_account_number.presence
    narration_account = deposit["account_number"]
    due_amount = candidate.due_amount.to_f
    reasoning = Array(identity[:reasoning]).dup

    # Source-of-funds check, independent of how identity was resolved (PRD §6.4/§6.6): any
    # account number the narration exposes is the SENDER's account — including the virtual
    # account case, where the investor remits from the account assigned to them — so whenever
    # the investor has a KYC-registered account on file, the two must agree. A :kyc_account
    # match agrees by construction; a :virtual_account or :name match is checked here. With no
    # KYC account on file there is nothing to contradict, so nothing is raised (§12.6).
    discrepancy = via != :kyc_account && narration_account.present? && kyc_account.present? && kyc_account != narration_account
    reasoning << "narration account #{narration_account} contradicts the investor's KYC-registered account #{kyc_account}" if discrepancy

    # Amount classification drives both the tier and the reviewer-facing reasoning line, so a
    # Needs review row always says *why* it landed there (PRD §8 sample report).
    amount_status, amount_line = classify_amount(deposit["amount"], due_amount)
    reasoning << amount_line

    deposit["matched_remittance_id"] = candidate.id
    deposit["matched_commitment_id"] = candidate.capital_commitment_id
    deposit["matched_investor_name"] = candidate.investor_name
    deposit["identity_via"] = via.to_s
    deposit["kyc_account_number"] = kyc_account # what the sender account was checked against; shown next to a discrepancy
    deposit["due_amount"] = due_amount
    deposit["amount_status"] = amount_status.to_s
    deposit["reasoning"] = reasoning
    deposit["source_of_funds"] =
      if narration_account.blank? || kyc_account.blank?
        "unverifiable"
      elsif discrepancy
        "discrepancy"
      else
        "confirmed"
      end

    # Tier (PRD §6.4 + §6.5): a discrepancy or an overpayment always caps at Needs review. A
    # partial payment (shortfall beyond tolerance) does NOT downgrade — the payment is created
    # for the amount actually received and the remittance's own due_amount carries the
    # shortfall — so an unambiguous account match stays Exact and a name match stays Probable.
    deposit["tier"] =
      if discrepancy || %i[overpaid unknown].include?(amount_status)
        "needs_review"
      elsif %i[kyc_account virtual_account].include?(via)
        "exact"
      else
        "probable"
      end
  end

  # Compares a deposit against the remittance's outstanding due amount and returns
  # [status, reviewer-facing reasoning line]:
  #   :within_tolerance — |deposit - due| inside tolerance_amount OR tolerance_pct
  #   :partial          — deposit short of due by more than tolerance (a tranche; accepted)
  #   :overpaid         — deposit exceeds due by more than tolerance (surplus may belong to
  #                       another call, which a call-scoped run can't see — flagged, PRD §6.5)
  #   :unknown          — the statement row carried no readable amount at all
  def classify_amount(deposit_amount, due_amount)
    return [:unknown, "no readable amount on the statement row — amount could not be checked"] if deposit_amount.nil?

    fmt = ->(v) { ActiveSupport::NumberHelper.number_to_delimited(format("%.2f", v)) }
    diff = deposit_amount - due_amount
    return [:within_tolerance, "amount #{fmt.call(deposit_amount)} within tolerance of due #{fmt.call(due_amount)}"] if amount_within_tolerance?(deposit_amount, due_amount)

    if diff.negative?
      [:partial, "partial payment: #{fmt.call(deposit_amount)} received against due #{fmt.call(due_amount)} (shortfall #{fmt.call(diff.abs)})"]
    else
      [:overpaid, "overpayment: #{fmt.call(deposit_amount)} exceeds due #{fmt.call(due_amount)} by #{fmt.call(diff)} — " \
                  "check whether the surplus belongs to one of this investor's other open calls"]
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
               reasoning: ["sender account #{account} matches the investor's KYC bank account"] }
    elsif kyc_matches.size > 1
      return { status: :ambiguous, reasoning: ["sender account #{account} is on the KYC of #{kyc_matches.size} different investors"] }
    end

    virtual_matches = candidates.select { |c| c.capital_commitment.virtual_bank_account.presence == account }
    if virtual_matches.size == 1
      return { status: :resolved, candidate: virtual_matches.first, via: :virtual_account,
               reasoning: ["sender account #{account} matches the investor's assigned virtual account"] }
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
      "payments_recorded_elsewhere" => ctx[:payments_recorded_elsewhere] || 0,
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
