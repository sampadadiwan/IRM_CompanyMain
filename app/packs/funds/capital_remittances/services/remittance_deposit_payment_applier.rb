# Applies one parsed bank-statement deposit (as produced by RemittanceReconciliationAgent) to
# one CapitalRemittance as a CapitalRemittancePayment. Idempotent — skips with
# status: :already_recorded when a payment with this reference_no already exists on the fund,
# rather than attempting a create that would fail CapitalRemittancePayment's own DB-level
# `validates_uniqueness_of :reference_no, scope: :fund_id`.
#
# Shared by two callers that must dedupe and build the payment identically:
#   - RemittanceReconciliationAgent#apply_exact_matches (the agent's own auto-apply step)
#   - CapitalCallsController#confirm_reconciliation_deposit / #reassign_reconciliation_deposit
#     (a reviewer manually confirming a Probable/Needs review deposit, or reassigning a
#     No match deposit to a different CapitalRemittance via Folio No / Virtual Bank Account)
#
# Writes amount_cents directly (the bank statement figure is already fund currency) with
# convert_to_fund_currency: false, so CapitalRemittancePaymentCreate's set_amount step no-ops
# rather than attempting a folio-currency conversion there's no folio-currency figure for -
# mirrors the model's own set_amount comment ("In imports we have the amount_cents also
# already setup, so no conversion is needed"). investor_id is set explicitly because it's
# normally populated by set_amount itself; bypassing that step means bypassing that
# assignment too.
module RemittanceDepositPaymentApplier
  module_function

  # @param deposit [Hash] one entry from SupportAgentReport#json_fields["deposits"]
  # @param capital_remittance [CapitalRemittance] already resolved and already verified to
  #   belong to the capital call being reconciled — the caller's responsibility, not this
  #   method's, since "which call" differs between the two callers above.
  # @param fund [Fund]
  # @return [Hash] {status: :created, payment_id:, reference_no:} |
  #   {status: :already_recorded, payment_id:, reference_no:} | {status: :error, error:}
  def call(deposit:, capital_remittance:, fund:)
    reference_no = reference_no_for(deposit)

    existing = CapitalRemittancePayment.find_by(fund: fund, reference_no: reference_no)
    return { status: :already_recorded, payment_id: existing.id, reference_no: reference_no } if existing

    return { status: :error, error: "deposit has no amount" } if deposit["amount"].nil?

    payment = CapitalRemittancePayment.new(
      fund: fund,
      entity: capital_remittance.entity,
      capital_remittance: capital_remittance,
      investor_id: capital_remittance.investor_id,
      convert_to_fund_currency: false,
      payment_date: deposit["value_date"].present? ? Date.parse(deposit["value_date"]) : Time.zone.today,
      reference_no: reference_no,
      notes: "Applied from bank statement row #{deposit['row']} (#{deposit['sheet']}): #{deposit['raw_narration']}"
    )
    payment.amount = deposit["amount"]
    # Only when currencies actually match is deposit["amount"] also a valid folio-currency
    # figure - otherwise leave folio_amount unset rather than writing a wrong number into it.
    payment.folio_amount = deposit["amount"] if capital_remittance.capital_commitment.folio_currency == fund.currency

    result = CapitalRemittancePaymentCreate.wtf?(capital_remittance_payment: payment)
    if result.success?
      { status: :created, payment_id: payment.id, reference_no: reference_no }
    else
      { status: :error, error: result[:errors] || payment.errors.full_messages.join(", ") }
    end
  end

  # The bank's own transaction id where the statement exposes one (ICICI's "Tran Id" column);
  # otherwise a deterministic hash of sheet+row+narration+amount, stable across re-runs of the
  # same statement (row numbers don't change on a re-upload of the same file) so idempotency
  # doesn't depend on every bank export having a Tran Id column. `row` is included specifically
  # so two genuinely distinct deposits that happen to share identical narration text and amount
  # (e.g. repeat fixed-amount installments from the same payer) don't collide onto the same
  # reference and get treated as duplicates of each other. "SYN-" prefix makes a synthetic
  # reference visually distinguishable from a real one.
  def reference_no_for(deposit)
    deposit["tran_id"].presence ||
      "SYN-#{Digest::SHA256.hexdigest("#{deposit['sheet']}|#{deposit['row']}|#{deposit['raw_narration']}|#{deposit['amount']}")[0, 16]}"
  end
end
