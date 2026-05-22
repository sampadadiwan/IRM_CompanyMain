# frozen_string_literal: true

# Monitors the e-signing pipeline for stuck or expired documents.
#
# EsignMonitorAgent runs at the entity level. It finds documents in "requested"
# e-sign status that have been waiting longer than a configured threshold, fires
# resends via the existing resend_for_esign? path, and surfaces expired/voided
# documents for manual ops action.
#
# json_fields configuration:
#   send_reminders      — "true"/"false" (default true) — resend stuck requests
#   flag_expired        — "true"/"false" (default true) — surface expired/voided docs
#   reminder_after_days — integer (default 3) — days in "requested" before resend fires
#
# @see SupportAgentService
class EsignMonitorAgent < SupportAgentService
  DESCRIPTION = "Monitors the e-signing pipeline: resends stuck requests and flags expired or voided documents.".freeze

  LONG_DESCRIPTION = <<~DESC.freeze
    Monitors the e-signature pipeline and takes corrective action on stuck or expired documents.
    Targets the entity itself and scans all documents currently in "requested" e-sign status.

    Actions:
    • Send Reminders — if a document has been in "requested" state longer than reminder_after_days
      (default 3 days), it fires a resend via the existing resend_for_esign path.
      Controlled by send_reminders (true/false).
    • Flag Expired — surfaces documents in expired or voided e-sign state for manual ops action.
      Controlled by flag_expired (true/false).

    No LLM calls — entirely deterministic. Designed to run on a daily schedule. Results are saved
    as a SupportAgentReport listing each actioned document with its status and outcome.
  DESC

  STEP_LABELS = {
    initialize_agent:     "Initialize",
    find_pending_esigns:  "Find Pending",
    send_esign_reminders: "Send Reminders",
    flag_expired_esigns:  "Flag Expired",
    generate_progress_reports: "Save Report"
  }.freeze

  step :initialize_agent
  step :find_pending_esigns
  step :send_esign_reminders
  step :flag_expired_esigns
  step :generate_progress_reports

  def targets(entity_id)
    Entity.where(id: entity_id)
  end

  private

  def initialize_agent(ctx, target:, **)
    super
    ctx[:entity] = target
    ctx[:issues] = { esign_issues: [] }
    ctx[:pending_docs] = []
    @support_agent.enabled?
  end

  # Queries documents in "requested" state that have been waiting too long.
  # Always runs — read-only, no side effects.
  def find_pending_esigns(ctx, target:, **)
    reminder_after_days = @support_agent.json_fields["reminder_after_days"]&.to_i || 3

    ctx[:pending_docs] = Document
      .where(entity_id: target.id)
      .esign_status_requested
      .where("updated_at < ?", reminder_after_days.days.ago)
      .includes(:e_signatures)

    count = ctx[:pending_docs].size
    ctx[:issues][:esign_issues] << {
      type: :info,
      message: "#{count} document(s) pending e-sign for more than #{reminder_after_days} day(s)",
      severity: count > 0 ? :warning : :success
    }
    Rails.logger.info { "[EsignMonitorAgent] Found #{count} stuck e-sign request(s) for entity #{target.id}" }
    true
  end

  # Resends e-sign requests for eligible stuck documents.
  #
  # Configurable: send_reminders — "true"/"false"
  def send_esign_reminders(ctx, **)
    unless enabled?("send_reminders")
      ctx[:issues][:esign_issues] << {
        type: :info, message: "Reminders skipped via configuration", severity: :success
      }
      Rails.logger.debug { "[EsignMonitorAgent] send_reminders disabled, skipping." }
      return true
    end

    ctx[:pending_docs].each do |doc|
      if doc.resend_for_esign?
        # Delegate to the same service the controller uses — no user_id for scheduled runs
        result = ResendDocumentForEsign.call(document: doc, user_id: nil)
        if result.success?
          ctx[:issues][:esign_issues] << {
            type: :reminded, name: doc.name,
            message: "Resend queued", severity: :success
          }
          Rails.logger.info { "[EsignMonitorAgent] Resend queued for Document ID=#{doc.id} (#{doc.name})" }
        else
          ctx[:issues][:esign_issues] << {
            type: :resend_failed, name: doc.name,
            message: "Resend failed: #{result[:errors]}",
            severity: :warning
          }
        end
      else
        ctx[:issues][:esign_issues] << {
          type: :skipped, name: doc.name,
          message: "Not eligible for resend — check document approval and e-signature configuration",
          severity: :warning
        }
        Rails.logger.debug { "[EsignMonitorAgent] Document ID=#{doc.id} not eligible for resend" }
      end
    end
    true
  end

  # Surfaces documents with expired, cancelled, or voided e-sign status for manual action.
  #
  # Configurable: flag_expired — "true"/"false"
  def flag_expired_esigns(ctx, target:, **)
    unless enabled?("flag_expired")
      ctx[:issues][:esign_issues] << {
        type: :info, message: "Expired document check skipped via configuration", severity: :success
      }
      Rails.logger.debug { "[EsignMonitorAgent] flag_expired disabled, skipping." }
      return true
    end

    expired_docs = Document
      .where(entity_id: target.id)
      .where(esign_status: %w[expired cancelled voided])

    expired_docs.each do |doc|
      ctx[:issues][:esign_issues] << {
        type: :expired, name: doc.name,
        message: "E-sign #{doc.esign_status} — resend or re-initiate manually",
        severity: :blocking
      }
    end

    if expired_docs.empty?
      ctx[:issues][:esign_issues] << {
        type: :info, message: "No expired or voided e-sign documents", severity: :success
      }
    end

    Rails.logger.info { "[EsignMonitorAgent] Found #{expired_docs.size} expired/voided e-sign document(s)" }
    true
  end

  def generate_progress_reports(ctx, target:, support_agent:, **)
    super(ctx, model: target, support_agent: support_agent)
  end
end
