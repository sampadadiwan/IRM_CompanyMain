# Dealing-date journey check: Generate documents (optional — skipped when the fund has no template).
# open-ended-funds § Dealing-date documents
module WorkflowChecks
  module DealingDate
    class DocumentsGenerated < WorkflowChecks::Base
      self.key = "dealing_date.documents_generated"
      self.label = "Generate documents"
      self.workflowable_type = "DealingDate"
      self.how = "Click Generate documents on the dealing date once units are allotted and redemptions paid."
      self.why = "Contract notes and redemption advices are built from the fund's Word templates."
      self.effects = "Documents are saved unapproved on each folio; approvers are told they await approval."

      def call(dealing_date)
        progress = DealingProgress.new(dealing_date)
        progress.documents_generated? ? pass(message: "Documents generated") : fail_with(message: "Documents not generated yet")
      end
    end
  end
end
