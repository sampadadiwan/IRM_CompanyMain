# Service for listing and filtering Capital Remittance Payments.
#
# This service encapsulates the logic for Ransack search, Pundit scoping,
# and various filters used in the CapitalRemittancePaymentsController index action.
#
# It ensures that a policy scope is always applied to the query:
# 1. If a block is given, it yields the relation to the block (allowing controllers to use `policy_scope` helper).
# 2. If no block is given, it uses `Pundit.policy_scope!` directly.
class CapitalRemittancePaymentList < BaseList
  Result = Struct.new(:q, :capital_remittance_payments, keyword_init: true)

  def call(&)
    @q = CapitalRemittancePayment.ransack(@params[:q])
    @capital_remittance_payments = apply_policy_scope(@q.result, &)

    @capital_remittance_payments = @capital_remittance_payments.includes(:fund, :investor, capital_remittance: :capital_commitment)

    @capital_remittance_payments = filter_params(@capital_remittance_payments, :fund_id, :import_upload_id)

    Result.new(
      q: @q,
      capital_remittance_payments: @capital_remittance_payments
    )
  end
end
