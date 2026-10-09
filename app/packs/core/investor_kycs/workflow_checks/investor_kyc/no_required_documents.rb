# Skip check for "Upload required documents": the company requires no document for this KYC.
# Worked examples E2 — openspec/changes/investor-kyc-journey/design.md#worked-examples
module WorkflowChecks
  module InvestorKyc
    class NoRequiredDocuments < WorkflowChecks::Base
      include Support

      self.key = "investor_kyc.no_required_documents"
      self.label = "No documents are required"
      self.workflowable_type = "InvestorKyc"

      def call(kyc)
        return pass(message: "No documents are required") if required_document_names(kyc).empty?

        fail_with(message: "Documents are required")
      end
    end
  end
end
