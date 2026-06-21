require 'cgi'

class PortfolioReportExportJob < ApplicationJob
  include Rails.application.routes.url_helpers

  queue_as :low

  # Renders a PortfolioReportDraft to .docx or .pptx depending on template.output_format.
  def perform(draft_id, user_id)
    draft    = PortfolioReportDraft.find(draft_id)
    user     = User.find(user_id)
    portco   = draft.portfolio_company
    template = draft.portfolio_report_template

    Rails.logger.info { "[ExportJob] draft=#{draft_id} format=#{template.output_format} portco=#{portco}" }

    Chewy.strategy(:sidekiq) do
      doc = if template.output_format == "ppt"
              generate_ppt(draft, portco, user)
            else
              generate_word(draft, portco, user, template)
            end
      draft.update!(generated_document: doc, status: :exported)
    end

    url  = portfolio_report_draft_path(draft)
    ext  = template.output_format == "ppt" ? "PPTX" : "Word"
    msg  = "#{ext} export ready — #{portco} (#{template.name}). " \
           "<a href=\"#{url}\" class=\"alert-link\">View &rarr;</a>"
    UserAlert.new(user_id: user_id, message: msg, level: "success").broadcast
  rescue StandardError => e
    Rails.logger.error { "[ExportJob] failed draft=#{draft_id}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}" }
    begin
      draft.update_columns(status: "failed")
    rescue StandardError
      nil
    end
    UserAlert.new(
      user_id: user_id,
      message: "Report export failed: #{e.message.truncate(200)}",
      level: "danger"
    ).broadcast
    raise
  end

  private

  # ── HTML builder ────────────────────────────────────────────────────────────

  def build_html(draft, template)
    portco    = draft.portfolio_company
    sections  = ordered_sections(draft)
    mappings  = InvestorKpiMapping
                .where(id: Array(draft.selected_kpi_mapping_ids).map(&:to_i))
                .order(:position)
    period_labels = draft.effective_kpi_table.values.first&.keys || []

    html = <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <title>#{portco} — #{template.name}</title>
        <style>
          body  { font-family: Calibri, Arial, sans-serif; font-size: 11pt; line-height: 1.5; color: #1a1a1a; }
          h1    { font-size: 20pt; color: #1A3C6E; }
          h2    { font-size: 14pt; color: #1A3C6E; border-bottom: 1px solid #ccc; padding-bottom: 4px; }
          table { width: 100%; border-collapse: collapse; font-size: 10pt; margin-bottom: 1em; }
          th    { background: #1A3C6E; color: #fff; padding: 6px 8px; text-align: left; }
          th.num, td.num { text-align: right; }
          td    { border: 1px solid #ddd; padding: 5px 8px; }
          tr.cat td { background: #f0f4fa; font-weight: bold; font-size: 9pt; text-transform: uppercase; color: #555; }
          p     { margin: 0.4em 0; }
        </style>
      </head>
      <body>
        <h1>#{portco} — #{template.name}</h1>
        <p style="color:#666; font-size:10pt;">
          #{draft.kpi_period_type} #{draft.kpi_tag} &middot;
          #{draft.start_date.strftime('%b %Y')} to #{draft.end_date.strftime('%b %Y')} &middot;
          #{draft.n_periods} periods
        </p>
    HTML

    # ── KPI table ──────────────────────────────────────────────────────────────
    if mappings.any? && period_labels.any?
      html << "<h2>KPI Data</h2>\n<table>\n<thead><tr><th>Metric</th>"
      period_labels.each { |l| html << "<th class=\"num\">#{l}</th>" }
      html << "</tr></thead>\n<tbody>\n"

      mappings.group_by(&:category).each do |category, group|
        html << "<tr class=\"cat\"><td colspan=\"#{period_labels.length + 1}\">#{CGI.escapeHTML(category.presence || 'Other')}</td></tr>\n"
        group.each do |ikm|
          label = CGI.escapeHTML(ikm.reported_kpi_name)
          label += " <small>(#{CGI.escapeHTML(ikm.denomination)})</small>" if ikm.denomination.present?
          html << "<tr><td>#{label}</td>"
          period_labels.each do |lbl|
            val = draft.effective_kpi_table.dig(ikm.id.to_s, lbl)
            html << "<td class=\"num\">#{val || '—'}</td>"
          end
          html << "</tr>\n"
        end
      end

      html << "</tbody></table>\n"
    end

    # ── Section narratives ─────────────────────────────────────────────────────
    sections.each do |section|
      narrative = draft.narrative_for(section.id)
      next if narrative.blank?

      html << "<h2>#{CGI.escapeHTML(section.name)}</h2>\n"
      # narrative is stored as HTML (from Trix editor or LLM <ul><li> output)
      html << "<div>#{narrative}</div>\n"
    end

    html << "\n</body></html>"
    html
  end

  # ── PPT export ───────────────────────────────────────────────────────────────

  def generate_ppt(draft, portco, user)
    template = draft.portfolio_report_template

    if template.style_document.present?
      template.style_document.file.download do |style_tmp|
        if PortfolioReportPptTemplateService.has_placeholders?(style_tmp.path)
          # Placeholder mode — fill [[ markers ]] in the user's own PPTX design
          bytes = PortfolioReportPptTemplateService.new(draft).generate(style_tmp.path)
        else
          # Theme-only mode — generated service reads colours from the uploaded file
          overrides  = ppt_theme_overrides_from_path(style_tmp.path)
          bytes      = template.ppt_service_class.new(draft, theme_overrides: overrides).generate
        end
        save_and_upload(draft, portco, user, bytes, ext: "pptx")
      end
    else
      bytes = template.ppt_service_class.new(draft).generate
      save_and_upload(draft, portco, user, bytes, ext: "pptx")
    end
  end

  # ── Word export ──────────────────────────────────────────────────────────────

  def generate_word(draft, portco, user, template)
    if template.style_document.present?
      template.style_document.file.download do |style_tmp|
        if PortfolioReportWordTemplateService.has_sablon_placeholders?(style_tmp.path)
          # Sablon mode — full «variable» interpolation with rich context
          bytes = PortfolioReportSablonWordService.new(draft).generate(style_tmp.path)
          save_and_upload(draft, portco, user, bytes, ext: "docx")
        elsif PortfolioReportWordTemplateService.has_placeholders?(style_tmp.path)
          # Placeholder mode — fill [[ markers ]] in the user's own Word design
          bytes = PortfolioReportWordTemplateService.new(draft).generate(style_tmp.path)
          save_and_upload(draft, portco, user, bytes, ext: "docx")
        else
          # Theme-only mode — htmltoword uses the uploaded doc as a style base
          html  = build_html(draft, template)
          htw   = Htmltoword::Document.new(style_tmp.path)
          htw.replace_files(html)
          save_and_upload(draft, portco, user, htw.generate, ext: "docx")
        end
      end
    else
      html = build_html(draft, template)
      save_and_upload(draft, portco, user, Htmltoword::Document.create(html), ext: "docx")
    end
  end

  # ── Bytes → tempfile → upload ────────────────────────────────────────────────

  def save_and_upload(draft, portco, user, bytes, ext: "docx")
    tmp = Tempfile.new(["draft_export", ".#{ext}"])
    begin
      tmp.binmode
      tmp.write(bytes)
      tmp.flush
      upload_document(draft, portco, user, tmp.path, ext: ext)
    ensure
      tmp.close!
    end
  end

  # ── Document upload ──────────────────────────────────────────────────────────

  def upload_document(draft, portco, user, file_path, ext: "docx")
    # Use ASCII-only name — S3 Content-Disposition requires ISO-8859-1 safe filenames
    base     = draft.portfolio_report_template.name.tr('—', '-')
    period   = "#{draft.start_date.strftime('%b %Y')} to #{draft.end_date.strftime('%b %Y')}"
    doc_name = "#{base} - #{period}"

    Document.create!(
      entity_id: portco.entity_id,
      owner: portco,
      folder: portco.document_folder,
      name: doc_name,
      file: File.open(file_path),
      orignal: true,
      user: user,
      download: true
    )
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  # Reads accent colour + font from an already-downloaded .pptx file path.
  # Called in theme-only mode (no placeholders) after the file is already open.
  def ppt_theme_overrides_from_path(pptx_path)
    PortfolioReportPptThemeReader.new(pptx_path).overrides
  rescue StandardError => e
    Rails.logger.warn { "[ExportJob] Could not read PPT style theme: #{e.message}" }
    {}
  end

  def ordered_sections(draft)
    all = draft.portfolio_report.portfolio_report_sections.index_by(&:id)
    draft.portfolio_report_template.ordered_section_ids.filter_map { |id| all[id] }
  end
end
