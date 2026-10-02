# 9. Collect payments — every remittance has collected what it calls (call amount + other fees),
# from payments recorded on it. This reads the remittances, not the call: the call's own
# collected_amount only counts VERIFIED remittances, so it would wait for verification (step 10).
# A 10-cent tolerance matches CapitalRemittance#set_status (folio-currency rounding).
# Worked examples H6 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalCall
    class CollectPayments < WorkflowChecks::Base
      include Support

      TOLERANCE_CENTS = 10

      self.key = "capital_call.collect_payments"
      self.label = "Collect payments"
      self.workflowable_type = "CapitalCall"

      def call(call)
        due = remittances(call).sum("call_amount_cents + other_fee_cents")
        collected = remittances(call).sum(:collected_amount_cents)
        short = remittances(call).where("collected_amount_cents < call_amount_cents + other_fee_cents - ?", TOLERANCE_CENTS)
        if due.positive? && !short.exists?
          last_payment = ::CapitalRemittancePayment.where(capital_remittance_id: remittances(call).select(:id)).maximum(:created_at)
          return pass(message: "All payments collected", passed_since: last_payment)
        end

        percent = due.positive? ? [(collected * 100.0 / due).floor, 100].min : 0
        fail_with(message: "Collected #{percent}%", action_label: "View remittances",
                  action_path: call_path(call), action_target: REMITTANCES_TAB)
      end
    end
  end
end
