# 7. Review KYC — an acknowledge task: someone checks the KYC's details and clicks Mark reviewed.
# Editing the details after the review moves the journey back here (InvestorKycUpdate's hook).
# Worked examples H7, E12 — openspec/changes/investor-kyc-journey/design.md#worked-examples
module WorkflowChecks
  module InvestorKyc
    class ReviewKyc < WorkflowChecks::Base
      include Support

      self.key = "investor_kyc.review_kyc"
      self.label = "Review KYC (acknowledge)"
      self.workflowable_type = "InvestorKyc"
      # What the step popup says (journey_step_info): what to do, why the step exists, and what
      # completing it changes — including whether anyone outside the team is emailed
      self.how = "Check the KYC details and documents, then click Mark reviewed."
      self.why = "A person looks over the whole KYC before it goes for sign-off."
      self.effects = "Records who reviewed it. No emails are sent."

      def call(kyc)
        WorkflowChecks::Result.review(message: "Check the KYC details and mark reviewed",
                                      action_label: "Open documents", action_path: kyc_path(kyc), action_target: DOCS_TAB)
      end
    end
  end
end
