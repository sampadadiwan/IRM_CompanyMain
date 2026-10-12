# Skip check: the fund has no Contract Note / Redemption Advice template, so the document steps are
# optional and shown as not applicable. open-ended-funds § Dealing-date documents
module WorkflowChecks
  module DealingDate
    class NoDocumentTemplates < WorkflowChecks::Base
      self.key = "dealing_date.no_document_templates"
      self.label = "Skip: no document templates"
      self.workflowable_type = "DealingDate"
      self.how = "Add a Contract Note Template or Redemption Advice Template to the fund to use these steps."
      self.why = "Without a template, investors get the email only — no document to generate or approve."
      self.effects = "Optional step skipped."

      def call(dealing_date)
        EvergreenDealingDocuments.templates?(dealing_date.fund) ? fail_with(message: "The fund has document templates") : pass(message: "Optional — the fund has no Contract Note or Redemption Advice template, so investors are emailed without a document")
      end
    end
  end
end
