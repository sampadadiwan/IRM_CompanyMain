# frozen_string_literal: true

# Computes dashboard aggregations from portfolio company agent reports.
#
# Takes a collection of SupportAgentReport records (already loaded by
# AgentReportsQuery#portfolio_reports) and produces stat card numbers,
# issue-by-type breakdowns, and overdue company lists for the dashboard UI.
#
# @see SupportAgentReport
# @see PortfolioCompanyAgent
class PortfolioDashboardPresenter
  attr_reader :reports, :support_agent

  # @param reports [Array<SupportAgentReport>] portfolio reports collection
  # @param support_agent [SupportAgent] the portfolio company agent record
  def initialize(reports, support_agent)
    @reports = reports.select { |r| r.json_fields.present? }
    @support_agent = support_agent
  end

  # --- Stat Cards (Row 1: Overview) ---

  # Changed: count only companies the agent has run for (i.e. that have a
  # SupportAgentReport), not all portfolio companies in the entity. Previously
  # the stat cards showed inflated totals that included companies the agent
  # had never validated, making "Not Yet Validated" misleadingly high.
  #
  # @return [Integer] portfolio companies the agent has run for
  def total_companies
    @total_companies ||= reports.size
  end

  # Companies the agent has validated (final_status is "ready" or "blocked").
  # Displayed as "Validated" on the dashboard stat card.
  #
  # @return [Integer] companies that have been checked by the agent
  def submissions_received
    @submissions_received ||= reports.count { |r| final_status(r).in?(%w[ready blocked]) }
  end

  # Companies with zero blocking issues across KPIs, valuations, and documents.
  # Displayed as "Up to Date" on the dashboard stat card.
  #
  # @return [Integer] companies with no blocking issues
  def fully_complete
    @fully_complete ||= reports.count { |r| final_status(r) == "ready" }
  end

  # Companies the agent has NOT yet validated — no report exists.
  # Displayed as "Not Yet Validated" on the dashboard stat card.
  # Run the agent again to process these companies.
  #
  # @return [Integer] companies with no report (total - validated)
  def pending_submissions
    @pending_submissions ||= total_companies - submissions_received
  end

  # @return [Integer] total blocking issues across all reports
  def total_issues
    @total_issues ||= reports.sum { |r| blocking_count(r) }
  end

  # --- Stat Cards (Row 2: Issue Breakdown by Category) ---

  # Companies that have not submitted KPI reports for the expected period.
  # Displayed as "KPI Overdue" on the dashboard stat card.
  # These are the companies that would receive reminders via Send Reminders.
  #
  # @return [Integer] companies with blocking KPI issues
  def kpi_overdue_count
    @kpi_overdue_count ||= reports.count do |r|
      Array(r.json_fields.with_indifferent_access[:kpi_issues])
        .any? { |i| i[:severity].to_s == "blocking" }
    end
  end

  # Companies missing a recent valuation for the reporting period.
  # Displayed as "Valuation Overdue" on the dashboard stat card.
  #
  # @return [Integer] companies with blocking valuation issues
  def valuation_overdue_count
    @valuation_overdue_count ||= reports.count do |r|
      Array(r.json_fields.with_indifferent_access[:valuation_issues])
        .any? { |i| i[:severity].to_s == "blocking" }
    end
  end

  # Companies missing required compliance documents (Financial Statement, Board Minutes, etc.).
  # Displayed as "Documents Overdue" on the dashboard stat card.
  # Checks for both severity: "blocking" and type: "missing" since document issues use both.
  #
  # @return [Integer] companies with blocking or missing document issues
  def documents_overdue_count
    @documents_overdue_count ||= reports.count do |r|
      Array(r.json_fields.with_indifferent_access[:document_issues])
        .any? { |i| i[:severity].to_s == "blocking" || i[:type].to_s == "missing" }
    end
  end

  # --- Dynamic Document Types ---

  # Returns the list of File-type custom field labels configured on the entity's
  # KPI report form. These become the dynamic document columns in the table.
  #
  # @return [Array<String>] document type labels (e.g., ["Financial Statement", "Board Minutes"])
  def document_types
    @document_types ||= begin
      # Resolve via KpiReport.name — mirrors WithCustomField#setup_form_type
      # which uses self.class.name to find the entity's form type.
      form_type = support_agent.entity.form_types.where(name: KpiReport.name).last
      # Use label if present, fall back to humanized name for fields with blank labels.
      labels = form_type&.form_custom_fields&.where(field_type: "File")
                        &.map { |f| f.label.presence || f.name.humanize } || []

      agent_docs = support_agent.json_fields["required_docs"].to_s.split(",").map(&:strip).compact_blank
      labels += agent_docs

      if labels.empty?
        labels = reports.flat_map do |r|
          Array(r.json_fields.with_indifferent_access[:document_issues])
            .select { |i| i[:type].to_s == "missing" }
            .filter_map { |i| i[:message].presence }
        end.uniq
      end

      labels.uniq
    end
  end

  # --- Missing by Type (for bar chart) ---

  # @return [Hash{String => Integer}] issue counts per compliance category
  def issues_by_type
    @issues_by_type ||= begin
      result = { "KPI" => 0, "Valuation" => 0 }
      doc_names = Set.new

      reports.each do |r|
        data = r.json_fields.with_indifferent_access
        kpi_issues = Array(data[:kpi_issues])
        val_issues = Array(data[:valuation_issues])
        doc_issues = Array(data[:document_issues])

        result["KPI"] += 1 if kpi_issues.any? { |i| i[:severity].to_s == "blocking" }
        result["Valuation"] += 1 if val_issues.any? { |i| i[:severity].to_s == "blocking" }

        doc_issues.select { |i| i[:severity].to_s == "blocking" || i[:type].to_s == "missing" }.each do |i|
          name = i[:message].presence || "Documents"
          doc_names << name
          result[name] ||= 0
          result[name] += 1
        end
      end

      if doc_names.empty?
        doc_blocking = reports.count do |r|
          Array(r.json_fields.with_indifferent_access[:document_issues])
            .any? { |i| i[:severity].to_s == "blocking" || i[:type].to_s == "missing" }
        end
        result["Documents"] = doc_blocking if doc_blocking.positive?
      end

      result.reject { |_, v| v.zero? }
    end
  end

  # --- Overdue Companies (for Send Reminders + sidebar list) ---

  # Companies with any blocking issues (KPIs, documents, or valuations).
  # Matches PortfolioCompanyAgent's send_kpi_reminder step which now sends
  # consolidated reminders for all missing categories, not just KPIs.
  # Used by: Send Reminders button count, confirm dialog, and overdue sidebar list.
  #
  # @return [Array<Hash>] companies with any blocking issues, sorted by issues_count descending.
  #   Each hash includes :last_reminder_sent_at (Date or nil) for per-company
  #   reminder dates in the Send Reminders modal.
  def overdue_companies
    @overdue_companies ||= reports
                           .select { |r| blocking_count(r).positive? }
                           .map do |r|
      data = r.json_fields.with_indifferent_access
      run_at = begin
        Time.zone.parse(data[:run_at])
      rescue StandardError
        nil
      end
      last_reminder = begin
        date_str = data[:last_kpi_reminder_sent_at]
        Date.parse(date_str) if date_str.present?
      rescue StandardError
        nil
      end
      {
        name: r.owner&.name || r.owner_name || "Unknown",
        owner_id: r.owner_id,
        issues_count: blocking_count(r),
        days_since_run: run_at ? ((Time.current - run_at) / 1.day).floor : nil,
        last_reminder_sent_at: last_reminder
      }
    end
                           .sort_by { |c| -c[:issues_count] }
  end

  # @return [Date, nil] the most recent date any reminder was sent
  def last_reminder_sent_at
    @last_reminder_sent_at ||= begin
      dates = reports.filter_map do |r|
        date_str = r.json_fields&.dig("last_kpi_reminder_sent_at")
        Date.parse(date_str) if date_str.present?
      rescue Date::Error
        nil
      end
      dates.max
    end
  end

  # --- Per-Report Helpers (used by table rows) ---

  # @param report [SupportAgentReport]
  # @return [String] display status label
  def report_status(report)
    status = final_status(report)
    case status
    when "ready" then "Up to Date"
    when "blocked" then "Has Issues"
    else "Not Validated"
    end
  end

  # @param report [SupportAgentReport]
  # @return [String] Bootstrap color class
  def report_status_color(report)
    case report_status(report)
    when "Up to Date" then "success"
    when "Has Issues" then "warning"
    else "secondary"
    end
  end

  # Whether the KPI report was submitted for this company. Used by the table
  # to decide if document columns should show ✓/✗ or "--" (not checked).
  # When KPI is not submitted, check_document_presence is skipped entirely,
  # so showing ✓ for documents would be misleading.
  #
  # @param report [SupportAgentReport]
  # @return [Boolean] true if KPI report exists (no blocking KPI issues)
  def kpi_submitted?(report)
    category_ok?(report, :kpi)
  end

  # @param report [SupportAgentReport]
  # @param category [Symbol] :kpi, :valuation, or :document
  # @return [Boolean] true if category has no blocking issues
  def category_ok?(report, category)
    data = report.json_fields.with_indifferent_access
    issues = Array(data[:"#{category}_issues"])
    issues.none? { |i| i[:severity].to_s == "blocking" || i[:type].to_s == "missing" }
  end

  # Checks if a specific named document is present (not missing) for a report.
  #
  # @param report [SupportAgentReport]
  # @param doc_name [String] the document type label (e.g., "Financial Statement")
  # @return [Boolean] true if the document is NOT missing
  def document_ok?(report, doc_name)
    data = report.json_fields.with_indifferent_access
    doc_issues = Array(data[:document_issues])
    doc_issues.none? do |i|
      (i[:severity].to_s == "blocking" || i[:type].to_s == "missing") &&
        i[:message].to_s == doc_name
    end
  end

  # @param report [SupportAgentReport]
  # @return [Integer] total blocking issues in this report
  def blocking_count(report)
    data = report.json_fields.with_indifferent_access
    kpi_blocking = Array(data[:kpi_issues]).count { |i| i[:severity].to_s == "blocking" }
    doc_blocking = Array(data[:document_issues]).count { |i| i[:severity].to_s == "blocking" || i[:type].to_s == "missing" }
    val_blocking = Array(data[:valuation_issues]).count { |i| i[:severity].to_s == "blocking" }
    kpi_blocking + doc_blocking + val_blocking
  end

  private

  # @param report [SupportAgentReport]
  # @return [String] normalised final status
  def final_status(report)
    (report.json_fields.with_indifferent_access[:final_status].presence || report.status.to_s).downcase
  end

  # @return [Integer] minimum possible issue categories
  def total_possible_issues
    2 + [document_types.size, 1].max
  end
end
