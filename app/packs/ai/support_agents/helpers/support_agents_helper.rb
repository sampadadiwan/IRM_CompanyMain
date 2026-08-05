module SupportAgentsHelper
  # Normalizes an execution result_summary into { total:, processed:, failed: }.
  # Handles all three historical shapes:
  #   - canonical {total, processed, failed} (scheduled path, and manual since Aug 2026)
  #   - legacy manual-run {successes, errors}
  #   - legacy batch-delegation {batch: true, target_count:} — recorded before
  #     per-target counts existed; those runs completed, so target_count is
  #     shown as processed (matching the old optimistic behavior)
  def normalized_result_summary(summary)
    s = (summary || {}).transform_keys(&:to_s)
    legacy_batch = s["batch"] && s.key?("target_count") && !s.key?("processed")
    processed = legacy_batch ? s["target_count"].to_i : (s["processed"] || s["successes"]).to_i
    failed    = (s["failed"] || s["errors"]).to_i
    total     = s.key?("total") ? s["total"].to_i : processed + failed
    { total: total, processed: processed, failed: failed }
  end

  # Renders execution result_summary hash as stat pill cards (Total / Processed / Failed).
  def format_result_summary(summary)
    return "".html_safe if summary.blank?

    counts    = normalized_result_summary(summary)
    total     = counts[:total]
    processed = counts[:processed]
    failed    = counts[:failed]

    pills = [
      { label: "Total",     value: total,     css: "exec-stat-pill--neutral" },
      { label: "Processed", value: processed, css: processed.positive? ? "exec-stat-pill--success" : "exec-stat-pill--neutral" },
      { label: "Failed",    value: failed,    css: failed.positive?    ? "exec-stat-pill--danger"  : "exec-stat-pill--neutral" }
    ]

    content_tag(:div, class: "exec-stat-pills") do
      safe_join(pills.map do |p|
        content_tag(:div, class: "exec-stat-pill #{p[:css]}") do
          content_tag(:div, p[:value], class: "exec-stat-pill__value") +
            content_tag(:div, p[:label], class: "exec-stat-pill__label")
        end
      end)
    end
  end

  # One-liner for the non-expanded table row — EsignMonitorAgent only.
  # Returns nil if the summary has no esign-specific keys (falls back to generic mini-stats).
  def esign_execution_oneliner(summary)
    return nil if summary.blank?

    s = summary.transform_keys(&:to_s)
    return nil unless s.key?("docs_checked")

    notified = s["notified"].to_i
    expired  = s["expired_flagged"].to_i
    checked  = s["docs_checked"].to_i

    parts = []
    parts << "#{notified} doc#{"s" if notified != 1} reported to team" if notified > 0
    parts << "#{expired} expired — action needed"                       if expired > 0
    parts << (checked > 0 ? "No action needed" : "All clear")          if parts.empty?
    parts.join(" · ")
  end

  # Descriptive narrative panel for EsignMonitorAgent expanded rows.
  # Replaces the generic stat pills with what the agent actually found and what
  # the user should do next.
  # Returns the findings list HTML for the "What the Agent Found" card.
  def esign_findings_html(summary)
    return nil if summary.blank?

    s = summary.transform_keys(&:to_s)
    return nil unless s.key?("docs_checked")

    checked  = s["docs_checked"].to_i
    notified = s["notified"].to_i
    expired  = s["expired_flagged"].to_i

    items = []

    if checked.zero? && expired.zero?
      items << "Pipeline is clean — no stuck or expired documents"
    else
      if checked > 0
        items << "Found #{checked} document#{"s" if checked != 1} stuck in 'requested' e-sign state"
        items << "Status report emailed to stakeholders listing #{notified} pending document#{"s" if notified != 1}"
      end

      if expired > 0
        items << "#{expired} document#{"s" if expired != 1} expired or voided — requires manual action"
      else
        items << "No expired or voided documents"
      end
    end

    content_tag(:ol, class: "mb-0 ps-3") do
      safe_join(items.map { |t| content_tag(:li, t) })
    end
  end

  # Returns the next-steps strings for the "Next Steps" card (nil if nothing to do).
  def esign_next_steps_items(summary)
    return nil if summary.blank?

    s = summary.transform_keys(&:to_s)
    return nil unless s.key?("docs_checked")

    expired = s["expired_flagged"].to_i

    steps = []
    steps << "Check your email — the agent has sent a full status report listing pending signatories for each stuck document. Contact the signatories directly to follow up." if s["notified"].to_i > 0
    steps << "Re-initiate e-signing manually for #{expired == 1 ? "the" : expired} expired or voided document#{"s" if expired != 1} — these cannot be automatically resent." if expired > 0
    steps.presence
  end

  # Renders the per-document esign issues as a styled table.
  # Filters out :info type entries — those are captured in the narrative summary cards.
  # For "notified" entries, renders pending_signers as individual pills.
  def format_esign_issues_table(issues)
    return "".html_safe if issues.blank?

    doc_issues = issues.reject { |i| (i["type"] || i[:type]).to_s == "info" }
    return "".html_safe if doc_issues.empty?

    thead = content_tag(:thead, class: "table-light") do
      content_tag(:tr) do
        content_tag(:th, "Document") +
          content_tag(:th, "Status", style: "width: 120px") +
          content_tag(:th, "Pending Signers / Notes")
      end
    end

    tbody = content_tag(:tbody) do
      safe_join(doc_issues.map do |issue|
        type    = (issue["type"] || issue[:type]).to_s
        sev     = (issue["severity"] || issue[:severity]).to_s
        name    = issue["name"] || issue[:name] || "—"
        msg     = issue["message"] || issue[:message]
        signers = issue["pending_signers"] || issue[:pending_signers] || []

        badge_html, _row_cls = esign_issue_badge(type, sev)

        # Build the signers/detail cell
        detail_html = if type == "notified" && signers.any?
                        safe_join(signers.map do |s|
                          s = s.is_a?(Hash) ? s.with_indifferent_access : {}
                          label = s[:label].presence || s[:email] || "—"
                          tip   = s[:email].present? && s[:label].present? ? s[:email] : nil
                          content_tag(:span, class: "esign-signer-pill", title: tip) do
                            content_tag(:i, "", class: "ti ti-user-circle me-1") + label
                          end
                        end)
                      else
                        content_tag(:span, msg, class: "small text-muted")
                      end

        content_tag(:tr) do
          content_tag(:td, class: "small fw-medium", style: "max-width: 220px") do
            content_tag(:i, "", class: "ti ti-file-text text-secondary me-1") + name
          end +
            content_tag(:td) { badge_html } +
            content_tag(:td) { detail_html }
        end
      end)
    end

    content_tag(:table, thead + tbody, class: "table table-sm table-bordered esign-doc-table mb-0")
  end

  # Converts a LONG_DESCRIPTION heredoc into a fully structured HTML panel.
  #
  # Parsing rules (applied to blank-line-separated blocks):
  #   • Blocks containing "• item" lines → pipeline-steps section
  #   • Blocks starting with "Config:" → config-badges section
  #   • All other blocks → intro paragraph
  #
  # Each bullet item may span multiple lines; continuation lines are joined
  # onto the preceding bullet automatically.
  def format_agent_description(text)
    return "".html_safe if text.blank?

    sections = parse_agent_description_sections(text)
    parts    = sections.filter_map { |s| render_agent_description_section(s) }
    safe_join(parts)
  end

  private

  def esign_issue_badge(type, severity)
    case type
    when "notified"
      [content_tag(:span, class: "badge bg-primary") {
        content_tag(:i, "", class: "ti ti-mail me-1") + "Notified"
      }, nil]
    when "expired"
      [content_tag(:span, class: "badge bg-danger") {
        content_tag(:i, "", class: "ti ti-clock-x me-1") + "Expired / Voided"
      }, "table-danger"]
    else
      badge_css = severity == "success" ? "bg-success" : "bg-secondary"
      [content_tag(:span, type.humanize, class: "badge #{badge_css}"), nil]
    end
  end

  # Splits the text into typed sections.
  def parse_agent_description_sections(text)
    text.strip.split(/\n\n+/).map do |block|
      lines = block.strip.split("\n")
      if lines.any? { |l| l.strip.start_with?("•") }
        parse_bullets_block(lines)
      else
        joined = lines.map(&:strip).reject(&:empty?).join(" ")
        if joined.match?(/\AConfig:/i)
          { type: :config, text: joined.sub(/\AConfig:\s*/i, "") }
        else
          { type: :intro, text: joined }
        end
      end
    end
  end

  # Parses a block that contains "• bullet" lines, accumulating continuation lines.
  def parse_bullets_block(lines)
    header_lines = []
    items        = []
    current      = nil

    lines.each do |line|
      stripped = line.strip
      if stripped.start_with?("•")
        items << current if current
        current = stripped.sub(/\A•\s*/, "")
      elsif current.nil?
        header_lines << stripped unless stripped.empty?
      else
        current += " #{stripped}" unless stripped.empty?
      end
    end
    items << current if current

    { type: :steps, header: header_lines.join(" ").chomp(":"), items: items }
  end

  # Renders one parsed section into HTML.
  def render_agent_description_section(section)
    case section[:type]
    when :intro
      content_tag(:p, section[:text], class: "agent-about-intro")
    when :steps
      render_steps_section(section)
    when :config
      render_config_section(section)
    end
  end

  def render_steps_section(section)
    header_html = (content_tag(:div, section[:header], class: "agent-section-label") if section[:header].present?)

    step_tags = section[:items].each_with_index.map do |item, idx|
      if item.include?(" — ")
        title, body = item.split(" — ", 2)
      else
        title = item
        body  = nil
      end

      content_tag(:div, class: "agent-step") do
        badge = content_tag(:div, (idx + 1).to_s, class: "agent-step-num")
        inner = content_tag(:div, title, class: "agent-step-title")
        inner += content_tag(:div, body, class: "agent-step-body") if body.present?
        badge + content_tag(:div, inner)
      end
    end
    steps_html = safe_join(step_tags)

    content_tag(:div, class: "agent-steps-section") do
      safe_join([header_html, content_tag(:div, steps_html, class: "agent-steps")])
    end
  end

  def render_config_section(section)
    # Extract the first token of each comma-separated clause as the param name
    param_names = section[:text].split(/,\s*(?=[a-z_]+[\s(])/).filter_map do |clause|
      clause.strip.split(/[\s(]/)[0]
    end.reject(&:empty?).uniq

    badges = safe_join(param_names.map { |p| content_tag(:span, p, class: "agent-config-badge") }, " ")

    content_tag(:div, class: "agent-config-section") do
      content_tag(:span, "Config", class: "agent-section-label me-2") + badges
    end
  end
end
