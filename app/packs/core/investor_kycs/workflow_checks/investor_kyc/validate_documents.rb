# 4. Validate documents — an acknowledge task the data can complete: when AI validation has run and
# every answer passed, it is done ("Validated by AI"); otherwise a person checks the documents and
# clicks Mark reviewed (AI could not read one, flagged a mismatch, or the company has no questions).
# Worked examples H5, E3, E4, E5 — openspec/changes/investor-kyc-journey/design.md#worked-examples
module WorkflowChecks
  module InvestorKyc
    class ValidateDocuments < WorkflowChecks::Base
      include Support

      self.key = "investor_kyc.validate_documents"
      self.label = "Validate documents (AI or Mark reviewed)"
      self.workflowable_type = "InvestorKyc"

      def call(kyc)
        counts = ai_answer_counts(kyc)

        # AI validated every answer: done with no click (if newer than any "documents changed")
        if counts && kyc.all_docs_valid
          at = ai_validated_at(kyc)
          return WorkflowChecks::Result.confirmed(message: "Validated by AI", passed_since: at, fresh_since: at)
        end

        if counts
          failed, total = counts
          return WorkflowChecks::Result.review(message: "AI could not validate #{failed} of #{total} answers — check them and mark reviewed",
                                               action_label: "Open validation", action_path: kyc_path(kyc), action_target: VALIDATION_TAB)
        end

        if kyc.doc_questions.exists?
          return WorkflowChecks::Result.review(message: "Documents not validated yet — run AI validation or check them and mark reviewed",
                                               action_label: "Validate Document Data", action_path: kyc_path(kyc),
                                               action_target: VALIDATE_AI_BTN)
        end

        WorkflowChecks::Result.review(message: "Check the documents and mark reviewed",
                                      action_label: "Open documents", action_path: kyc_path(kyc), action_target: DOCS_TAB)
      end
    end
  end
end
