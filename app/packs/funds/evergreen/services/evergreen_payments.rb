# The settlement tracker's money actions, through the existing payment services (design card ⑥):
#   record_subscription_payment — CapitalRemittancePaymentCreate, then CapitalRemittanceVerify
#   verify                      — CapitalRemittanceVerify (when bank reconciliation recorded the money)
#   mark_redemption_paid        — CapitalDistributionPaymentUpdate (completed + payment date)
# Unit moves follow from the after-commit hook (EvergreenSettlementHooks).
# Worked examples H23, H24, walkthrough rows 4–5 — openspec/changes/open-ended-funds/design.md#worked-examples
module EvergreenPayments
  module_function

  def record_subscription_payment(remittance, amount:, payment_date:, reference:, user:)
    owed = remittance.call_amount_cents.to_d - remittance.collected_amount_cents.to_d
    # X87: fully paid (within the 10-paise tolerance) — a second click records nothing
    return [false, "Nothing is owed on this subscription"] if owed <= 10

    amount_cents = amount.present? ? amount.to_s.delete(",").to_d * 100 : owed
    # X86: a zero or negative payment is refused
    return [false, "Enter an amount greater than zero"] unless amount_cents.positive?

    payment = CapitalRemittancePayment.new(entity_id: remittance.entity_id, fund_id: remittance.fund_id, capital_remittance: remittance,
                                           amount_cents:, folio_amount_cents: amount_cents, payment_date: payment_date.presence || Time.zone.today,
                                           reference_no: reference.to_s.first(40))
    result = CapitalRemittancePaymentCreate.call(capital_remittance_payment: payment)
    return [false, result[:errors].presence || payment.errors.full_messages.to_sentence] unless result.success?

    verify(remittance.reload, user)
  end

  # Verifying is a toggle in the existing service, so only call it when not yet verified
  def verify(remittance, user)
    return [true, nil] if remittance.verified

    result = CapitalRemittanceVerify.call(capital_remittance: remittance, current_user: user)
    result.success? ? [true, nil] : [false, result[:errors].presence || "Could not verify the payment"]
  end

  def mark_redemption_paid(payment, payment_date:, reference:)
    # X88: a second Mark paid must not overwrite the recorded date and bank reference
    return [false, "Already marked paid#{" on #{I18n.l(payment.payment_date)}" if payment.payment_date}"] if payment.completed

    payment.assign_attributes(completed: true, payment_date: payment_date.presence || Time.zone.today)
    # CapitalDistributionPayment has no notes column; the bank reference is kept in json_fields
    payment.json_fields = (payment.json_fields || {}).merge("payment_reference" => reference) if reference.present?
    result = CapitalDistributionPaymentUpdate.call(capital_distribution_payment: payment)
    result.success? ? [true, nil] : [false, result[:errors].presence || payment.errors.full_messages.to_sentence]
  end
end
