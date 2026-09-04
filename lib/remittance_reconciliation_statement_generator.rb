# frozen_string_literal: true

require "caxlsx"

# Generates a bank statement workbook for ONE existing CapitalCall, in ONE bank's export
# format (ICICI or Axis — the two BankDepositNarrationParser has dedicated modules for), from
# that call's own live remittances, crafted so that running RemittanceReconciliationAgent
# against it produces one of every outcome the agent can reach:
#
#   Exact (sender account = KYC account, amount = due)      Exact + Partial (60% of due)
#   Exact (short by 350, inside the wire-charge tolerance)   Exact via virtual account (if any commitment has one)
#   Probable (name only, no account exposed)                 Needs review — funding-source discrepancy
#   Needs review — overpayment                               No match (unknown depositor)
#   Internal (the fund's own FD maturity; Axis only — ICICI   a withdrawal row the parser must ignore
#     exports have no internal-movement narration pattern)
#
# Roles are handed out in that order to the call's remittances that have what the role needs
# (an account-based role needs the investor's InvestorKyc#bank_account_number on file; the
# virtual-account role needs CapitalCommitment#virtual_bank_account), so it works on any call
# with a few remittances — on a call whose investors have no KYC bank accounts, only the
# name-only roles are produced and the summary says so.
#
# Coverage: "full" (default) then adds an ordinary deposit for EVERY other outstanding
# remittance on the call (Exact for those with a KYC account, name-only Probable otherwise), so
# the statement pays the whole call and the reviewer sees one row per remittance. "sample"
# stops after the role rows — one row per outcome, a short readable statement.
#
# Nothing is created or modified in the database; the only output is the xlsx
# (public/sample_uploads/remittance_recon_call_<id>_<bank>[_sample].xlsx) and, with run: true,
# an agent run against the call (which does create a Document and a SupportAgentReport, and
# — only if the agent's auto_apply_exact is Yes — payments).
#
# Usage: rake "remittance_reconciliation:statement[<capital_call_id>,icici]"
#        rake "remittance_reconciliation:statement[<capital_call_id>,axis,sample]"
#        rake "remittance_reconciliation:statement[<capital_call_id>,icici,full,run]"
class RemittanceReconciliationStatementGenerator
  SAMPLE_DIR = Rails.public_path.join('sample_uploads')
  BANKS = %w[icici axis].freeze

  # Each role: what the remittance must have, how the amount is derived from the remittance's
  # due amount, and the outcome the agent should produce. The narration shape per bank is in
  # #narration_for.
  ROLES = [
    { key: :exact,        needs: :kyc_account, amount: ->(due) { due },
      expect: "Exact — sender account = KYC account, amount = due" },
    { key: :partial,      needs: :kyc_account, amount: ->(due) { (due * 0.6).round(2) },
      expect: "Exact + Partial — 60% of due received; payment (if applied) is for the amount received" },
    { key: :tolerance,    needs: :kyc_account, amount: ->(due) { (due - 350).round(2) },
      expect: "Exact — 350 short, inside the default 500 wire-charge tolerance" },
    { key: :virtual,      needs: :virtual_account, amount: ->(due) { due },
      expect: "Exact via virtual account (a KYC account on file that differs would make this a discrepancy instead)" },
    { key: :probable,     needs: :none, amount: ->(due) { due },
      expect: "Probable — name only, no sender account exposed; awaits Confirm" },
    { key: :discrepancy,  needs: :kyc_account, amount: ->(due) { due },
      expect: "Needs review — funding-source discrepancy: sender account differs from the investor's KYC account" },
    { key: :overpaid,     needs: :kyc_account, amount: ->(due) { (due + 250_000).round(2) },
      expect: "Needs review — overpayment of 2,50,000 beyond tolerance (surplus may belong to another call)" }
  ].freeze

  COVERAGES = %w[sample full].freeze

  # Roles used only by full coverage for the remaining remittances — plain, in-full payments.
  FULL_EXACT_ROLE = { key: :exact, needs: :kyc_account, amount: ->(due) { due },
                      expect: "Exact — paid in full from the KYC account" }.freeze
  FULL_PROBABLE_ROLE = { key: :probable, needs: :none, amount: ->(due) { due },
                         expect: "Probable — paid in full, name only (no KYC account on file)" }.freeze

  def initialize(capital_call_id, bank: "icici", coverage: "full", run_agent: false, output: $stdout)
    @capital_call = CapitalCall.find(capital_call_id)
    @fund = @capital_call.fund
    @entity = @capital_call.entity
    @bank = bank.to_s.downcase
    raise ArgumentError, "bank must be one of #{BANKS.join(', ')} (got #{bank.inspect})" unless BANKS.include?(@bank)

    @coverage = coverage.to_s.downcase
    raise ArgumentError, "coverage must be one of #{COVERAGES.join(', ')} (got #{coverage.inspect})" unless COVERAGES.include?(@coverage)

    @run_agent = run_agent
    @out = output
  end

  def call
    @out.puts "== #{@bank.upcase} statement (#{@coverage}) for Capital Call ##{@capital_call.id} (#{@fund.name} / #{@capital_call.name}) =="
    remittances = @capital_call.capital_remittances.includes(capital_commitment: :investor_kyc).order(:id).to_a
    abort_with "This call has no remittances — generate them first (approve the call / run CapitalCallJob)." if remittances.empty?

    rows = statement_rows(remittances)
    path = write_workbook(rows)
    @out.puts "Statement: #{path}\n\n"
    print_expectations(rows)
    print_unassigned(remittances, rows)

    if @run_agent
      run_agent!(path)
    else
      @out.puts "\nNext: open the capital call page, Actions -> Run Reconciliation, upload #{path.basename}."
    end
  end

  private

  # ── Row design ─────────────────────────────────────────────────────────────

  # Hands each role to the first not-yet-used remittance that has what the role needs; a role
  # nobody can fill is skipped (and reported). The unknown-depositor, internal and withdrawal
  # rows need no remittance at all.
  def statement_rows(remittances)
    available = remittances.select { |r| r.due_amount.to_f.positive? }
    rows = []

    ROLES.each do |role|
      remittance = available.find { |r| satisfies?(r, role[:needs]) }
      next unless remittance

      available.delete(remittance)
      rows << build_row(role, remittance)
    end

    # Full coverage: everyone else pays too, in the plainest way their data allows.
    if @coverage == "full"
      available.each do |remittance|
        role = kyc_account(remittance).present? ? FULL_EXACT_ROLE : FULL_PROBABLE_ROLE
        rows << build_row(role, remittance)
      end
      available.clear
    end

    rows << { narration: name_only_narration("NOBODY MATCHES ME"), amount: 100_000.0, investor: nil,
              expect: "No match — no remittance under this call for that name; Reassign by Folio No" }
    if @bank == "axis"
      rows << { narration: "9260400797932#{@capital_call.id % 10}5 : Closure Proceeds", amount: 3_003_452.10, investor: nil,
                expect: "Internal — the fund's own fixed deposit maturing back; excluded from matching" }
    end
    rows << { narration: "SGB/3101499/#{@fund.name.upcase.gsub(/[^A-Z0-9 ]/, '')[0, 20]}/Transfer", amount: 1_900_000.0, withdrawal: true, investor: nil,
              expect: "Withdrawal — never appears in the report" }
    rows
  end

  def satisfies?(remittance, needs)
    case needs
    when :kyc_account then kyc_account(remittance).present?
    when :virtual_account then remittance.capital_commitment.virtual_bank_account.present?
    else true
    end
  end

  def build_row(role, remittance)
    due = remittance.due_amount.to_f.round(2)
    { narration: narration_for(role, remittance), amount: role[:amount].call(due),
      investor: remittance.investor_name.to_s, due: due, expect: role[:expect] }
  end

  # The narration in the chosen bank's own export style (see IciciNarrationParser /
  # AxisNarrationParser for the shapes each recognises).
  #   ICICI: RTGS-<ref>-<NAME>-<sender account>-<sender IFSC> carries the account; the
  #          name-only rail is "TRFR FROM:<name>".
  #   Axis:  MOB/TPFT/<name>/<sender account> carries the account; the name-only rail is
  #          "TRF/<name>/TRANSFER".
  def narration_for(role, remittance)
    name = remittance.investor_name.to_s
    account =
      case role[:key]
      when :virtual then remittance.capital_commitment.virtual_bank_account
      # A syntactically valid but different sender account — the investor's own KYC account
      # is NOT the one paying.
      when :discrepancy then "6000#{format('%010d', remittance.id)}"
      when :probable then nil
      else kyc_account(remittance)
      end
    return name_only_narration(name) if account.nil?

    if @bank == "icici"
      "RTGS-#{utr(remittance)}-#{concat(name)}-#{account}-#{role[:key] == :discrepancy ? 'KKBK0000958' : 'HDFC0000240'}"
    else
      "MOB/TPFT/#{name.upcase}/#{account}"
    end
  end

  def name_only_narration(name)
    @bank == "icici" ? "TRFR FROM:#{name.upcase}" : "TRF/#{name.upcase}/TRANSFER"
  end

  def kyc_account(remittance)
    remittance.investor_kyc&.bank_account_number.presence
  end

  # ICICI strips every space from the beneficiary name ("SANDEEPKUMARSINGH").
  def concat(name)
    name.upcase.gsub(/[^A-Z0-9]/, "")
  end

  # UTR-shaped reference unique per remittance, so re-generating for the same call yields the
  # same narrations (and the Tran Id column below the same ids) — re-runs stay idempotent.
  def utr(remittance)
    "HDFCR5#{format('%08d', @capital_call.id)} #{format('%07d', remittance.id)}"
  end

  # ── Workbook ───────────────────────────────────────────────────────────────

  # One sheet, in the layout BankDepositNarrationParser.each_deposit_narration recognises for
  # that bank, including the account-statement header line detect_bank scans for the issuing
  # bank's IFSC. ICICI's "Tran Id" column is deterministic per call+row, so the
  # bank-transaction-id reference path is exercised and a re-upload of a regenerated file
  # dedups correctly; Axis exports carry no transaction id, so the agent's synthetic
  # SYN- reference path is exercised there instead.
  def write_workbook(rows)
    FileUtils.mkdir_p(SAMPLE_DIR)
    path = SAMPLE_DIR.join("remittance_recon_call_#{@capital_call.id}_#{@bank}#{'_sample' if @coverage == 'sample'}.xlsx")
    package = Axlsx::Package.new
    value_date = [@capital_call.due_date, Time.zone.today].min

    if @bank == "icici"
      package.workbook.add_worksheet(name: "ICICI") do |sheet|
        sheet.add_row(["ICICI Bank Limited - Account Statement"])
        sheet.add_row(["A/C No: 0004#{format('%08d', @fund.id)}    IFSC: ICIC0000004    Branch: Demo"])
        sheet.add_row(["Statement Period: #{(value_date - 20).strftime('%d/%m/%Y')} To #{value_date.strftime('%d/%m/%Y')}"])
        sheet.add_row([])
        sheet.add_row(["Sl No", "Tran Id", "Value Date", "Transaction Remarks", "Withdrawal (Dr)", "Deposit (Cr)"])
        rows.each_with_index do |row, i|
          sheet.add_row([i + 1, "S#{format('%06d', @capital_call.id)}#{format('%03d', i + 1)}", value_date.strftime("%d/%b/%Y"), row[:narration],
                         row[:withdrawal] ? row[:amount] : nil, row[:withdrawal] ? nil : row[:amount]])
        end
        sheet.add_row(["", "", "", "TOTAL", nil, rows.reject { |r| r[:withdrawal] }.sum { |r| r[:amount] }])
      end
    else
      package.workbook.add_worksheet(name: "Axis") do |sheet|
        sheet.add_row(["Axis Bank - Statement of Account"])
        sheet.add_row(["A/C No: 9210#{format('%08d', @fund.id)}    IFSC: UTIB0000123    Branch: Demo"])
        sheet.add_row([])
        sheet.add_row(["S.No", "Transaction Date", "Particulars", "Amount (INR)", "Debit/Credit"])
        rows.each_with_index do |row, i|
          sheet.add_row([i + 1, value_date.strftime("%d/%m/%Y"), row[:narration], row[:amount], row[:withdrawal] ? "DR" : "CR"])
        end
      end
    end

    package.serialize(path.to_s)
    path
  end

  # ── Reporting ──────────────────────────────────────────────────────────────

  def print_expectations(rows)
    bulk_expects = [FULL_EXACT_ROLE[:expect], FULL_PROBABLE_ROLE[:expect]]
    @out.puts "#   | Investor                     |         Amount |            Due | Expected outcome"
    rows.each_with_index do |row, i|
      next if bulk_expects.include?(row[:expect]) # the bulk "paid in full" rows are summarised below

      @out.puts format("%-3s | %-28s | %14s | %14s | %s", i + 1, (row[:investor] || "-")[0, 28],
                       delimited(row[:amount]), row[:due] ? delimited(row[:due]) : "-", row[:expect])
      @out.puts format("%-3s | %s", "", row[:narration])
    end
    bulk = rows.select { |r| bulk_expects.include?(r[:expect]) }
    return if bulk.empty?

    @out.puts "... plus #{bulk.size} remaining remittance(s) paid in full: " \
              "#{bulk.count { |r| r[:expect] == FULL_EXACT_ROLE[:expect] }} Exact (KYC account), " \
              "#{bulk.count { |r| r[:expect] == FULL_PROBABLE_ROLE[:expect] }} Probable (name only)"
  end

  # Roles nobody could fill (and why), and outstanding remittances left with no deposit —
  # which stay Pending, the "investor hasn't paid yet" case a controller sees alongside
  # everything above. Already-settled remittances (nothing due) are never candidates.
  def print_unassigned(remittances, rows)
    outstanding = remittances.select { |r| r.due_amount.to_f.positive? }
    with_account = outstanding.count { |r| kyc_account(r).present? }
    @out.puts "\nRemittances: #{remittances.size} on this call, #{outstanding.size} with an amount still due, " \
              "#{with_account} of those with a KYC bank account on file"

    missing = ROLES.reject { |role| rows.any? { |r| r[:expect] == role[:expect] } }
    if missing.any?
      @out.puts "Roles skipped: #{missing.pluck(:key).join(', ')}"
      @out.puts "  -> every role needs a remittance with an amount still due; account-based roles also need " \
                "InvestorKyc#bank_account_number on the commitment's KYC, and the virtual role needs " \
                "CapitalCommitment#virtual_bank_account. Pick a call with more outstanding remittances for the full set."
    end

    used = rows.filter_map { |r| r[:investor] }
    left = outstanding.reject { |r| used.include?(r.investor_name.to_s) }
    return if left.empty?

    shown = left.first(10).map(&:investor_name)
    @out.puts "Outstanding remittances with no deposit on this statement (stay Pending): #{shown.join(', ')}" \
              "#{" and #{left.size - 10} more" if left.size > 10}"
  end

  def delimited(value)
    ActiveSupport::NumberHelper.number_to_delimited(format("%.2f", value))
  end

  def abort_with(message)
    @out.puts message
    raise ArgumentError, message
  end

  # ── Optional: run the agent right away ─────────────────────────────────────

  def run_agent!(path)
    support_agent = SupportAgent.find_by(entity_id: @entity.id, agent_type: "RemittanceReconciliationAgent")
    abort_with "No RemittanceReconciliationAgent for entity #{@entity.id} — run rake \"support_agents:setup[#{@entity.id}]\" first." unless support_agent
    @out.puts "\nNote: the entity's capital_remittance_reconciliation_agent flag is off — the capital call page won't show the panel." unless @entity.support_agents.set?(:capital_remittance_reconciliation_agent)

    doc = Document.new(name: "Bank Statement (generated, #{@bank.upcase})", entity: @entity, owner: @capital_call, folder: @capital_call.document_folder,
                       user: @entity.employees.first, send_email: false, orignal: true)
    doc.file = File.open(path)
    doc.save!

    Chewy.strategy(:bypass) do
      RemittanceReconciliationAgent.wtf?(support_agent_id: support_agent.id, target: @capital_call, bank_statement_document_id: doc.id)
    end

    rpt = SupportAgentReport.where(owner: @capital_call, support_agent: support_agent).order(created_at: :desc).detect { |r| r.json_fields.key?("deposits") }
    data = rpt.json_fields
    @out.puts "\nReport ##{rpt.id}: #{data['tier_counts']}  discrepancies=#{data['discrepancy_count']}  " \
              "payments_created=#{data['payments_created']} (auto_apply_exact=#{data['auto_apply_exact']})"
    @out.puts "  tier         amount           source        investor                     narration"
    data["deposits"].each do |d|
      @out.puts format("  %-12s %-16s %-13s %-28s %s", d["tier"], d["amount_status"].to_s, d["source_of_funds"].to_s,
                       (d["matched_investor_name"] || "-")[0, 28], d["raw_narration"][0, 60])
    end
    (data["issues"] || []).each { |i| @out.puts "  [#{i['severity']}] #{i['message']}" }
  end
end
