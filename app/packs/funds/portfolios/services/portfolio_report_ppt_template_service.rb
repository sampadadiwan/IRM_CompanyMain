require 'cgi'
require 'zip'
require 'nokogiri'

# Fills [[ placeholder ]] markers inside an uploaded .pptx style file with real draft
# content. Every slide, master, layout, theme, and relationship file is carried over
# verbatim — only the text content of shapes that contain placeholders is touched.
#
# Supported placeholders (case-insensitive, extra spaces ignored):
#   [[ company name ]]         — portfolio company name
#   [[ fund name ]]            — portfolio report name
#   [[ template name ]]        — template name
#   [[ period ]]               — "Jan 2024 – Jun 2024"
#   [[ prepared date ]]        — today's date
#   [[ kpi table ]]            — replaces the shape with a full PPTX table graphic frame
#                                sized to match the placeholder shape's exact dimensions
#   [[ section: Name ]]        — bullet narrative for that section (replaces shape txBody)
#   [[ all sections ]]         — all sections concatenated as bullets on one shape
#
# Activation: export job calls has_placeholders? on the uploaded file and routes here
# instead of the generated-service path when placeholders are found.
class PortfolioReportPptTemplateService
  PLACEHOLDER_RE = /\[\[\s*(.+?)\s*\]\]/im.freeze
  NS = {
    "p" => "http://schemas.openxmlformats.org/presentationml/2006/main",
    "a" => "http://schemas.openxmlformats.org/drawingml/2006/main",
    "r" => "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  }.freeze

  # Returns true when the uploaded .pptx contains at least one [[ ]] marker across all slides.
  def self.has_placeholders?(pptx_path)
    Zip::File.open(pptx_path) do |zip|
      zip.select { |e| e.name.match?(%r{\Appt/slides/slide\d+\.xml\z}) }.any? do |entry|
        doc = Nokogiri::XML(entry.get_input_stream.read)
        doc.xpath("//a:r/a:t", NS).any? { |t| t.text.include?("[[") }
      end
    end
  rescue StandardError
    false
  end

  def initialize(draft)
    @draft         = draft
    @portco        = draft.portfolio_company
    @template      = draft.portfolio_report_template
    @sections      = ordered_sections
    @mappings      = InvestorKpiMapping
                       .where(id: Array(draft.selected_kpi_mapping_ids).map(&:to_i))
                       .order(:position)
    @period_labels = draft.effective_kpi_table.values.first&.keys || []
  end

  # Returns filled .pptx bytes. Every zip entry except slide XMLs is copied verbatim.
  def generate(style_pptx_path)
    Zip::File.open(style_pptx_path) do |zip|
      Zip::OutputStream.write_buffer do |out|
        zip.each do |entry|
          out.put_next_entry(entry.name)
          if entry.name.match?(%r{\Appt/slides/slide\d+\.xml\z})
            out.write(process_slide_xml(entry.get_input_stream.read))
          else
            out.write(zip.read(entry.name))
          end
        end
      end.string
    end
  end

  private

  def process_slide_xml(xml_str)
    doc = Nokogiri::XML(xml_str)

    doc.xpath("//p:sp", NS).to_a.each do |shape|
      full_text = shape.xpath(".//a:r/a:t", NS).map(&:text).join
      next unless full_text.include?("[[")

      m = full_text.match(PLACEHOLDER_RE)
      next unless m

      resolve_ppt_placeholder(shape, m[1].strip.downcase, doc)
    end

    doc.to_xml(encoding: "UTF-8")
  end

  def resolve_ppt_placeholder(shape, key, doc)
    case key
    when "company name"             then replace_ppt_text(shape, @portco.to_s, doc)
    when "fund name", "report name" then replace_ppt_text(shape, @template.portfolio_report.name, doc)
    when "template name"            then replace_ppt_text(shape, @template.name, doc)
    when "period"                   then replace_ppt_text(shape, period_label, doc)
    when "prepared date"            then replace_ppt_text(shape, Date.today.strftime("%d %b %Y"), doc)
    when /\Asection:\s*(.+)\z/i
      section = @sections.find { |s|
        s.name.casecmp?($1.strip) || s.name.downcase.include?($1.strip.downcase)
      }
      return unless section
      replace_ppt_bullets(shape, extract_bullets(@draft.narrative_for(section.id)), doc)
    when "all sections"
      bullets = @sections.flat_map { |s|
        ["▸ #{s.name}"] + extract_bullets(@draft.narrative_for(s.id))
      }
      replace_ppt_bullets(shape, bullets, doc)
    when "kpi table"
      replace_ppt_with_kpi_table(shape, doc)
    end
  end

  # ── Shape text replacement ────────────────────────────────────────────────────

  # Replaces the text body content with a single value while keeping the shape's
  # geometry, background, border, and the original run's font/size/colour.
  def replace_ppt_text(shape, text, doc)
    txBody = shape.at_xpath("p:txBody", NS)
    return unless txBody

    rPr_xml   = txBody.at_xpath(".//a:r/a:rPr", NS)&.to_xml(save_with: 0) ||
                "<a:rPr lang=\"en-US\" dirty=\"0\"/>"
    body_pr   = txBody.at_xpath("a:bodyPr",   NS)&.to_xml(save_with: 0) || "<a:bodyPr/>"
    lst_style = txBody.at_xpath("a:lstStyle", NS)&.to_xml(save_with: 0) || "<a:lstStyle/>"

    new_txBody = <<~XML
      <p:txBody>
        #{body_pr}#{lst_style}
        <a:p>
          <a:r>#{rPr_xml}<a:t>#{CGI.escapeHTML(text)}</a:t></a:r>
        </a:p>
      </p:txBody>
    XML

    txBody.replace(doc.fragment(new_txBody))
  end

  # Replaces the text body with a bullet list while keeping the shape's geometry.
  # The original run's rPr (font, size, colour) is reused so the bullets look right.
  def replace_ppt_bullets(shape, lines, doc)
    txBody = shape.at_xpath("p:txBody", NS)
    return unless txBody

    rPr_xml   = txBody.at_xpath(".//a:r/a:rPr", NS)&.to_xml(save_with: 0) ||
                "<a:rPr lang=\"en-US\" sz=\"1700\" dirty=\"0\"/>"
    body_pr   = txBody.at_xpath("a:bodyPr", NS)&.to_xml(save_with: 0) ||
                "<a:bodyPr anchor=\"t\" wrap=\"square\"><a:normAutofit/></a:bodyPr>"
    lst_style = txBody.at_xpath("a:lstStyle", NS)&.to_xml(save_with: 0) || "<a:lstStyle/>"

    paras = lines.each_with_index.map do |line, i|
      spc = i > 0 ? "<a:spcBef><a:spcPts val=\"180\"/></a:spcBef>" : ""
      <<~PARA
        <a:p>
          <a:pPr marL="342900" indent="-342900">
            #{spc}<a:buChar char="•"/>
          </a:pPr>
          <a:r>#{rPr_xml}<a:t xml:space="preserve">#{CGI.escapeHTML(line)}</a:t></a:r>
        </a:p>
      PARA
    end.join

    txBody.replace(doc.fragment("<p:txBody>#{body_pr}#{lst_style}#{paras}</p:txBody>"))
  end

  # Replaces a text shape with a PPTX graphicFrame table, using the placeholder
  # shape's own x/y/cx/cy so the table lands exactly where the designer placed it.
  def replace_ppt_with_kpi_table(shape, doc)
    return unless @mappings.any? && @period_labels.any?

    xfrm = shape.at_xpath("p:spPr/a:xfrm", NS)
    x    = xfrm&.at_xpath("a:off", NS)&.attr("x")&.to_i  || 685_800
    y    = xfrm&.at_xpath("a:off", NS)&.attr("y")&.to_i  || 1_300_000
    cx   = xfrm&.at_xpath("a:ext", NS)&.attr("cx")&.to_i || 10_820_400
    cy   = xfrm&.at_xpath("a:ext", NS)&.attr("cy")&.to_i || 4_000_000
    id   = shape.at_xpath("p:nvSpPr/p:cNvPr", NS)&.attr("id")&.to_i || 99

    shape.replace(doc.fragment(ppt_kpi_table_xml(id, x, y, cx, cy)))
  end

  # ── KPI table XML ────────────────────────────────────────────────────────────

  def ppt_kpi_table_xml(id, x, y, cx, cy)
    row_h        = 400_000
    metric_col_w = (cx * 0.38).to_i
    period_col_w = ((cx - metric_col_w) / [@period_labels.length, 1].max).to_i

    header_cells =
      ppt_tc("Metric", fill: "1A3C6E", color: "FFFFFF", bold: true,  w: metric_col_w, h: row_h) +
      @period_labels.map { |l|
        ppt_tc(l, fill: "1A3C6E", color: "FFFFFF", bold: true, w: period_col_w, h: row_h, align: "r")
      }.join

    data_rows = @mappings.each_with_index.map do |ikm, idx|
      fill  = idx.even? ? "EEF2F8" : "FFFFFF"
      cells = ppt_tc(ikm.reported_kpi_name, fill: fill, color: "1A1A1A", bold: false, w: metric_col_w, h: row_h)
      cells += @period_labels.map { |lbl|
        val = @draft.effective_kpi_table.dig(ikm.id.to_s, lbl)&.to_s || "—"
        ppt_tc(val, fill: fill, color: "1A1A1A", bold: false, w: period_col_w, h: row_h, align: "r")
      }.join
      "<a:tr h=\"#{row_h}\">#{cells}</a:tr>"
    end.join

    grid = "<a:gridCol w=\"#{metric_col_w}\"/>" +
           @period_labels.map { "<a:gridCol w=\"#{period_col_w}\"/>" }.join

    <<~XML
      <p:graphicFrame>
        <p:nvGraphicFramePr>
          <p:cNvPr id="#{id}" name="KpiTable_#{id}"/>
          <p:cNvGraphicFramePr><a:graphicFrameLocks noGrp="1"/></p:cNvGraphicFramePr>
          <p:nvPr/>
        </p:nvGraphicFramePr>
        <p:xfrm><a:off x="#{x}" y="#{y}"/><a:ext cx="#{cx}" cy="#{cy}"/></p:xfrm>
        <a:graphic>
          <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table">
            <a:tbl>
              <a:tblPr firstRow="1" bandRow="1">
                <a:solidFill><a:srgbClr val="FFFFFF"/></a:solidFill>
              </a:tblPr>
              <a:tblGrid>#{grid}</a:tblGrid>
              <a:tr h="#{row_h}">#{header_cells}</a:tr>
              #{data_rows}
            </a:tbl>
          </a:graphicData>
        </a:graphic>
      </p:graphicFrame>
    XML
  end

  def ppt_tc(text, fill:, color:, bold:, w:, h:, align: "l")
    <<~XML
      <a:tc>
        <a:txBody>
          <a:bodyPr/><a:lstStyle/>
          <a:p>
            <a:pPr algn="#{align}"/>
            <a:r>
              <a:rPr lang="en-US" sz="1200" b="#{bold ? 1 : 0}" dirty="0">
                <a:solidFill><a:srgbClr val="#{color}"/></a:solidFill>
              </a:rPr>
              <a:t>#{CGI.escapeHTML(text)}</a:t>
            </a:r>
          </a:p>
        </a:txBody>
        <a:tcPr>
          <a:solidFill><a:srgbClr val="#{fill}"/></a:solidFill>
          <a:lnL w="9525"><a:solidFill><a:srgbClr val="DDDDDD"/></a:solidFill></a:lnL>
          <a:lnR w="9525"><a:solidFill><a:srgbClr val="DDDDDD"/></a:solidFill></a:lnR>
          <a:lnT w="9525"><a:solidFill><a:srgbClr val="DDDDDD"/></a:solidFill></a:lnT>
          <a:lnB w="9525"><a:solidFill><a:srgbClr val="DDDDDD"/></a:solidFill></a:lnB>
        </a:tcPr>
      </a:tc>
    XML
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  def period_label
    "#{@draft.start_date.strftime('%b %Y')} – #{@draft.end_date.strftime('%b %Y')}"
  end

  def extract_bullets(html)
    return ["No content generated."] if html.blank?
    doc     = Nokogiri::HTML.fragment(html)
    bullets = doc.css("li").map { |li| li.text.strip }.reject(&:empty?)
    bullets = doc.css("p").map  { |p|  p.text.strip  }.reject(&:empty?) if bullets.empty?
    bullets = html.split("\n").map(&:strip).reject(&:empty?)             if bullets.empty?
    bullets.presence || ["No content generated."]
  end

  def ordered_sections
    all = @draft.portfolio_report.portfolio_report_sections.index_by(&:id)
    @template.ordered_section_ids.filter_map { |id| all[id] }
  end
end
