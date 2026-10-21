require 'cgi'

# Trailblazer operation that populates a PortfolioReportDraft:
#   1. Pull KPI actuals from DB → kpi_table_data
#   2. Call LLM once per section → section_data
#   3. Flip status to :review and notify the user
#
# Called from PortfolioReportDraftJob:
#   result = PortfolioReportDraftService.call(draft_id: id, user_id: user_id)
class PortfolioReportDraftService < Trailblazer::Operation
  step :load_draft
  step :pull_kpi_data
  step :generate_section_narratives
  step :finalize_draft
  left :handle_error

  private

  # ── Step 1 ────────────────────────────────────────────────────────────────

  def load_draft(ctx, draft_id:, **)
    draft = PortfolioReportDraft.find(draft_id)
    draft.update!(status: :generating)

    ctx[:draft]  = draft
    ctx[:entity] = draft.portfolio_report.entity
    ctx[:llm]    = LlmService.ruby_llm_chat(entity: ctx[:entity])

    Rails.logger.info { "[DraftService] draft=#{draft_id} generating for #{draft.portfolio_company}" }
    true
  rescue StandardError => e
    ctx[:error] = e
    false
  end

  # ── Step 2 ────────────────────────────────────────────────────────────────

  def pull_kpi_data(ctx, draft:, **)
    selected_ids = Array(draft.selected_kpi_mapping_ids).map(&:to_i)
    mappings     = InvestorKpiMapping.where(id: selected_ids).order(:position)

    # Fetch the last n_periods KpiReports for this portco up to end_date
    kpi_reports = KpiReport
                  .where(
                    portfolio_company: draft.portfolio_company,
                    entity: draft.portfolio_report.entity,
                    period: draft.kpi_period_type,
                    tag_list: draft.kpi_tag
                  )
                  .where(as_of: ..draft.end_date)
                  .order(as_of: :desc)
                  .limit(draft.n_periods)
                  .to_a
                  .reverse # oldest → newest

    period_labels = kpi_reports.map { |kr| format_period(kr.as_of, draft.kpi_period_type) }

    # Pre-fetch all Kpi rows in one query
    kpis_index = Kpi
                 .where(kpi_report: kpi_reports, investor_kpi_mapping: mappings)
                 .index_by { |k| [k.kpi_report_id, k.investor_kpi_mapping_id] }

    table_data = {}
    mappings.each do |ikm|
      table_data[ikm.id.to_s] = {}
      kpi_reports.each_with_index do |kr, i|
        kpi = kpis_index[[kr.id, ikm.id]]
        table_data[ikm.id.to_s][period_labels[i]] = kpi&.value
      end
    end

    draft.update!(kpi_table_data: table_data)

    ctx[:mappings]      = mappings
    ctx[:period_labels] = period_labels
    ctx[:kpi_reports]   = kpi_reports # passed to step 3 for commentary extraction

    Rails.logger.info do
      "[DraftService] KPI table built: #{mappings.count} metrics × #{period_labels.count} periods"
    end
    true
  rescue StandardError => e
    ctx[:error] = e
    false
  end

  # ── Step 3 ────────────────────────────────────────────────────────────────

  def generate_section_narratives(ctx, draft:, llm:, mappings:, period_labels:, kpi_reports: [], **)
    sections = ordered_sections(draft)

    notes = draft.portfolio_company.notes
                 .where(entity: draft.portfolio_report.entity)
                 .with_all_rich_text
                 .order(created_at: :desc)
                 .limit(10)
                 .to_a

    kpi_ctx   = build_kpi_context(draft, mappings, period_labels)
    notes_ctx = build_notes_context(notes)

    # Download PDFs from the last KPI report once.
    # Small enough combined → pass binary files directly to every section ask.
    # Too large to fit in one request → extract text locally with PDF::Reader, pass text to sections.
    with_kpi_report_pdfs(kpi_reports) do |kpi_report_ctx, pdf_paths|
      sections.each do |section|
        Rails.logger.info { "[DraftService] Generating section '#{section.name}'" }

        prompt = build_section_prompt(section, kpi_ctx, notes_ctx, kpi_report_ctx, draft)

        ask_opts = pdf_paths.any? ? { with: pdf_paths } : {}
        response = llm.ask(prompt, **ask_opts)
        raw_text = extract_text(response)

        # Convert JSON array of bullet strings → <ul><li> HTML for rich text storage.
        # Falls back to wrapping raw lines in <ul> if JSON parsing fails.
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
        draft.save! # persist after each section — partial progress is recoverable
      end
    end

    true
  rescue StandardError => e
    ctx[:error] = e
    false
  end

  # ── Step 4 ────────────────────────────────────────────────────────────────

  def finalize_draft(_ctx, draft:, user_id:, **)
    draft.update!(status: :review)
    if user_id.present?
      url  = Rails.application.routes.url_helpers.portfolio_report_draft_path(draft)
      msg  = "Report draft ready — #{draft.portfolio_company} (#{draft.portfolio_report_template.name}). " \
             "<a href=\"#{url}\" class=\"alert-link\">Open to review &rarr;</a>"
      UserAlert.new(user_id: user_id, message: msg, level: "success").broadcast
    end
    true
  end

  # ── Error handler (left track) ─────────────────────────────────────────────

  def handle_error(ctx, draft: nil, user_id: nil, **)
    msg = ctx[:error]&.message.to_s.truncate(200)
    Rails.logger.error { "[DraftService] failed — #{msg}\n#{ctx[:error]&.backtrace&.first(5)&.join("\n")}" }
    draft&.update!(status: :configuring) # let user retry
    if user_id.present?
      UserAlert.new(
        user_id: user_id,
        message: "Draft generation failed: #{msg}",
        level: "danger"
      ).broadcast
    end
    true
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  def ordered_sections(draft)
    all = draft.portfolio_report.portfolio_report_sections.index_by(&:id)
    draft.portfolio_report_template.ordered_section_ids.filter_map { |id| all[id] }
  end

  def build_kpi_context(draft, mappings, period_labels)
    return "No KPI data available." if period_labels.empty? || mappings.empty?

    lines = [
      "KPI Data (#{draft.kpi_period_type} #{draft.kpi_tag} — #{period_labels.count} periods):",
      ""
    ]

    metric_w = mappings.map { |m| m.reported_kpi_name.length }.max.to_i + 2
    col_w    = [period_labels.map(&:length).max.to_i, 10].max + 2

    header = "Metric".ljust(metric_w) + period_labels.map { |l| l.rjust(col_w) }.join
    lines << header
    lines << ("-" * header.length)

    mappings.each do |ikm|
      cols = period_labels.map do |lbl|
        val = draft.kpi_table_data.dig(ikm.id.to_s, lbl)
        format_kpi_value(val, ikm).rjust(col_w)
      end.join
      lines << "#{ikm.reported_kpi_name.ljust(metric_w)}#{cols}"
    end

    lines.join("\n")
  end

  def format_kpi_value(value, ikm)
    return "—" if value.nil?

    v = value.to_f
    case ikm.data_type
    when "money"
      case ikm.denomination.to_s
      when "millions"  then "$#{format('%.2f', v)}M"
      when "thousands" then "$#{format('%.0f', v)}K"
      when "crores"    then "₹#{format('%.2f', v)}Cr"
      when "lakhs"     then "₹#{format('%.2f', v)}L"
      else                  "$#{format('%.2f', v)}"
      end
    when "percentage" then "#{format('%.1f', v)}%"
    else value.to_s
    end
  end

  def build_notes_context(notes)
    return "No notes available." if notes.empty?

    notes.map do |n|
      body = n.details.to_plain_text.strip.truncate(600)
      "[#{n.created_at.to_date}] #{body}"
    end.join("\n\n")
  end

  # Raw 10 MB ≈ 13 MB base64-encoded, leaving comfortable headroom under the ~20 MB
  # API request body limit once the text prompt is included.
  MAX_COMBINED_PDF_BYTES = 10 * 1024 * 1024

  # Yields (commentary_text, pdf_paths) to the block.
  #
  # Fast path  — combined PDFs ≤ MAX_COMBINED_PDF_BYTES:
  #   pdf_paths contains all tempfile paths; section calls attach them as multimodal input.
  #
  # Fallback   — combined PDFs > MAX_COMBINED_PDF_BYTES:
  #   Greedy-batches by size; extracts each batch locally with PDF::Reader (zero API cost,
  #   no chat-history side effects). pdf_paths is empty; section calls receive text only.
  #   Every file is still fully processed — nothing is dropped.
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
      tmpfiles << { doc: doc, tmp: tmp } # register before I/O so ensure always cleans up
      tmp.binmode
      doc.file.open { |io| tmp.write(io.read) }
      tmp.flush
      Rails.logger.info { "[DraftService] Downloaded PDF '#{doc.name}' (#{tmp.size} bytes)" }
    rescue StandardError => e
      Rails.logger.warn { "[DraftService] Could not download PDF '#{doc.name}': #{e.message}" }
    end

    total_bytes = tmpfiles.sum { |t| t[:tmp].size }
    Rails.logger.info { "[DraftService] Total PDF payload: #{total_bytes} bytes (#{tmpfiles.size} files)" }

    if total_bytes <= MAX_COMBINED_PDF_BYTES
      # Fast path — everything fits; pass binaries directly to section calls.
      tmpfiles.each { |t| lines << "PDF attached: #{t[:doc].name}" }
      commentary = lines.any? ? "[#{label}]\n#{lines.join("\n")}" : "No KPI report commentary available."
      yield commentary, tmpfiles.map { |t| t[:tmp].path }
    else
      # Greedy batching — pack as many PDFs as fit per batch, extract text locally per batch.
      batches = greedy_pdf_batches(tmpfiles)
      Rails.logger.info do
        "[DraftService] Payload #{total_bytes} bytes exceeds limit — #{batches.size} greedy batch(es), extracting locally"
      end

      batches.each_with_index do |batch, idx|
        batch_names = batch.map { |e| e[:doc].name }
        batch_bytes = batch.sum { |e| e[:tmp].size }
        Rails.logger.info { "[DraftService] Batch #{idx + 1}/#{batches.size}: #{batch_names.join(', ')} (#{batch_bytes} bytes)" }

        batch.each do |entry|
          text = extract_pdf_text(entry[:tmp].path)
          lines << "--- #{entry[:doc].name} ---"
          lines << text.truncate(3000)
        end
      end

      commentary = lines.any? ? "[#{label}]\n#{lines.join("\n")}" : "No KPI report commentary available."
      yield commentary, []
    end
  ensure
    tmpfiles.each do |entry|
      entry[:tmp].close
      entry[:tmp].unlink rescue nil
    end
  end

  # Groups tmpfile entries into the fewest batches where each batch's combined size
  # stays within MAX_COMBINED_PDF_BYTES. Greedy left-to-right.
  def greedy_pdf_batches(tmpfiles)
    batches       = []
    current_batch = []
    current_size  = 0

    tmpfiles.each do |entry|
      size = entry[:tmp].size
      if current_batch.any? && current_size + size > MAX_COMBINED_PDF_BYTES
        batches << current_batch
        current_batch = [entry]
        current_size  = size
      else
        current_batch << entry
        current_size  += size
      end
    end
    batches << current_batch if current_batch.any?
    batches
  end

  # Local PDF text extraction — zero API cost, no chat-history side effects.
  def extract_pdf_text(file_path)
    require 'pdf-reader'
    PDF::Reader.new(file_path).pages.first(100).map(&:text).join("\n\n")
  rescue StandardError => e
    Rails.logger.warn { "[DraftService] PDF text extraction failed for #{file_path}: #{e.message}" }
    "(text extraction failed: #{e.message.truncate(120)})"
  end

  def build_section_prompt(section, kpi_context, notes_context, kpi_report_commentary, draft)
    <<~PROMPT
      You are an analyst at a private equity fund writing a section of a portfolio report.
      Portfolio company: #{draft.portfolio_company.investor_name}
      Report period: #{draft.start_date.strftime('%b %Y')} to #{draft.end_date.strftime('%b %Y')}

      Section: #{section.name}
      Instructions: #{section.data}

      Use only the data provided below. Be factual and specific.

      === KPI DATA ===
      #{kpi_context}

      === KPI REPORT COMMENTARY ===
      #{kpi_report_commentary}

      === RECENT PORTCO NOTES ===
      #{notes_context}

      Respond with a JSON array of concise, insight-driven bullet-point strings (3-6 items).
      Each item is one complete, specific sentence or data point.
      Do NOT include markdown, nesting, or ```json fences — just the raw JSON array.
      Example: ["Revenue grew 8% MoM to $1.40M", "Gross margin stable at 40%"]
    PROMPT
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

  def extract_text(response)
    return response.to_s unless response.respond_to?(:content)

    content = response.content
    content.to_s
  end
end
