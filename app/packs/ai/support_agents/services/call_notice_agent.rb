# frozen_string_literal: true

# Validates capital call readiness before sending notices to investors.
#
# CallNoticeAgent is a deterministic, step-based support agent that performs
# a series of validation checks to ensure a capital call is ready to be sent.
# It provides real-time progress feedback via Turbo Streams.
#
# @example Run the agent for a capital call
#   CallNoticeAgent.call(support_agent_id: 1, target: capital_call, user_id: 10)
#
# @see SupportAgentService
# @see SupportAgentReport
class CallNoticeAgent < SupportAgentService
  DESCRIPTION = "Validates capital call readiness by checking KYC status, document generation, and approval workflow."

  LONG_DESCRIPTION = <<~DESC
    Validates that all prerequisites are in place before capital call notices are sent to investors.
    Runs against each CapitalCall in the entity and walks through a multi-step checklist,
    surfacing any blockers in real time via the step progress panel.

    Steps:
    • KYC Pre-Check — all investors on the call must have a completed KYC record.
    • Docs Generated — the call notice document must exist and be attached to the call.
    • Docs Approved — the notice document must be in an approved state.
    • Notification Configured — at least one notification template or delivery contact must be set up.
    • Ready to Send — final gate; marks the call ready when all checks pass.

    No LLM calls — entirely deterministic. Results are saved as a SupportAgentReport with
    per-step pass/fail detail. Blockers appear in the issue list for operations to resolve
    before notices are dispatched.
  DESC
  # @return [Hash{Symbol => String}] human-readable labels for each step
  STEP_LABELS = {
    initialize_agent: "Initialize",
    verify_investor_kyc: "KYC Pre-Check",
    check_documents_generated: "Docs Generated",
    check_documents_approved: "Docs Approved",
    check_notification_configured: "Notification",
    mark_ready_to_send: "Ready to Send",
    generate_progress_reports: "Save Report"
  }.freeze

  step :initialize_agent
  step :verify_investor_kyc
  step :check_documents_generated
  step :check_documents_approved
  step :check_notification_configured
  step :mark_ready_to_send
  step :generate_progress_reports

  # Returns the collection of capital calls to be processed for an entity.
  #
  # @param entity_id [Integer] the entity ID to scope targets
  # @return [ActiveRecord::Relation<CapitalCall>] capital calls for the entity
  def targets(entity_id)
    # Return the list of targets for this agent
    # This is a placeholder implementation
    CapitalCall.where(entity_id: entity_id)
  end

  # Setup health check — call notices cannot be generated without a Call
  # Template on the fund. Surfaced here because batch/scheduled runs skip the
  # step-level validation that would otherwise catch it.
  def self.config_issues(support_agent)
    issues = []
    support_agent.entity.funds.find_each do |fund|
      unless fund.documents.templates.where(owner_tag: "Call Template").exists?
        issues << "Fund '#{fund.name}' has no Call Template — upload one under Fund > Documents before sending call notices."
      end
    end
    issues
  end

  # Initializes the agent and sets up the issues tracking hash.
  #
  # @param ctx [Hash] the Trailblazer context
  # @return [Boolean] true on success
  def initialize_agent(ctx, **)
    super
    report = ctx[:support_agent_report]
    if report
      mark_step_running(report, :initialize_agent)
      ctx[:issues] = {
        kyc_issues: [],
        document_issues: [],
        notification_issues: []
      }

      mark_step_success(report, :initialize_agent, message: "Agent initialized successfully")
    end
    true
  end

  # Validates that all investors linked to the capital call have verified KYC.
  #
  # Checks each remittance's associated investor_kyc record to ensure it exists
  # and is marked as verified. Blocks the pipeline if any KYC issues are found.
  #
  # @param ctx [Hash] the Trailblazer context
  # @param target [CapitalCall] the capital call being validated
  # @return [Boolean] true if all KYC verified, false otherwise
  def verify_investor_kyc(ctx, target:, **)
    report = ctx[:support_agent_report]
    return true unless report

    mark_step_running(report, :verify_investor_kyc)

    capital_call = target
    remittances = capital_call.capital_remittances.includes(investor_kyc: :investor)

    failed_records = []

    remittances.each do |remittance|
      kyc = remittance.investor_kyc

      if kyc.blank?
        failed_records << {
          "name" => remittance.investor_name,
          "reason" => "No KYC record linked to this commitment"
        }
      elsif !kyc.verified
        failed_records << {
          "name" => "#{remittance.investor_name} (#{kyc.full_name})",
          "reason" => "KYC not verified"
        }
      end
    end

    if failed_records.any?
      mark_step_failed(
        report,
        :verify_investor_kyc,
        message: "#{failed_records.size} of #{remittances.size} investor(s) have KYC issues. Go to Investor KYCs, filter by fund, and mark each KYC as verified.",
        count: failed_records.size,
        failed_records: failed_records
      )

      ctx[:issues][:kyc_issues] = failed_records
      finalize_report(report, status: "blocked", failed_step: 2)
      false # Stop pipeline - can't generate docs without verified KYC
    else
      mark_step_success(
        report,
        :verify_investor_kyc,
        message: "All #{remittances.size} investor(s) have verified KYC",
        count: remittances.size
      )

      true
    end
  end

  # Placeholder - validates all investors have verified KYC
  # def verify_investor_kyc(ctx, target:, **)
  #   report = ctx[:support_agent_report]
  #   return true unless report

  #   mark_step_running(report, :verify_investor_kyc)

  #   capital_call = target
  #   remittances = capital_call.capital_remittances

  #   mark_step_success(
  #     report,
  #     :verify_investor_kyc,
  #     message: "All #{remittances.size} investor(s) have verified KYC",
  #     count: remittances.size
  #   )

  #   true
  # end

  # Verifies that call notice documents have been generated for all remittances.
  #
  # Checks that the fund has call templates configured and that each remittance
  # (excluding those with skip_doc_gen) has generated documents.
  #
  # @param ctx [Hash] the Trailblazer context
  # @param target [CapitalCall] the capital call being validated
  # @return [Boolean] true if all documents generated, false otherwise
  def check_documents_generated(ctx, target:, **)
    report = ctx[:support_agent_report]
    return true unless report

    mark_step_running(report, :check_documents_generated)

    capital_call = target
    fund = capital_call.fund

    # Get the call templates configured for this fund
    call_templates = fund.documents.templates.where(owner_tag: "Call Template")

    if call_templates.blank?
      mark_step_failed(
        report,
        :check_documents_generated,
        message: "No call templates found for Fund '#{fund.name}'. Go to Fund > Documents and upload a Call Template",
        count: 0,
        failed_records: []
      )
      ctx[:issues][:document_issues] = [{ "name" => "Fund Configuration", "reason" => "No call templates found for the fund." }]
      finalize_report(report, status: "blocked", failed_step: 3)
      return false # Stop pipeline - can't generate docs without templates
    end

    remittances = capital_call.capital_remittances.includes(:documents, capital_commitment: :investor_kyc)
    failed_records = []

    remittances.each do |remittance|
      # Skip remittances where skip_doc_gen is set on the commitment
      next if remittance.capital_commitment.skip_doc_gen?

      # Check if documents have been generated for this remittance
      generated_docs = remittance.documents.not_templates

      next if generated_docs.present?

      failed_records << {
        "name" => "#{remittance.investor_name} (#{remittance.folio_id})",
        "reason" => "No call notice documents generated"
      }
    end

    if failed_records.any?
      mark_step_failed(
        report,
        :check_documents_generated,
        message: "#{failed_records.size} of #{remittances.size} remittance(s) are missing call notice documents. Generate call notices to proceed. Click 'Generate Docs' on the Capital Call page to generate them.",
        count: failed_records.size,
        failed_records: failed_records
      )
      ctx[:issues][:document_issues] = failed_records
      finalize_report(report, status: "blocked", failed_step: 3)
      false # Stop pipeline - can't send notices without documents
    else
      mark_step_success(
        report,
        :check_documents_generated,
        message: "All #{remittances.size} remittance(s) have call notice documents generated",
        count: remittances.size
      )
      true
    end
  end

  # Verifies that all generated call notice documents have been approved.
  #
  # @param ctx [Hash] the Trailblazer context
  # @param target [CapitalCall] the capital call being validated
  # @return [Boolean] true if all documents approved, false otherwise
  def check_documents_approved(ctx, target:, **)
    report = ctx[:support_agent_report]
    return true unless report

    mark_step_running(report, :check_documents_approved)

    capital_call = target
    remittances = capital_call.capital_remittances.includes(:documents, capital_commitment: :investor_kyc)
    failed_records = []

    remittances.each do |remittance|
      # Skip remittances where skip_doc_gen is set on the commitment
      next if remittance.capital_commitment.skip_doc_gen?

      # Check if all generated documents are approved
      generated_docs = remittance.documents.not_templates
      unapproved_docs = generated_docs.not_approved

      next if unapproved_docs.blank?

      failed_records << {
        "name" => "#{remittance.investor_name} (#{remittance.folio_id})",
        "reason" => "#{unapproved_docs.size} document(s) pending approval"
      }
    end

    if failed_records.any?
      mark_step_failed(
        report,
        :check_documents_approved,
        message: "#{failed_records.size} remittance(s) have unapproved documents. Go to Documents and approve each call notice before sending.",
        count: failed_records.size,
        failed_records: failed_records
      )
      ctx[:issues][:document_issues]&.concat(failed_records)
      finalize_report(report, status: "blocked", failed_step: 4)
      false
    else
      approved_count = remittances.count { |r| !r.capital_commitment.skip_doc_gen? }
      mark_step_success(
        report,
        :check_documents_approved,
        message: "All #{approved_count} remittance(s) have approved documents",
        count: approved_count
      )
      true
    end
  end

  # Verifies that an email notification template is configured for the capital call.
  #
  # Checks for a custom notification with the key "notify_capital_remittance".
  #
  # @param ctx [Hash] the Trailblazer context
  # @return [Boolean] true if notification configured, false otherwise
  def check_notification_configured(ctx, target:, **)
    report = ctx[:support_agent_report]
    return true unless report

    mark_step_running(report, :check_notification_configured)

    capital_call = target

    # Check if custom notofication exusts and is enabled for sending call notices

    notification = capital_call.custom_notification("notify_capital_remittance")

    if notification.blank?
      mark_step_failed(
        report,
        :check_notification_configured,
        message: "No email notification template configured. Go to the 'Notification' tab and create a custom notification for 'notify_capital_remittance'.",
        count: 1,
        failed_records: [{
          "name" => "Email Template",
          "reason" => "No enabled custom notification found for notify_capital_remittance"
        }]
      )
      ctx[:issues][:notification_issues] = [{ "name" => "Email Template", "reason" => "Not configured" }]
      finalize_report(report, status: "blocked", failed_step: 5)
      return false
    end
    mark_step_success(
      report,
      :check_notification_configured,
      message: "Email notification template '#{notification.subject}' is configured and enabled",
      count: 1
    )
    true
  end

  # Confirms the capital call is ready to send after all validations pass.
  #
  # This is a validation confirmation step - all previous checks have passed,
  # so the call is ready for sending. No database changes are made here.
  #
  # @param ctx [Hash] the Trailblazer context
  # @return [Boolean] true on success
  def mark_ready_to_send(ctx, **)
    report = ctx[:support_agent_report]
    return true unless report

    mark_step_running(report, :mark_ready_to_send)
    mark_step_success(report, :mark_ready_to_send, message: "All validations passed. Call is ready to send.")
    true
  end

  # Finalizes the validation report and determines overall status.
  #
  # Sets the final status to "ready" if all steps passed, or "blocked" if any failed.
  #
  # @param ctx [Hash] the Trailblazer context
  # @return [Boolean] true on success
  def generate_progress_reports(ctx, **)
    report = ctx[:support_agent_report]
    return true unless report

    mark_step_running(report, :generate_progress_reports)

    # Determine final status based on any failures
    has_failures = report.steps.any? { |s| s["status"] == "failed" }
    final_status = has_failures ? "blocked" : "ready"
    failed_step_num = report.failed_step&.dig("step")

    mark_step_success(report, :generate_progress_reports, message: "Report Saved")
    finalize_report(report, status: final_status, failed_step: failed_step_num)
    true
  end
end
