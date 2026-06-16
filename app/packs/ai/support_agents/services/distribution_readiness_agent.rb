# frozen_string_literal: true

# Validates capital distribution readiness before payments are released to investors.
#
# DistributionReadinessAgent is a deterministic, step-based support agent that mirrors
# CallNoticeAgent but for distributions. Each step is individually skippable via
# support_agent.json_fields flags.
#
# json_fields configuration:
#   check_kyc           — "true"/"false" (default true) — verify investor KYC
#   check_net_payable   — "true"/"false" (default true) — verify net payable computed
#   check_docs_generated — "true"/"false" (default true) — verify notices generated
#   check_docs_approved — "true"/"false" (default true) — verify notices approved
#   check_bank_details  — "true"/"false" (default true) — verify bank details on file
#
# @see SupportAgentService
# @see CallNoticeAgent
class DistributionReadinessAgent < SupportAgentService
  DESCRIPTION = "Validates distribution readiness: KYC, net payable, notices generated/approved, bank details on file."

  LONG_DESCRIPTION = <<~DESC
    Validates that all prerequisites are in place before a capital distribution payment is released.
    Runs against each CapitalDistribution in the entity and surfaces any blockers before funds are wired.

    Steps:
    • KYC Check — investor must have a completed KYC record (toggle: check_kyc).
    • Net Payable — distribution net payable amount must be computed (check_net_payable).
    • Notices Generated — distribution notice documents must be generated (check_docs_generated).
    • Docs Approved — notice documents must be in an approved state (check_docs_approved).
    • Bank Details — investor must have valid bank account details on file (check_bank_details).
    • Ready to Pay — final gate; marks the distribution ready when all checks pass.

    All checks are independently toggleable via json_fields (true/false). Results are saved as a
    SupportAgentReport with per-step pass/fail detail for operations to review and action.
  DESC

  STEP_LABELS = {
    initialize_agent: "Initialize",
    verify_investor_kyc: "KYC Check",
    check_net_payable_computed: "Net Payable",
    check_distribution_notices_generated: "Notices Generated",
    check_documents_approved: "Docs Approved",
    verify_bank_details: "Bank Details",
    mark_ready_to_pay: "Ready to Pay",
    generate_progress_reports: "Save Report"
  }.freeze

  step :initialize_agent
  step :verify_investor_kyc
  step :check_net_payable_computed
  step :check_distribution_notices_generated
  step :check_documents_approved
  step :verify_bank_details
  step :mark_ready_to_pay
  step :generate_progress_reports

  def targets(entity_id)
    CapitalDistribution.joins(:fund).where(funds: { entity_id: entity_id })
  end

  private

  def initialize_agent(ctx, **)
    super
    report = ctx[:support_agent_report]
    if report
      mark_step_running(report, :initialize_agent)
      ctx[:issues] = {
        kyc_issues: [],
        payment_issues: [],
        document_issues: [],
        bank_issues: []
      }
      mark_step_success(report, :initialize_agent, message: "Agent initialized")
    end
    true
  end

  # Verifies all investors linked to the distribution have verified KYC.
  #
  # Configurable: check_kyc — "true"/"false"
  def verify_investor_kyc(ctx, target:, **)
    report = ctx[:support_agent_report]
    return true unless report

    unless enabled?("check_kyc")
      mark_step_skipped(report, :verify_investor_kyc, message: "Skipped via configuration")
      return true
    end

    mark_step_running(report, :verify_investor_kyc)
    payments = distribution_payments(target)
    failed_records = []

    payments.each do |payment|
      kyc = payment.investor_kyc
      if kyc.blank?
        failed_records << { "name" => payment.investor_name, "reason" => "No KYC linked to commitment" }
      elsif !kyc.verified
        failed_records << { "name" => payment.investor_name, "reason" => "KYC not verified" }
      end
    end

    if failed_records.any?
      mark_step_failed(report, :verify_investor_kyc,
                       message: "#{failed_records.size} of #{payments.size} investor(s) have KYC issues.",
                       count: failed_records.size, failed_records: failed_records)
      ctx[:issues][:kyc_issues] = failed_records
      finalize_report(report, status: "blocked", failed_step: 2)
      false
    else
      mark_step_success(report, :verify_investor_kyc,
                        message: "All #{payments.size} investor(s) have verified KYC",
                        count: payments.size)
      true
    end
  end

  # Verifies every payment has a non-zero net_payable computed.
  #
  # Configurable: check_net_payable — "true"/"false"
  def check_net_payable_computed(ctx, target:, **)
    report = ctx[:support_agent_report]
    return true unless report

    unless enabled?("check_net_payable")
      mark_step_skipped(report, :check_net_payable_computed, message: "Skipped via configuration")
      return true
    end

    mark_step_running(report, :check_net_payable_computed)
    payments = distribution_payments(target)
    failed_records = payments.select do |p|
      p.net_payable_cents.nil? || p.net_payable_cents.zero?
    end.map do |p|
      { "name" => p.investor_name, "reason" => "Net payable not computed — re-run fee calculation" }
    end

    if failed_records.any?
      mark_step_failed(report, :check_net_payable_computed,
                       message: "#{failed_records.size} payment(s) missing net payable. Re-run fee calculation on the distribution.",
                       count: failed_records.size, failed_records: failed_records)
      ctx[:issues][:payment_issues] = failed_records
      finalize_report(report, status: "blocked", failed_step: 3)
      false
    else
      mark_step_success(report, :check_net_payable_computed,
                        message: "All #{payments.size} payment(s) have computed net payable",
                        count: payments.size)
      true
    end
  end

  # Verifies distribution notice documents have been generated for all payments.
  #
  # Configurable: check_docs_generated — "true"/"false"
  def check_distribution_notices_generated(ctx, target:, **)
    report = ctx[:support_agent_report]
    return true unless report

    unless enabled?("check_docs_generated")
      mark_step_skipped(report, :check_distribution_notices_generated, message: "Skipped via configuration")
      return true
    end

    mark_step_running(report, :check_distribution_notices_generated)

    distribution_templates = target.fund.documents.templates.where(owner_tag: "Distribution Template")
    if distribution_templates.blank?
      mark_step_failed(report, :check_distribution_notices_generated,
                       message: "No Distribution Template found for Fund '#{target.fund.name}'. Upload a Distribution Template under Fund > Documents.",
                       count: 0, failed_records: [])
      finalize_report(report, status: "blocked", failed_step: 4)
      return false
    end

    payments = distribution_payments(target)
    failed_records = payments.select do |p|
      p.documents.not_templates.empty?
    end.map do |p|
      { "name" => "#{p.investor_name} (#{p.folio_id})", "reason" => "No distribution notice generated" }
    end

    if failed_records.any?
      mark_step_failed(report, :check_distribution_notices_generated,
                       message: "#{failed_records.size} of #{payments.size} payment(s) missing distribution notices. Click 'Generate Docs' on the Distribution page.",
                       count: failed_records.size, failed_records: failed_records)
      ctx[:issues][:document_issues] = failed_records
      finalize_report(report, status: "blocked", failed_step: 4)
      false
    else
      mark_step_success(report, :check_distribution_notices_generated,
                        message: "All #{payments.size} payment(s) have generated distribution notices",
                        count: payments.size)
      true
    end
  end

  # Verifies all generated distribution notices are approved.
  #
  # Configurable: check_docs_approved — "true"/"false"
  def check_documents_approved(ctx, target:, **)
    report = ctx[:support_agent_report]
    return true unless report

    unless enabled?("check_docs_approved")
      mark_step_skipped(report, :check_documents_approved, message: "Skipped via configuration")
      return true
    end

    mark_step_running(report, :check_documents_approved)
    payments = distribution_payments(target)
    failed_records = []

    payments.each do |payment|
      unapproved = payment.documents.not_templates.not_approved
      next if unapproved.blank?

      failed_records << {
        "name" => "#{payment.investor_name} (#{payment.folio_id})",
        "reason" => "#{unapproved.size} document(s) pending approval"
      }
    end

    if failed_records.any?
      mark_step_failed(report, :check_documents_approved,
                       message: "#{failed_records.size} payment(s) have unapproved distribution notices. Approve each document before releasing payment.",
                       count: failed_records.size, failed_records: failed_records)
      ctx[:issues][:document_issues].concat(failed_records)
      finalize_report(report, status: "blocked", failed_step: 5)
      false
    else
      mark_step_success(report, :check_documents_approved,
                        message: "All distribution notices approved",
                        count: payments.size)
      true
    end
  end

  # Verifies bank account details are on file for every investor via their KYC record.
  #
  # Configurable: check_bank_details — "true"/"false"
  def verify_bank_details(ctx, target:, **)
    report = ctx[:support_agent_report]
    return true unless report

    unless enabled?("check_bank_details")
      mark_step_skipped(report, :verify_bank_details, message: "Skipped via configuration")
      return true
    end

    mark_step_running(report, :verify_bank_details)
    payments = distribution_payments(target)
    failed_records = payments.filter_map do |payment|
      kyc = payment.investor_kyc
      next if kyc&.bank_account_number.present?

      { "name" => payment.investor_name, "reason" => "Bank account number missing on KYC record" }
    end

    if failed_records.any?
      mark_step_failed(report, :verify_bank_details,
                       message: "#{failed_records.size} investor(s) missing bank details. Update KYC records before releasing payment.",
                       count: failed_records.size, failed_records: failed_records)
      ctx[:issues][:bank_issues] = failed_records
      finalize_report(report, status: "blocked", failed_step: 6)
      false
    else
      mark_step_success(report, :verify_bank_details,
                        message: "Bank details on file for all #{payments.size} investor(s)",
                        count: payments.size)
      true
    end
  end

  # Confirmation step — all validations passed, distribution is clear for payment.
  def mark_ready_to_pay(ctx, **)
    report = ctx[:support_agent_report]
    return true unless report

    mark_step_running(report, :mark_ready_to_pay)
    mark_step_success(report, :mark_ready_to_pay, message: "All validations passed. Distribution is ready to pay.")
    true
  end

  def generate_progress_reports(ctx, **)
    report = ctx[:support_agent_report]
    return true unless report

    mark_step_running(report, :generate_progress_reports)
    has_failures = report.steps.any? { |s| s["status"] == "failed" }
    final_status = has_failures ? "blocked" : "ready"
    failed_step_num = report.failed_step&.dig("step")
    mark_step_success(report, :generate_progress_reports, message: "Report saved")
    finalize_report(report, status: final_status, failed_step: failed_step_num)
    true
  end

  def distribution_payments(distribution)
    @distribution_payments ||= distribution.capital_distribution_payments
                                           .includes(:documents, capital_commitment: :investor_kyc)
  end
end
