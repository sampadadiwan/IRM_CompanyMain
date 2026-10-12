# Dealing-date journey check: Approve and send documents (optional — skipped without templates).
# open-ended-funds § Dealing-date documents
module WorkflowChecks
  module DealingDate
    class DocumentsSent < WorkflowChecks::Base
      self.key = "dealing_date.documents_sent"
      self.label = "Approve and send documents"
      self.workflowable_type = "DealingDate"
      self.how = "Click Approve & send on the dealing date."
      self.why = "Investors only receive documents the fund has approved."
      self.effects = "Each investor is emailed their contract note or redemption advice with the PDF attached."

      def call(dealing_date)
        DealingProgress.new(dealing_date).documents_sent? ? pass(message: "Documents approved and sent") : fail_with(message: "Documents waiting for approval")
      end
    end
  end
end
