# Drafts (or refines) an AI report draft in the background: asks the AI
# (ReportDraftGenerator), keeps only what the builder allows (ReportSpecPruner),
# writes the report (ReportSpecApplier, replacing the draft's columns), stores
# the AI's questions / assumptions / couldn't-do on the draft, then updates the
# draft page over the user's alert stream and sends "Your draft report is ready".
#
# Worked examples H2, H4, E5, E7, X1, X2, X3 — openspec/changes/report-builder-assistant/business-rules.md
class ReportDraftJob < ApplicationJob
  queue_as :default

  def perform(report_id, user_id, instruction = nil)
    report = Report.find_by(id: report_id)
    user   = User.find_by(id: user_id)
    # Discarded or cleaned up meanwhile
    return unless report && user

    ai = report.template.to_h.fetch("ai", {})
    # E5 — refinements start from the report as it is now, hand edits included
    current = report.grid_view_preferences.exists? ? ReportSpecApplier.spec_from(report) : nil

    result = ReportDraftGenerator.new(entity: report.entity, question: ai["question"], spec: current,
                                      instruction: instruction).call
    clean, problems = ReportSpecPruner.prune(result["spec"], entity: report.entity)
    cannot = (result["cannot"] + problems).uniq

    # X3 — nothing usable: only the couldn't-do list
    usable = clean["root_model"].present? && clean["columns"].any? { |c| c["key"] }
    if usable
      fund = Fund.where(entity_id: report.entity_id).find_by(id: ai["fund_id"]) if ai["fund_id"]
      ReportSpecApplier.apply!(report: report, spec: clean, fund: fund, validate: false, replace: true)
    end

    turns = Array(ai["turns"]) + (instruction ? [{ "instruction" => instruction, "at" => Time.current.iso8601 }] : [])
    store(report, ai.merge("status" => usable ? "ready" : "empty", "questions" => result["questions"],
                           "assumptions" => result["assumptions"], "cannot" => cannot, "turns" => turns,
                           "name" => result["name"] || ai["name"], "error" => nil))
    finish(report, user, "Your draft report is ready", "success")
  rescue ReportDraftGenerator::Failed => e
    # X1, X2 — the last good draft (if any) stays; the question stays
    store(report, ai.merge("status" => "failed", "error" => e.message))
    finish(report, user, "Couldn't draft <strong>#{ERB::Util.h(ai['question'].to_s.truncate(60))}</strong>", "danger")
  end

  private

  def store(report, ai)
    report.reload
    report.update!(template: report.template.to_h.merge("draft" => true, "ai" => ai))
  end

  # The draft page (if open) redraws; the alert links back to it (E7)
  def finish(report, user, message, level)
    # A fresh frame that loads the draft's state with the user's own session
    Turbo::StreamsChannel.broadcast_replace_to("user_alert_#{user.id}", target: "rb_draft_#{report.id}",
                                                                        partial: "report_builder/draft_frame",
                                                                        locals: { report: report })
    link = Rails.application.routes.url_helpers.report_builder_draft_path(report)
    UserAlert.new(user_id: user.id, entity_id: report.entity_id, level: level,
                  message: "#{message}. <a href='#{link}' class='btn btn-sm btn-#{level}'>Open draft</a>").broadcast
  end
end
