# Skip check for "Clear AML match": AML is off, or the result is no match without anyone overriding it
# (an override to no match is shown as done by ClearAmlMatch, naming who cleared it).
# Worked examples H6, E8 — openspec/changes/investor-kyc-journey/design.md#worked-examples
module WorkflowChecks
  module InvestorKyc
    class NoAmlMatch < WorkflowChecks::Base
      include Support

      self.key = "investor_kyc.no_aml_match"
      self.label = "No AML match"
      self.workflowable_type = "InvestorKyc"

      def call(kyc)
        return pass(message: "AML screening is not enabled") unless kyc.entity.entity_setting&.aml_enabled
        return pass(message: "No AML match") if aml_result(kyc) == "no_match" && !kyc.aml_manual_override

        fail_with(message: "AML match to review")
      end
    end
  end
end
