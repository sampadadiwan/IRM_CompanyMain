# 4. Validate documents — an acknowledge task the data can complete: when the KYC's Document Checks have
# current results and nothing needs attention, it is done ("Validated by AI"); otherwise a person resolves
# the items (or checks the documents) and clicks Mark reviewed.
# Worked examples H7, E13, E21, E22, E23 — openspec/changes/document-checks/design.md#worked-examples
module WorkflowChecks
  module InvestorKyc
    class ValidateDocuments < WorkflowChecks::Base
      include Support

      self.key = "investor_kyc.validate_documents"
      self.label = "Validate documents (AI or Mark reviewed)"
      self.workflowable_type = "InvestorKyc"

      def call(kyc)
        assessment = DocChecks::Assessment.new(kyc)

        # Every item OK (or resolved): done with no click, if newer than any "documents changed"
        if assessment.settled?
          at = assessment.fresh_at
          return WorkflowChecks::Result.confirmed(message: "Validated by AI", passed_since: at, fresh_since: at)
        end

        # Checked, and something needs a person
        if assessment.checked?
          return WorkflowChecks::Result.review(message: attention_message(assessment.attention_count),
                                               action_label: "Open document checks", action_path: kyc_path(kyc),
                                               action_target: VALIDATION_TAB)
        end

        # Checks are set up for this KYC's documents, but they haven't been checked
        if assessment.checks?
          return WorkflowChecks::Result.review(message: "Documents not checked yet — check documents or mark reviewed",
                                               action_label: "Check documents", action_path: kyc_path(kyc),
                                               action_target: VALIDATE_AI_BTN)
        end

        WorkflowChecks::Result.review(message: "Check the documents and mark reviewed",
                                      action_label: "Open documents", action_path: kyc_path(kyc), action_target: DOCS_TAB)
      end

      private

      def attention_message(count)
        count == 1 ? "1 document item needs attention — resolve it or mark reviewed" : "#{count} document items need attention — resolve them or mark reviewed"
      end
    end
  end
end
