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

  # --- Stat Cards ---

  # @return [Integer] total portfolio companies in the entity
  def total_companies
    @total_companies ||= Investor.where(
      entity_id: support_agent.entity_id,
      category: "Portfolio Company"
    ).count
  end

  # @return [Integer] companies that have at least one report
  def submissions_received
    @submissions_received ||= reports.count { |r| final_status(r).in?(%w[ready blocked]) }
  end

  # @return [Integer] companies with no blocking issues
  def fully_complete
    @fully_complete ||= reports.count { |r| final_status(r) == "ready" }
  end

  # @return [Integer] companies with no report or blocked status
  def pending_submissions
    @pending_submissions ||= total_companies - submissions_received
  end

  # @return [Integer] total blocking issues across all reports
  def total_issues
    @total_issues ||= reports.sum { |r| blocking_count(r) }
  end

  # --- Dynamic Document Types ---

  # Returns the list of File-type custom field labels configured on the entity's
  # KPI report form. These become the dynamic document columns in the table.
  #
  # @return [Array<String>] document type labels (e.g., ["Financial Statement", "Board Minutes"])
  def document_types
    @document_types ||= begin
      form_type = FormType.find_by(entity_id: support_agent.entity_id, name: "PortfolioKpiReport")
      labels = form_type&.form_custom_fields&.where(field_type: "File")&.map(&:label) || []

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

  # --- Overdue / Pending Companies ---

  # @return [Array<Hash>] overdue companies sorted by issues_count descending
  def overdue_companies
    @overdue_companies ||= reports
                           .select { |r| final_status(r) == "blocked" }
                           .map do |r|
                             data = r.json_fields.with_indifferent_access
                             run_at = begin
                               Time.zone.parse(data[:run_at])
                             rescue StandardError
                               nil
                             end
                             {
                               name: r.owner&.name || r.owner_name || "Unknown",
                               owner_id: r.owner_id,
                               issues_count: blocking_count(r),
                               days_since_run: run_at ? ((Time.current - run_at) / 1.day).floor : nil
                             }
                           end
                           .sort_by { |c| -c[:issues_count] }
  end

  # --- Per-Report Helpers (used by table rows) ---

  # @param report [SupportAgentReport]
  # @return [String] display status label
  def report_status(report)
    status = final_status(report)
    case status
    when "ready" then "Complete"
    when "blocked" then blocking_count(report) == total_possible_issues ? "Pending" : "Incomplete"
    else "Pending"
    end
  end

  # @param report [SupportAgentReport]
  # @return [String] Bootstrap color class
  def report_status_color(report)
    case report_status(report)
    when "Complete" then "success"
    when "Incomplete" then "warning"
    when "Pending" then "danger"
    else "secondary"
    end
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
