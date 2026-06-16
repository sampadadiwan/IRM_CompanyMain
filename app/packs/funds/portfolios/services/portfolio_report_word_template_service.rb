require 'cgi'
require 'zip'
require 'nokogiri'

# Fills [[ placeholder ]] markers inside an uploaded .docx style file with real draft
# content, leaving all surrounding Word formatting (styles, margins, headers, footers)
# completely intact.
#
# Supported placeholders (case-insensitive, extra spaces ignored):
#   [[ company name ]]         — portfolio company name
#   [[ fund name ]]            — portfolio report name
#   [[ template name ]]        — template name
#   [[ period ]]               — "Jan 2024 – Jun 2024"
#   [[ prepared date ]]        — today's date
#   [[ kpi table ]]            — full KPI data table (replaces the paragraph with a <w:tbl>)
#   [[ section: Name ]]        — bullet narrative for that section
#   [[ all sections ]]         — every section as Heading2 + bullets in order
#
# Activation: export job calls has_placeholders? on the uploaded file and routes here
# instead of the htmltoword path when placeholders are found.
class PortfolioReportWordTemplateService
  PLACEHOLDER_RE = /\[\[\s*(.+?)\s*\]\]/im
  W_NS = { "w" => "http://schemas.openxmlformats.org/wordprocessingml/2006/main" }.freeze

  # Returns true when the uploaded .docx contains at least one [[ ]] marker.
  def self.has_placeholders?(docx_path)
    Zip::File.open(docx_path) do |zip|
      entry = zip.find_entry("word/document.xml")
      return false unless entry

      doc = Nokogiri::XML(entry.get_input_stream.read)
      doc.xpath("//w:r/w:t", W_NS).any? { |t| t.text.include?("[[") }
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

  # Returns filled .docx bytes. Every file in the uploaded zip is carried over verbatim
  # except word/document.xml, which has its placeholder paragraphs replaced.
  def generate(style_docx_path)
    Zip::File.open(style_docx_path) do |zip|
      Zip::OutputStream.write_buffer do |out|
        zip.each do |entry|
          out.put_next_entry(entry.name)
          if entry.name == "word/document.xml"
            out.write(process_document_xml(entry.get_input_stream.read))
          else
            out.write(zip.read(entry.name))
          end
        end
      end.string
    end
  end

  private

  def process_document_xml(xml_str)
    doc = Nokogiri::XML(xml_str)

    # Snapshot the NodeSet first — modifying the tree mid-iteration causes missed nodes.
    doc.xpath("//w:body//w:p", W_NS).to_a.each do |para|
      # Join all runs in the paragraph to catch placeholders fragmented across runs.
      full_text = para.xpath(".//w:r/w:t", W_NS).map(&:text).join
      next unless full_text.include?("[[")

      m = full_text.match(PLACEHOLDER_RE)
      next unless m

      key         = m[1].strip.downcase
      replacement = resolve_word_xml(key, para)
      next unless replacement

      # doc.fragment parses in the document's namespace context, avoiding duplicate declarations.
      para.replace(doc.fragment(replacement))
    end

    doc.to_xml(encoding: "UTF-8")
  end

  def resolve_word_xml(key, context_para)
    case key
    when "company name"             then simple_para_xml(context_para, @portco.to_s)
    when "fund name", "report name" then simple_para_xml(context_para, @template.portfolio_report.name)
    when "template name"            then simple_para_xml(context_para, @template.name)
    when "period"                   then simple_para_xml(context_para, period_label)
    when "prepared date"            then simple_para_xml(context_para, Time.zone.today.strftime("%d %b %Y"))
    when /\Asection:\s*(.+)\z/i     then section_paras_xml(::Regexp.last_match(1).strip)
    when "all sections"             then all_sections_xml
    when "kpi table"                then kpi_table_word_xml
    end
  end

  # Preserves the placeholder paragraph's own paragraph/run style so the resolved text
  # inherits font, size, colour, and alignment the user set on the placeholder.
  def simple_para_xml(context_para, text)
    pPr = context_para.at_xpath("w:pPr", W_NS)&.to_xml(save_with: 0) || ""
    rPr = context_para.at_xpath(".//w:r/w:rPr", W_NS)&.to_xml(save_with: 0) || ""
    "<w:p>#{pPr}<w:r>#{rPr}" \
      "<w:t xml:space=\"preserve\">#{CGI.escapeHTML(text)}</w:t></w:r></w:p>"
  end

  # Resolves [[ section: Name ]] — fuzzy match on section name.
  def section_paras_xml(name)
    section = @sections.find do |s|
      s.name.casecmp?(name) || s.name.downcase.include?(name.downcase)
    end
    return nil unless section

    bullets_to_paras(extract_bullets(@draft.narrative_for(section.id)))
  end

  def all_sections_xml
    @sections.map do |section|
      heading = "<w:p><w:pPr><w:pStyle w:val=\"Heading2\"/></w:pPr>" \
                "<w:r><w:t>#{CGI.escapeHTML(section.name)}</w:t></w:r></w:p>"
      heading + bullets_to_paras(extract_bullets(@draft.narrative_for(section.id)))
    end.join
  end

  def bullets_to_paras(bullets)
    bullets.map do |b|
      "<w:p><w:pPr><w:pStyle w:val=\"ListBullet\"/></w:pPr>" \
        "<w:r><w:t xml:space=\"preserve\">#{CGI.escapeHTML(b)}</w:t></w:r></w:p>"
    end.join
  end

  # Generates an OOXML <w:tbl> — column widths in twips (1 twip = 1/1440 inch).
  # 9000 twips ≈ 6.25" which fits a standard letter or A4 text column.
  def kpi_table_word_xml
    return nil unless @mappings.any? && @period_labels.any?

    total_w  = 9000
    metric_w = (total_w * 0.38).to_i
    period_w = ((total_w - metric_w) / @period_labels.length).to_i

    grid = "<w:gridCol w:w=\"#{metric_w}\"/>" +
           @period_labels.map { "<w:gridCol w:w=\"#{period_w}\"/>" }.join

    header_cells =
      word_tc("Metric", fill: "1A3C6E", color: "FFFFFF", bold: true, w: metric_w) +
      @period_labels.map { |l|
        word_tc(l, fill: "1A3C6E", color: "FFFFFF", bold: true, w: period_w, align: "right")
      }.join

    data_rows = @mappings.each_with_index.map do |ikm, idx|
      fill  = idx.even? ? "EEF2F8" : "FFFFFF"
      cells = word_tc(ikm.reported_kpi_name, fill: fill, color: "1A1A1A", bold: false, w: metric_w)
      cells += @period_labels.map do |lbl|
        val = @draft.effective_kpi_table.dig(ikm.id.to_s, lbl)&.to_s || "—"
        word_tc(val, fill: fill, color: "1A1A1A", bold: false, w: period_w, align: "right")
      end.join
      "<w:tr>#{cells}</w:tr>"
    end.join

    <<~XML
      <w:tbl>
        <w:tblPr>
          <w:tblStyle w:val="TableGrid"/>
          <w:tblW w:w="0" w:type="auto"/>
        </w:tblPr>
        <w:tblGrid>#{grid}</w:tblGrid>
        <w:tr>#{header_cells}</w:tr>
        #{data_rows}
      </w:tbl>
    XML
  end

  def word_tc(text, fill:, color:, bold:, w:, align: "left")
    jc = align == "right" ? "<w:jc w:val=\"right\"/>" : ""
    <<~XML
      <w:tc>
        <w:tcPr>
          <w:tcW w:w="#{w}" w:type="dxa"/>
          <w:shd w:val="clear" w:color="auto" w:fill="#{fill}"/>
        </w:tcPr>
        <w:p>
          <w:pPr>#{jc}</w:pPr>
          <w:r>
            <w:rPr>
              #{'<w:b/>' if bold}
              <w:color w:val="#{color}"/>
              <w:sz w:val="20"/><w:szCs w:val="20"/>
            </w:rPr>
            <w:t xml:space="preserve">#{CGI.escapeHTML(text)}</w:t>
          </w:r>
        </w:p>
      </w:tc>
    XML
  end

  def period_label
    "#{@draft.start_date.strftime('%b %Y')} – #{@draft.end_date.strftime('%b %Y')}"
  end

  def extract_bullets(html)
    return ["No content generated."] if html.blank?

    doc     = Nokogiri::HTML.fragment(html)
    bullets = doc.css("li").map { |li| li.text.strip }.reject(&:empty?)
    bullets = doc.css("p").map  { |p|  p.text.strip  }.reject(&:empty?) if bullets.empty?
    bullets = html.split("\n").map(&:strip).reject(&:empty?) if bullets.empty?
    bullets.presence || ["No content generated."]
  end

  def ordered_sections
    all = @draft.portfolio_report.portfolio_report_sections.index_by(&:id)
    @template.ordered_section_ids.filter_map { |id| all[id] }
  end
end
