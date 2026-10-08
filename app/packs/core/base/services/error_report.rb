# frozen_string_literal: true

# The one way application code reports a handled error to the developer error inbox
# (ExceptionNotifier), so every such email carries the same "who / what / where" block that
# ErrorReportContext builds for the user-facing error emails.
#
# Before this, the ~25 hand-written ExceptionNotifier.notify_exception calls each passed whatever
# came to mind - usually one id, often nothing - so the email named the exception and little
# else: not which job, who triggered it, from where, or for which entity.
#
#   ErrorReport.notify(e, job: self, entity_id: entity.id)                       # inside a job
#   ErrorReport.notify(e, source: "JourneyEmailEdit", custom_notification_id: 7)  # anywhere else
#
# The block goes under data[:report]. Not as top-level keys: the email notifier turns each
# top-level data key into an instance variable (ExceptionNotifier::EmailNotifier#set_data_variables),
# so a key like "Triggered by" would raise inside the notifier and the email would never be sent.
class ErrorReport
  class << self
    # error  - the exception (or a StandardError built to describe a non-raised failure)
    # job    - the running ActiveJob, when called from inside one (adds job id, args, queue, actor)
    # source - names the entry point when not inside a job; defaults to the caller's file:line
    # extra  - anything that identifies the failing work (entity_id:, document_id:, ...);
    #          entity / entity_id are resolved to "Name (#id)"
    def notify(error, job: nil, source: nil, **extra)
      ExceptionNotifier.notify_exception(error, data: { report: context(job:, source:, extra:) })
    end

    # The rows that identify a document in an error report: what it is, whose it is and which
    # entity it belongs to - for failures about one document, e.g. an eSign send or webhook.
    # Nil-safe, since several callers report precisely because the document was not found.
    def document_context(doc)
      return {} if doc.nil?

      { document_id: doc.id, document: doc.name, owner: "#{doc.owner_type}##{doc.owner_id}", entity_id: doc.entity_id }
    end

    private

    def context(job:, source:, extra:)
      return ErrorReportContext.for_job(job, **extra) if job

      ErrorReportContext.for_service(source || reporting_line, **extra)
    end

    # "app/packs/.../journey_email_edit.rb:61" - the line that called notify, so even a caller that
    # names no source can be found. caller_locations(3, 1) skips this method, #context and #notify.
    def reporting_line
      loc = caller_locations(3, 1).first
      return nil unless loc

      # Relative inside the app ("app/packs/..."); a gem or eval'd frame keeps its full path.
      root = Rails.root.to_s.chomp("/").concat("/")
      "#{loc.path.start_with?(root) ? loc.path.delete_prefix(root) : loc.path}:#{loc.lineno}"
    rescue StandardError
      nil
    end
  end
end
