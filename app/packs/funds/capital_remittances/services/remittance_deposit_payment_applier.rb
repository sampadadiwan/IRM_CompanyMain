# Applies one parsed bank-statement deposit (as produced by RemittanceReconciliationAgent) to
# one CapitalRemittance as a CapitalRemittancePayment. Idempotent — skips with
# status: :already_recorded when a payment with this reference_no already exists on the fund
# *under the same capital call*, rather than attempting a create that would fail
# CapitalRemittancePayment's own DB-level `validates_uniqueness_of :reference_no, scope: :fund_id`.
#
# A payment with this reference that exists on the fund but under a *different* capital call
# (the same statement was run against two calls whose due windows overlap) comes back as
# status: :recorded_elsewhere — it is neither re-created (the uniqueness validation would
# reject it anyway) nor reported as "recorded" for this call, since the money was applied to
# another call's remittance and an Undo here must never be able to delete that payment.
#
# Shared by two callers that must dedupe and build the payment identically:
#   - RemittanceReconciliationAgent#apply_exact_matches (the agent's own auto-apply step)
#   - CapitalCallsController#confirm_reconciliation_deposit / #reassign_reconciliation_deposit
#     (a reviewer manually confirming a Probable/Needs review deposit, or reassigning a
#     No match deposit to a different CapitalRemittance via Folio No / Virtual Bank Account)
#
# Amounts: the statement figure is already in fund currency, so `amount` is set from it
# directly with convert_to_fund_currency: false (CapitalRemittancePaymentCreate's set_amount
# step converts the *other* way, folio -> fund, and would have nothing to convert from).
# The folio-currency figure is then derived through the fund's own recorded exchange rate via
# WithExchangeRate#convert_currency (fund -> folio, as of the payment date) — never invented —
# so a foreign-currency folio's folio_collected_amount moves exactly as it would for a manual
# entry, and CapitalRemittance#set_status (which reads folio_due_amount) can reach Paid.
# investor_id is set explicitly because set_amount, which normally populates it, is bypassed.
module RemittanceDepositPaymentApplier
  module_function

  # @param deposit [Hash] one entry from SupportAgentReport#json_fields["deposits"]
  # @param capital_remittance [CapitalRemittance] already resolved and already verified to
  #   belong to the capital call being reconciled — the caller's responsibility, not this
  #   method's, since "which call" differs between the two callers above.
  # @param fund [Fund]
  # @return [Hash] {status: :created, payment_id:, reference_no:} |
  #   {status: :already_recorded, payment_id:, reference_no:} |
  #   {status: :recorded_elsewhere, payment_id:, reference_no:, error:} |
  #   {status: :error, error:}
  def call(deposit:, capital_remittance:, fund:)
    reference_no = reference_no_for(deposit)

    existing = CapitalRemittancePayment.find_by(fund: fund, reference_no: reference_no)
    if existing
      # Same reference, same call: a genuine re-run — nothing to do.
      return { status: :already_recorded, payment_id: existing.id, reference_no: reference_no } if existing.capital_remittance&.capital_call_id == capital_remittance.capital_call_id

      # Same reference, different call: the deposit was already applied elsewhere on this fund.
      other_call = existing.capital_remittance&.capital_call
      return { status: :recorded_elsewhere, payment_id: existing.id, reference_no: reference_no,
               error: "already recorded as a payment against #{other_call&.name || 'another capital call'} (payment ##{existing.id})" }
    end

    return { status: :error, error: "deposit has no amount" } if deposit["amount"].nil?

    payment_date = deposit["value_date"].present? ? Date.parse(deposit["value_date"]) : Time.zone.today
    payment = CapitalRemittancePayment.new(
      fund: fund,
      entity: capital_remittance.entity,
      capital_remittance: capital_remittance,
      investor_id: capital_remittance.investor_id,
      convert_to_fund_currency: false,
      payment_date: payment_date,
      reference_no: reference_no,
      notes: "Applied from bank statement row #{deposit['row']} (#{deposit['sheet']}): #{deposit['raw_narration']}"
    )
    payment.amount = deposit["amount"]

    folio_currency = capital_remittance.capital_commitment.folio_currency.presence || fund.currency
    begin
      # convert_currency returns the input unchanged when the currencies match, so this is a
      # single path for both same-currency and foreign-currency folios. It also records the
      # ExchangeRate used on payment.exchange_rate, exactly as a manual folio->fund entry does.
      payment.folio_amount_cents = payment.convert_currency(fund.currency, folio_currency, payment.amount_cents, payment_date)
    rescue ActiveRecord::RecordInvalid
      # No exchange rate on file for that pair/date — refuse rather than record a payment
      # whose folio amount would be zero (which would leave the remittance unpayable).
      return { status: :error, error: "No exchange rate from #{fund.currency} to #{folio_currency} on or before #{I18n.l(payment_date)} — add one under Exchange Rates and retry" }
    end

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
