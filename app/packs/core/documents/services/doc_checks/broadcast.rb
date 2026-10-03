# Tells open pages that a record's Document Checks changed (progress, finish, a resolution). Like the
# journey panel (Workflowable#broadcast_journey_change) it broadcasts an empty frame with a src, so each
# browser re-fetches the tab as its own user — the tab's buttons depend on the viewer's rights, so
# rendered HTML can't be broadcast to everyone. Never raises into the caller.
# See openspec/changes/document-checks/design.md (card ⑧ Screens). Worked example H12.
module DocChecks
  module Broadcast
    module_function

    # A run moved on: the record's tab, or the trial frame on the setup page
    def run(run)
      run.trial ? trial(run) : record(run.record)
    end

    # The record's Document checks tab
    def record(record)
      src = routes.panel_doc_check_runs_path(record_type: Registry.record_type_of(record), record_id: record.id)
      replace([record, :doc_checks], panel_frame_id(record), src)
    end

    def trial(run)
      replace([run, :trial], trial_frame_id(run), routes.doc_check_run_path(run))
    end

    def panel_frame_id(record)
      "doc_checks_#{Registry.record_type_of(record).underscore}_#{record.id}"
    end

    def trial_frame_id(run)
      "doc_check_trial_#{run.id}"
    end

    def replace(streamables, target, src)
      frame = %(<turbo-frame id="#{target}" src="#{src}"></turbo-frame>)
      Turbo::StreamsChannel.broadcast_replace_to(*streamables, target:, html: frame)
    rescue StandardError => e
      Rails.logger.error("DocChecks::Broadcast failed for #{target}: #{e.class} #{e.message}")
    end

    def routes
      Rails.application.routes.url_helpers
    end
  end
end
