# Files Digio's audit trail beside the signed copy once a document completes. A job rather than part of the
# webhook, because Digio may still answer "only on flow completion" when its last notification reaches us, and
# a slow download should not hold up that request. Worked examples H11, E36-E37, X13 —
# openspec/changes/embedded-esign-digio/design.md#worked-examples
class DigioAuditTrailJob < ApplicationJob
  queue_as :low

  # A signed document without its audit trail is not a state to leave unnoticed
  retry_on StandardError, wait: :polynomially_longer, attempts: 6 do |job, error|
    ErrorReport.notify(error, job:)
  end
  discard_on ActiveRecord::RecordNotFound

  def perform(document_id)
    Chewy.strategy(:sidekiq) do
      DigioEsignHelper.new.attach_audit_trail(Document.find(document_id))
    end
  end
end
