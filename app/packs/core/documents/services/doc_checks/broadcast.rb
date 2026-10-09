# Tells open pages that a record's Document Checks changed (progress, finish, a resolution). It broadcasts
# a reload_frame stream action (app/javascript/custom/turbo_stream_actions.js) carrying only the frame id
# and its src, so each browser re-fetches the tab as its own user — the tab's buttons depend on the
# viewer's rights, so rendered HTML can't be broadcast to everyone. The frame reloads in place (morphed:
# the tab's frame is refresh="morph"), so the page doesn't go blank and jump on every update, as it did
# when the frame was replaced with an empty one. Never raises into the caller.
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
      reload([record, :doc_checks], panel_frame_id(record), src)
    end

    def trial(run)
      reload([run, :trial], trial_frame_id(run), routes.doc_check_run_path(run))
    end

    def panel_frame_id(record)
      "doc_checks_#{Registry.record_type_of(record).underscore}_#{record.id}"
    end

    def trial_frame_id(run)
      "doc_check_trial_#{run.id}"
    end

    # No content: the browser reloads the frame from src itself
    def reload(streamables, target, src)
      Turbo::StreamsChannel.broadcast_action_to(*streamables, action: :reload_frame, target:, attributes: { src: })
    rescue StandardError => e
      Rails.logger.error("DocChecks::Broadcast failed for #{target}: #{e.class} #{e.message}")
    end

    def routes
      Rails.application.routes.url_helpers
    end
  end
end
