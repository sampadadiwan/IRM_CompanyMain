# Skip check for "Run AML screening": AML is not enabled for the company.
# Worked examples E8 — openspec/changes/investor-kyc-journey/design.md#worked-examples
module WorkflowChecks
  module InvestorKyc
    class AmlOff < WorkflowChecks::Base
      include Support

      self.key = "investor_kyc.aml_off"
      self.label = "AML screening is not enabled"
      self.workflowable_type = "InvestorKyc"

      def call(kyc)
        return pass(message: "AML screening is not enabled") unless kyc.entity.entity_setting&.aml_enabled

        fail_with(message: "AML screening is enabled")
      end
    end
  end
end
