# 6. Clear AML match — a potential match has been reviewed and overridden to no match. n/a when there
# is no match at all (NoAmlMatch). A match confirmed by an override stays here: the KYC should not be
# verified (the journey is advisory, so Verify still works).
# Worked examples H10, E7 — openspec/changes/investor-kyc-journey/design.md#worked-examples
module WorkflowChecks
  module InvestorKyc
    class ClearAmlMatch < WorkflowChecks::Base
      include Support

      self.key = "investor_kyc.clear_aml_match"
      self.label = "Clear AML match"
      self.workflowable_type = "InvestorKyc"

      def call(kyc)
        return pass(message: "No AML match") if aml_result(kyc) == "no_match" && !kyc.aml_manual_override

        if aml_result(kyc) == "no_match"
          by = overridden_by(kyc)
          return pass(message: ["Overridden#{" by #{by}" if by}", kyc.aml_override_reason.presence].compact.join(": "))
        end

        if kyc.aml_manual_override && aml_result(kyc) == "potential_match"
          return fail_with(message: "AML match confirmed — this KYC should not be verified",
                           action_label: "View AML Reports", action_path: kyc_path(kyc), action_target: AML_VIEW_BTN)
        end

        fail_with(message: "AML found a potential match — review the report and override it if it is a false positive",
                  action_label: "View AML Reports", action_path: kyc_path(kyc), action_target: AML_VIEW_BTN)
      end

      private

      # Who set the override (the audit that turned aml_manual_override on)
      def overridden_by(kyc)
        kyc.audits.where(action: "update").where("audited_changes LIKE ?", "%aml_manual_override%").order(created_at: :desc)
           .first&.user&.full_name
      end
    end
  end
end
