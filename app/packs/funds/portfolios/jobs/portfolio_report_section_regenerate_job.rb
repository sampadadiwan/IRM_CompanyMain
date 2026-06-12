require 'cgi'

class PortfolioReportSectionRegenerateJob < ApplicationJob
  include Rails.application.routes.url_helpers

  queue_as :low

  def perform(draft_id, section_id, user_id)
    draft   = PortfolioReportDraft.find(draft_id)
    section = draft.portfolio_report.portfolio_report_sections.find(section_id)

    entity  = draft.portfolio_report.entity
    llm     = LlmService.ruby_llm_chat(entity: entity)

    # Re-run only the KPI context build — reuse existing kpi_table_data already on the draft
    selected_ids  = Array(draft.selected_kpi_mapping_ids).map(&:to_i)
    mappings      = InvestorKpiMapping.where(id: selected_ids).order(:position)
    period_labels = draft.effective_kpi_table.values.first&.keys || []

    kpi_ctx = build_kpi_context(draft, mappings, period_labels)

    notes = draft.portfolio_company.notes
                 .where(entity: entity)
                 .with_all_rich_text
                 .order(created_at: :desc)
                 .limit(10)
                 .to_a
    notes_ctx = build_notes_context(notes)

    # Pull the same KPI reports used when the draft was first generated
    kpi_reports = KpiReport
                  .where(portfolio_company: draft.portfolio_company, entity: entity,
                         period: draft.kpi_period_type, tag_list: draft.kpi_tag)
                  .where(as_of: ..draft.end_date)
                  .order(as_of: :desc).limit(draft.n_periods).to_a.reverse

    with_kpi_report_pdfs(kpi_reports) do |kpi_report_ctx, pdf_paths|
      prompt   = build_section_prompt(section, kpi_ctx, notes_ctx, kpi_report_ctx, draft)
      ask_opts = pdf_paths.any? ? { with: pdf_paths } : {}
      response = llm.ask(prompt, **ask_opts)
      raw_text = if response.is_a?(String)
                   response
                 else
                   (response.respond_to?(:content) ? response.content : response.to_s)
                 end

      bullets = begin
        parsed = JSON.parse(raw_text.gsub(/\A```json\s*|\s*```\z/, "").strip)
        if parsed.is_a?(Array) && parsed.any?
          items = parsed.map { |b| "<li>#{CGI.escapeHTML(b.to_s)}</li>" }.join
          "<ul>#{items}</ul>"
        else
          raw_text
        end
      rescue JSON::ParserError
        lines = raw_text.split("\n").map(&:strip).reject(&:empty?)
        lines.any? ? "<ul>#{lines.map { |l| "<li>#{CGI.escapeHTML(l)}</li>" }.join}</ul>" : raw_text
      end

      draft.set_llm_output(section.id, bullets)
      draft.save!
    end

    url = portfolio_report_draft_path(draft)
    msg = "Section \"#{section.name}\" regenerated for #{draft.portfolio_company}. " \
          "<a href=\"#{url}\" class=\"alert-link\">Open draft &rarr;</a>"
    UserAlert.new(user_id: user_id, message: msg, level: "success").broadcast if user_id.present?
  rescue StandardError => e
    Rails.logger.error { "[SectionRegenerateJob] draft=#{draft_id} section=#{section_id}: #{e.message}" }
    UserAlert.new(user_id: user_id, message: "Section regeneration failed: #{e.message.truncate(200)}", level: "danger").broadcast if user_id.present?
    raise
  end

  private

  def build_kpi_context(draft, mappings, period_labels)
    return "No KPI data available." if period_labels.empty? || mappings.empty?

    lines    = ["KPI Data (#{draft.kpi_period_type} #{draft.kpi_tag} — #{period_labels.count} periods):", ""]
    metric_w = mappings.map { |m| m.reported_kpi_name.length }.max.to_i + 2
    col_w    = [period_labels.map(&:length).max.to_i, 10].max + 2
    header   = "Metric".ljust(metric_w) + period_labels.map { |l| l.rjust(col_w) }.join
    lines << header << ("-" * header.length)
    mappings.each do |ikm|
      cols = period_labels.map { |lbl| (draft.effective_kpi_table.dig(ikm.id.to_s, lbl)&.to_s || "—").rjust(col_w) }.join
      lines << "#{ikm.reported_kpi_name.ljust(metric_w)}#{cols}"
    end
    lines.join("\n")
  end

  def build_notes_context(notes)
    return "No notes available." if notes.empty?

    notes.map { |n| "[#{n.created_at.to_date}] #{n.details.to_plain_text.strip.truncate(600)}" }.join("\n\n")
  end

  def build_section_prompt(section, kpi_context, notes_context, kpi_report_commentary, draft)
    <<~PROMPT
      You are an analyst at a private equity fund writing a section of a portfolio report.
      Portfolio company: #{draft.portfolio_company.investor_name}
      Report period: #{draft.start_date.strftime('%b %Y')} to #{draft.end_date.strftime('%b %Y')}

      Section: #{section.name}
      Instructions: #{section.data}

      Use only the data provided below. Be factual and specific.
      Respond with a JSON array of bullet-point strings — one string per bullet, no markdown, no numbering.
      Each bullet should be a complete, standalone sentence.

      === KPI DATA ===
      #{kpi_context}

      === KPI REPORT COMMENTARY ===
      #{kpi_report_commentary}

      === RECENT PORTCO NOTES ===
      #{notes_context}
    PROMPT
  end

  # Downloads PDFs from the most recent KPI report into Tempfiles, yields paths, then cleans up.
  def with_kpi_report_pdfs(kpi_reports)
    tmpfiles = []

    if kpi_reports.empty?
      yield "No KPI report commentary available.", []
      return
    end

    kr    = KpiReport.includes(:documents).find(kpi_reports.last.id)
    label = format_period(kr.as_of, kr.period)
    lines = []

    lines << "Notes: #{kr.notes.strip}"       if kr.notes.present?
    lines << "Analysis: #{kr.analysis.strip}" if kr.analysis.present?

    kr.documents.reject { |d| d.owner_tag == "Generated" }.each do |doc|
      next unless doc.pdf?

      tmp = Tempfile.new([doc.name.parameterize.presence || "kpi-doc", ".pdf"])
      tmp.binmode
      doc.file.open { |io| tmp.write(io.read) }
      tmp.flush
      tmpfiles << tmp
      lines << "PDF attached: #{doc.name}"
      Rails.logger.info { "[SectionRegenerateJob] Attached PDF '#{doc.name}' (#{tmp.size} bytes)" }
    rescue StandardError => e
      Rails.logger.warn { "[SectionRegenerateJob] Skipped PDF '#{doc.name}': #{e.message}" }
    end

    commentary = lines.any? ? "[#{label}]\n#{lines.join("\n")}" : "No KPI report commentary available."
    yield commentary, tmpfiles.map(&:path)
  ensure
    tmpfiles.each do |t|
      t.close
      begin
        t.unlink
      rescue StandardError
        nil
      end
    end
  end

  def format_period(as_of, period_type)
    case period_type
    when "Quarter"   then "Q#{((as_of.month - 1) / 3) + 1} #{as_of.year}"
    when "Half Year" then "H#{as_of.month <= 6 ? 1 : 2} #{as_of.year}"
    when "Year"      then as_of.year.to_s
    when "YTD"       then "YTD #{as_of.year}"
    else as_of.strftime("%b %Y")
    end
  end
end
