# 5. Run AML screening — the KYC has an AML result. n/a when AML is not enabled (AmlOff).
# Worked examples H6 — openspec/changes/investor-kyc-journey/design.md#worked-examples
module WorkflowChecks
  module InvestorKyc
    class RunAml < WorkflowChecks::Base
      include Support

      self.key = "investor_kyc.run_aml"
      self.label = "Run AML screening"
      self.workflowable_type = "InvestorKyc"
      # What the step popup says (journey_step_info): what to do, why the step exists, and what
      # completing it changes — including whether anyone outside the team is emailed
      self.how = "Click Generate AML Report."
      self.why = "Screens the investor against sanctions and watch lists before they are accepted."
      self.effects = "An AML report is generated and attached to the KYC. The investor is not emailed."

      def call(kyc)
        latest = kyc.aml_reports.maximum(:created_at)
        result = aml_result(kyc)
        return pass(message: "AML result: #{result.humanize}", passed_since: latest) if result

        message = latest ? "AML report requested — waiting for the result" : "No AML report yet"
        fail_with(message:, action_label: "Generate AML Report", action_path: kyc_path(kyc), action_target: AML_GENERATE_BTN)
      end
    end
  end
end
