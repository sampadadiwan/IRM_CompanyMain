# 3. Upload required documents — a document exists for every required name (the entity's list for
# the KYC type plus the form's required document fields). n/a when nothing is required.
# Worked examples H4, E1 — openspec/changes/investor-kyc-journey/design.md#worked-examples
module WorkflowChecks
  module InvestorKyc
    class UploadDocuments < WorkflowChecks::Base
      include Support

      self.key = "investor_kyc.upload_documents"
      self.label = "Upload required documents"
      self.workflowable_type = "InvestorKyc"

      def call(kyc)
        missing = missing_document_names(kyc)
        return pass(message: "Required documents uploaded") if missing.empty?

        # Name at most three; a form can require a dozen (prod: 10 on one non-individual form)
        names = missing.size > 3 ? "#{missing.first(3).join(', ')} and #{missing.size - 3} more" : missing.join(", ")
        fail_with(message: "#{missing.size} required #{'document'.pluralize(missing.size)} missing: #{names}",
                  action_label: "Upload documents", action_path: kyc_path(kyc), action_target: DOCS_TAB)
      end
    end
  end
end
