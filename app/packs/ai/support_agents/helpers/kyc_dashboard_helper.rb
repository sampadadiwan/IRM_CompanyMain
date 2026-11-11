# frozen_string_literal: true

# View helper for the KYC Agent Dashboard tab. Transforms raw query data
# (stats, reports, document ratios) into display-ready strings, CSS classes,
# and visibility flags used by the dashboard ERB partials.
module KycDashboardHelper
  # Classifies a KYC into a display status based on its expiry date and
  # report's json_fields. Expired takes priority — if expiry_date < today,
  # the KYC is "Expired" regardless of report status. Mirrors the SQL CASE
  # WHEN logic in AgentReportsQuery#kyc_stat_counts so the table badge
  # matches the stat card counts.
  #
  # @param kyc [InvestorKyc]
  # @param report [SupportAgentReport, nil]
  # @return [String] "Pending", "Successful", "Failed", "Partially Failed", or "Expired"
  def kyc_agent_status(kyc, report)
    # Expired takes priority over all other statuses
    return "Expired" if kyc.expiry_date.present? && kyc.expiry_date < Time.zone.today

    return "Pending" if report.blank?

    fields = report_json_fields(report)
    final  = fields["final_status"]

    return "Successful" if final == "ready"

    return "Failed" if final == "error"

    if final == "blocked"
      has_success = (fields["field_issues"].to_a + fields["document_issues"].to_a).any? do |issue|
        issue["severity"] == "success" || issue["type"] == "info"
      end
      return has_success ? "Partially Failed" : "Failed"
    end

    "Pending"
  end

  # Returns a human-readable summary of matched vs total items from a report.
  #
  # @param report [SupportAgentReport, nil]
  # @return [String] "8 of 12 items matched" or "—"
  def kyc_result_summary(report)
    return "—" if report.blank?

    fields = report_json_fields(report)
    issues = fields["field_issues"].to_a + fields["document_issues"].to_a
    return "—" if issues.empty?

    passed = issues.count { |i| i["severity"] == "success" || i["type"] == "info" }
    "#{passed} of #{issues.size} items passed"
  end

  # Formats the document upload ratio for the table Docs column.
  # Shows uploaded / required count from the precomputed doc_ratios hash.
  #
  # @param kyc [InvestorKyc]
  # @param doc_ratios [Hash<Integer, Hash>] precomputed by AgentReportsQuery#kyc_doc_ratios
  # @return [String] "3 / 5" or "—"
  def kyc_doc_ratio(kyc, doc_ratios)
    ratio = doc_ratios[kyc.id]
    return "—" if ratio.blank? || ratio[:required].to_i.zero?

    "#{ratio[:uploaded]} / #{ratio[:required]}"
  end

  # Returns a Bootstrap text color class based on document upload completeness.
  # Green = all uploaded, orange = some missing, red = none uploaded.
  #
  # @param uploaded [Integer]
  # @param required [Integer]
  # @return [String] "text-success", "text-warning", or "text-danger"
  def kyc_doc_ratio_color(uploaded, required)
    return "" if required.to_i.zero?

    if uploaded >= required
      "text-success"
    elsif uploaded.positive?
      "text-warning"
    else
      "text-danger"
    end
  end

  # Builds an HTML tooltip with uploaded and required doc names side by side.
  # Horizontal layout: "Uploaded: ... | Required: ..." with missing highlighted.
  # safe_join handles escaping — no raw html_safe needed.
  #
  # @param ratio [Hash, nil] from doc_ratios — { required_names:, uploaded_names:, missing_names: }
  # @return [ActiveSupport::SafeBuffer] HTML-safe tooltip content or ""
  def kyc_doc_tooltip_html(ratio)
    return "" if ratio.blank? || ratio[:required].to_i.zero?

    left = content_tag(:strong, "Uploaded: ") + h(ratio[:uploaded_names].present? ? ratio[:uploaded_names].join(", ") : "None")
    right = content_tag(:strong, "Required: ") + h(ratio[:required_names].join(", "))
    safe_join([left, right], " | ")
  end

  # Parses a report's json_fields into a flat list of item hashes for the
  # run-output detail panel. Each item is tagged with source: :field or
  # source: :document so the "Documents" tab can filter to doc-only items,
  # and step: from the issue's pipeline step tag for grouped display.
  #
  # @param report [SupportAgentReport]
  # @return [Array<Hash>] [{ item:, detail:, status:, source:, step: }]
  def kyc_run_output_items(report)
    return [] if report.blank?

    fields = report_json_fields(report)
    items = fields["field_issues"].to_a.map { |issue| field_issue_to_row(issue).merge(source: :field, step: issue["step"].to_s.presence || infer_field_step(issue)) }
    items + fields["document_issues"].to_a.map { |issue| doc_issue_to_row(issue).merge(source: :document, step: issue["step"].to_s.presence || infer_doc_step(issue)) }
  end

  # Step-to-label mapping for grouped run output display.
  STEP_LABELS = {
    "field_completeness" => "Field Completeness",
    "document_presence" => "Document Presence",
    "document_validity" => "Document Validity",
    "consistency" => "Field-to-Document Consistency",
    "expiry_status" => "Expiry Status"
  }.freeze

  # Pipeline step display order for grouped run output.
  STEP_ORDER = %w[field_completeness document_presence document_validity consistency expiry_status].freeze

  # Groups run output items by pipeline step in display order.
  # Items without a step tag are collected under "other".
  #
  # @param items [Array<Hash>] from kyc_run_output_items
  # @return [Array<Hash>] [{ key:, label:, items: }] ordered by pipeline sequence
  def kyc_run_output_grouped(items)
    by_step = items.group_by { |i| i[:step].presence || "other" }

    groups = STEP_ORDER.filter_map do |key|
      next unless by_step[key]

      { key: key, label: STEP_LABELS[key] || key.humanize, items: by_step[key] }
    end

    groups << { key: "other", label: "Other", items: by_step["other"] } if by_step["other"]
    groups
  end

  # Counts items per status category and source for tab labels.
  # Includes a "documents" count for the Documents tab.
  #
  # @param items [Array<Hash>] from kyc_run_output_items
  # @return [Hash] { "all" => 12, "matched" => 8, "failed" => 2, "warning" => 2, "documents" => 4 }
  def kyc_run_output_counts(items)
    counts = items.group_by { |i| i[:status].downcase }.transform_values(&:size)
    doc_count = items.count { |i| i[:source] == :document }
    { "all" => items.size, "passed" => counts["passed"].to_i,
      "failed" => counts["failed"].to_i, "warning" => counts["warning"].to_i,
      "documents" => doc_count }
  end

  # Controls visibility of the "Mark Verified" action icon. Only shown for
  # KYCs with a successful agent result that are not already verified.
  #
  # @param kyc [InvestorKyc]
  # @param report [SupportAgentReport, nil]
  # @return [Boolean]
  def show_mark_verified?(kyc, report)
    return false if report.blank?
    return false if kyc.submission_verified?

    report_json_fields(report)["final_status"] == "ready"
  end

  private

  # Safely parses report json_fields, handling both String and Hash forms.
  #
  # @param report [SupportAgentReport]
  # @return [Hash]
  def report_json_fields(report)
    raw = report.json_fields
    return raw if raw.is_a?(Hash)

    JSON.parse(raw.to_s)
  rescue JSON::ParserError
    {}
  end

  # Infers the pipeline step from a field issue's type/message for legacy
  # reports created before the step: tag was added.
  def infer_field_step(issue)
    type = issue["type"].to_s
    msg = issue["message"].to_s.downcase
    return "expiry_status" if %w[kyc_expired kyc_expiring_soon].include?(type)
    return "expiry_status" if type == "info" && (msg.include?("expiry") || msg.include?("valid until"))

    "field_completeness"
  end

  # Infers the pipeline step from a document issue's type for legacy reports.
  def infer_doc_step(issue)
    case issue["type"].to_s
    when "missing" then "document_presence"
    when "field_mismatch" then "consistency"
    when "mismatched_document", "document_unavailable", "llm_parse_error" then "document_validity"
    when "info" then issue["name"].present? ? "consistency" : "document_presence"
    else "document_presence"
    end
  end

  # Converts a field_issue hash to a display row for the run output panel.
  # Uses the field name as the item label and the current value as detail.
  #
  # @param issue [Hash]
  # @return [Hash] { item:, detail:, status: }
  def field_issue_to_row(issue)
    status = issue_status(issue)
    if issue["type"] == "info"
      { item: issue["message"], detail: "—", status: status }
    else
      val = issue["value"].presence || "(empty)"
      { item: issue["message"].to_s.humanize, detail: val, status: status }
    end
  end

  # Converts a document_issue hash to a display row for the run output panel.
  # Uses the document name as item and the message as detail for mismatches.
  #
  # @param issue [Hash]
  # @return [Hash] { item:, detail:, status: }
  def doc_issue_to_row(issue)
    status = issue_status(issue)
    name = issue["name"].presence || issue["message"]

    detail = case issue["type"]
             when "info" then "Valid"
             when "missing" then "Missing"
             when "field_mismatch", "document_unavailable", "llm_parse_error"
               issue["message"]
             when "mismatched_document" then issue["explanation"].presence || "Invalid document"
             else "—"
             end

    { item: name, detail: detail, status: status }
  end

  # Maps a single issue hash to a display status string for the detail panel.
  #
  # @param issue [Hash] with "severity" and/or "type" keys
  # @return [String] "Matched", "Warning", or "Failed"
  def issue_status(issue)
    case issue["severity"]
    when "success" then "Passed"
    when "warning" then "Warning"
    else "Failed"
    end
  end
end
