require 'cgi'
require 'zip'
require 'nokogiri'

# Business-friendly pastel PPTX variant.
#
# Design:
#   Cover   — white slide with a soft light-blue upper band, vivid accent stripe,
#             large company name, report name and period metadata.
#   TOC     — numbered contents list with per-item coloured numbers.
#   KPI     — clean table: pastel-blue header, alternating very-light rows, soft borders.
#   Sections — one slide each; thin top accent stripe and coloured bullet dots;
#              accent colour rotates through a pastel set for visual variety.
#
# Activation: set branding["ppt_theme"] = "pastel" on the PortfolioReportTemplate.
# The export job calls template.ppt_service_class which returns this class.
class PortfolioReportPastelPptService
  # ── Canvas ─────────────────────────────────────────────────────────────────
  SLIDE_W = 12_192_000
  SLIDE_H = 6_858_000
  MARGIN = 685_800 # 0.75" side margin
  CONTENT_W = SLIDE_W - (MARGIN * 2) # 10_820_400

  # ── Colour palette ─────────────────────────────────────────────────────────
  WHITE        = "FFFFFF".freeze
  COVER_BAND   = "EFF6FF".freeze   # very-light blue — upper cover band
  SLIDE_BG     = "FFFFFF".freeze
  TITLE_BG     = "F8FAFC".freeze   # near-white title strip
  DIVIDER_CLR  = "E2E8F0".freeze   # horizontal rule under title
  TBL_HDR_BG   = "DBEAFE".freeze   # pastel blue — KPI table header fill
  TBL_HDR_TXT  = "1E3A8A".freeze   # dark navy — KPI table header text
  ROW_EVEN     = "F1F5F9".freeze   # very light slate — alternating rows
  ROW_ODD      = "FFFFFF".freeze
  CELL_BORDER  = "CBD5E1".freeze
  HEADING_CLR  = "1E293B".freeze   # dark slate
  BODY_CLR     = "334155".freeze   # medium slate
  CAPTION_CLR  = "94A3B8".freeze   # light slate — footer / meta

  # Rotating accent colours (used for top stripe + bullets, one per section)
  ACCENTS = %w[3B82F6 10B981 8B5CF6 F59E0B EF4444 06B6D4 EC4899 84CC16].freeze

  # ── Layout (EMU) ────────────────────────────────────────────────────────────
  # Cover
  COVER_BAND_H   = 2_400_000
  COVER_STRIPE_H = 57_150 # vivid line at base of upper band

  # Content slides
  STRIPE_H   =   114_300   # thin top accent stripe (0.125")
  TITLE_BG_H =   971_550   # title band height  (~1.06")
  RULE_H = 28_575 # divider below title
  RULE_Y     = STRIPE_H + TITLE_BG_H                   # 1_085_850
  CONTENT_Y  = RULE_Y + RULE_H + 114_300               # 1_228_725
  FOOTER_H = 285_750
  FOOTER_Y   = SLIDE_H - FOOTER_H                      # 6_572_250
  CONTENT_H  = FOOTER_Y - CONTENT_Y - 57_150           # ~5_286_375

  def initialize(draft, theme_overrides: {})
    @draft         = draft
    @portco        = draft.portfolio_company
    @template      = draft.portfolio_report_template
    @sections      = ordered_sections
    @mappings      = InvestorKpiMapping
                     .where(id: Array(draft.selected_kpi_mapping_ids).map(&:to_i))
                     .order(:position)
    @period_labels = draft.effective_kpi_table.values.first&.keys || []
    @shape_id      = 200
    @overrides     = theme_overrides
  end

  # Returns raw .pptx bytes.
  def generate
    Zip::OutputStream.write_buffer do |zip|
      slides = build_slides
      write_content_types(zip, slides.length)
      write_top_rels(zip)
      write_presentation(zip, slides.length)
      write_presentation_rels(zip, slides.length)
      write_theme(zip)
      write_slide_master(zip)
      write_slide_master_rels(zip)
      write_slide_layout(zip, 1)
      write_slide_layout_rels(zip, 1)
      slides.each_with_index do |xml, i|
        n = i + 1
        zip.put_next_entry("ppt/slides/slide#{n}.xml")
        zip.write(xml)
        zip.put_next_entry("ppt/slides/_rels/slide#{n}.xml.rels")
        zip.write(slide_rels)
      end
    end.string
  end

  private

  # ── Slide builders ──────────────────────────────────────────────────────────

  def build_slides
    slides = [cover_slide, toc_slide]
    slides << kpi_slide if @mappings.any? && @period_labels.any?
    @sections.each_with_index { |s, i| slides << section_slide(s, i) }
    slides
  end

  def cover_slide
    period = "#{@draft.start_date.strftime('%b %Y')} – #{@draft.end_date.strftime('%b %Y')}"
    meta   = "#{@draft.kpi_period_type} · #{@draft.kpi_tag} · #{@draft.n_periods} periods"

    slide_xml do
      # White background
      filled_rect(0, 0, SLIDE_W, SLIDE_H, WHITE) +
        # Soft blue upper band
        filled_rect(0, 0, SLIDE_W, COVER_BAND_H, COVER_BAND) +
        # Vivid accent stripe at the base of the band — uses brand override if set
        filled_rect(0, COVER_BAND_H, SLIDE_W, COVER_STRIPE_H, accent_for(0)) +
        # Report / template name — centred in the upper band
        text_box(e(@template.portfolio_report.name),
                 x: MARGIN, y: (COVER_BAND_H - 700_000) / 2, w: CONTENT_W, h: 700_000,
                 size: 2200, bold: true, color: HEADING_CLR, align: "l", valign: "ctr") +
        # Company name — large, below the band
        text_box(e(@portco.to_s),
                 x: MARGIN, y: COVER_BAND_H + COVER_STRIPE_H + 228_600,
                 w: CONTENT_W, h: 1_371_600,
                 size: 5200, bold: true, color: HEADING_CLR, align: "l", valign: "t") +
        # Period
        text_box(e(period),
                 x: MARGIN, y: COVER_BAND_H + COVER_STRIPE_H + 1_714_500,
                 w: CONTENT_W, h: 400_000,
                 size: 1800, bold: false, color: BODY_CLR, align: "l", valign: "t") +
        # Meta (period type / tag / count)
        text_box(e(meta),
                 x: MARGIN, y: COVER_BAND_H + COVER_STRIPE_H + 2_171_700,
                 w: CONTENT_W, h: 342_900,
                 size: 1300, bold: false, color: CAPTION_CLR, align: "l", valign: "t") +
        # Prepared date — bottom right
        text_box(e("Prepared #{Time.zone.today.strftime('%d %b %Y')}"),
                 x: MARGIN, y: SLIDE_H - 400_000, w: CONTENT_W, h: 342_900,
                 size: 1000, bold: false, color: CAPTION_CLR, align: "r", valign: "t")
    end
  end

  def toc_slide
    items = @sections.map { |s| e(s.name) }
    items.unshift(e("KPI Data")) if @mappings.any?

    slide_xml do
      content_slide_chrome(e("Contents"), accent_for(0)) +
        numbered_list(items,
                      x: MARGIN, y: CONTENT_Y, w: CONTENT_W, h: CONTENT_H,
                      size: 1900, color: BODY_CLR, accent: accent_for(0)) +
        slide_footer
    end
  end

  def kpi_slide
    slide_xml do
      content_slide_chrome(e("KPI Data"), accent_for(1)) +
        kpi_table +
        slide_footer
    end
  end

  def section_slide(section, idx)
    accent    = accent_for(idx)
    narrative = @draft.narrative_for(section.id)
    bullets   = extract_bullets(narrative)

    slide_xml do
      content_slide_chrome(e(section.name), accent) +
        bullet_list(bullets.map { |b| e(b) },
                    x: MARGIN, y: CONTENT_Y, w: CONTENT_W, h: CONTENT_H,
                    size: 1700, color: BODY_CLR, accent: accent) +
        slide_footer
    end
  end

  # ── Composite chrome helpers ─────────────────────────────────────────────────

  # Thin top stripe + light title band + divider rule
  def content_slide_chrome(title_text, accent_color)
    filled_rect(0, 0, SLIDE_W, SLIDE_H, SLIDE_BG) +
      filled_rect(0, 0, SLIDE_W, STRIPE_H, accent_color) +
      filled_rect(0, STRIPE_H, SLIDE_W, TITLE_BG_H, TITLE_BG) +
      text_box(title_text,
               x: MARGIN, y: STRIPE_H, w: CONTENT_W, h: TITLE_BG_H,
               size: 2800, bold: true, color: HEADING_CLR, align: "l", valign: "ctr") +
      filled_rect(MARGIN, RULE_Y, CONTENT_W, RULE_H, DIVIDER_CLR)
  end

  def slide_footer
    text_box(e(@portco.to_s),
             x: MARGIN, y: FOOTER_Y + 57_150, w: CONTENT_W, h: FOOTER_H,
             size: 900, bold: false, color: CAPTION_CLR, align: "l", valign: "t")
  end

  # ── Shape primitives ─────────────────────────────────────────────────────────

  def filled_rect(x, y, w, h, color)
    id = @shape_id += 1
    <<~XML
      <p:sp>
        <p:nvSpPr>
          <p:cNvPr id="#{id}" name="rect_#{id}"/>
          <p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>
          <p:nvPr/>
        </p:nvSpPr>
        <p:spPr>
          <a:xfrm><a:off x="#{x}" y="#{y}"/><a:ext cx="#{w}" cy="#{h}"/></a:xfrm>
          <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
          <a:solidFill><a:srgbClr val="#{color}"/></a:solidFill>
          <a:ln><a:noFill/></a:ln>
        </p:spPr>
        <p:txBody><a:bodyPr/><a:lstStyle/><a:p/></p:txBody>
      </p:sp>
    XML
  end

  def text_box(text, x:, y:, w:, h:, size: 1800, bold: false,
               color: HEADING_CLR, align: "l", valign: "ctr")
    id = @shape_id += 1
    <<~XML
      <p:sp>
        <p:nvSpPr>
          <p:cNvPr id="#{id}" name="txt_#{id}"/>
          <p:cNvSpPr txBox="1"/>
          <p:nvPr/>
        </p:nvSpPr>
        <p:spPr>
          <a:xfrm><a:off x="#{x}" y="#{y}"/><a:ext cx="#{w}" cy="#{h}"/></a:xfrm>
          <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
          <a:noFill/>
          <a:ln><a:noFill/></a:ln>
        </p:spPr>
        <p:txBody>
          <a:bodyPr anchor="#{valign}" wrap="square"><a:normAutofit/></a:bodyPr>
          <a:lstStyle/>
          <a:p>
            <a:pPr algn="#{align}"/>
            <a:r>
              <a:rPr lang="en-US" sz="#{size}" b="#{bold ? 1 : 0}" dirty="0">
                <a:solidFill><a:srgbClr val="#{color}"/></a:solidFill>
              </a:rPr>
              <a:t>#{text}</a:t>
            </a:r>
          </a:p>
        </p:txBody>
      </p:sp>
    XML
  end

  # Numbered list — accented bold numbers, plain body text, hanging indent
  def numbered_list(items, x:, y:, w:, h:, size: 1900, color: BODY_CLR, accent: ACCENTS[0])
    id    = @shape_id += 1
    paras = items.each_with_index.map do |item, i|
      spc = i.positive? ? "<a:spcBef><a:spcPts val=\"280\"/></a:spcBef>" : ""
      <<~PARA
        <a:p>
          <a:pPr marL="457200" indent="-457200">
            #{spc}
          </a:pPr>
          <a:r>
            <a:rPr lang="en-US" sz="#{size}" b="1" dirty="0">
              <a:solidFill><a:srgbClr val="#{accent}"/></a:solidFill>
            </a:rPr>
            <a:t>#{i + 1}.  </a:t>
          </a:r>
          <a:r>
            <a:rPr lang="en-US" sz="#{size}" b="0" dirty="0">
              <a:solidFill><a:srgbClr val="#{color}"/></a:solidFill>
            </a:rPr>
            <a:t>#{item}</a:t>
          </a:r>
        </a:p>
      PARA
    end.join
    text_run_box(id, x, y, w, h, paras)
  end

  # Coloured bullet list — filled-circle bullets in accent colour
  def bullet_list(lines, x:, y:, w:, h:, size: 1700, color: BODY_CLR, accent: ACCENTS[0])
    id    = @shape_id += 1
    paras = lines.each_with_index.map do |line, i|
      spc = i.positive? ? "<a:spcBef><a:spcPts val=\"180\"/></a:spcBef>" : ""
      <<~PARA
        <a:p>
          <a:pPr marL="342900" indent="-342900">
            #{spc}
            <a:buClr><a:srgbClr val="#{accent}"/></a:buClr>
            <a:buChar char="●"/>
          </a:pPr>
          <a:r>
            <a:rPr lang="en-US" sz="#{size}" b="0" dirty="0">
              <a:solidFill><a:srgbClr val="#{color}"/></a:solidFill>
            </a:rPr>
            <a:t>#{line}</a:t>
          </a:r>
        </a:p>
      PARA
    end.join
    if paras.empty?
      paras = "<a:p><a:r><a:rPr lang=\"en-US\" sz=\"#{size}\" dirty=\"0\"><a:solidFill>" \
              "<a:srgbClr val=\"#{CAPTION_CLR}\"/></a:solidFill></a:rPr>" \
              "<a:t>No content generated.</a:t></a:r></a:p>"
    end
    text_run_box(id, x, y, w, h, paras)
  end

  def text_run_box(id, x, y, w, h, paras_xml)
    <<~XML
      <p:sp>
        <p:nvSpPr>
          <p:cNvPr id="#{id}" name="list_#{id}"/>
          <p:cNvSpPr txBox="1"/>
          <p:nvPr/>
        </p:nvSpPr>
        <p:spPr>
          <a:xfrm><a:off x="#{x}" y="#{y}"/><a:ext cx="#{w}" cy="#{h}"/></a:xfrm>
          <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
          <a:noFill/>
          <a:ln><a:noFill/></a:ln>
        </p:spPr>
        <p:txBody>
          <a:bodyPr anchor="t" wrap="square"><a:normAutofit/></a:bodyPr>
          <a:lstStyle/>
          #{paras_xml}
        </p:txBody>
      </p:sp>
    XML
  end

  # ── KPI table ───────────────────────────────────────────────────────────────

  def kpi_table
    id           = @shape_id += 1
    row_h        = 400_000
    metric_col_w = (CONTENT_W * 0.38).to_i
    period_col_w = ((CONTENT_W - metric_col_w) / [@period_labels.length, 1].max).to_i

    header_row =
      kpi_cell(e("Metric"), fill: TBL_HDR_BG, color: TBL_HDR_TXT,
                            bold: true, w: metric_col_w, h: row_h, align: "l") +
      @period_labels.map { |l|
        kpi_cell(e(l), fill: TBL_HDR_BG, color: TBL_HDR_TXT,
                       bold: true, w: period_col_w, h: row_h, align: "r")
      }.join

    data_rows = @mappings.each_with_index.map do |ikm, row_idx|
      fill = row_idx.even? ? ROW_EVEN : ROW_ODD
      name_cell = kpi_cell(e(ikm.reported_kpi_name), fill: fill, color: HEADING_CLR,
                                                     bold: false, w: metric_col_w, h: row_h, align: "l")
      val_cells = @period_labels.map do |lbl|
        val = @draft.effective_kpi_table.dig(ikm.id.to_s, lbl)&.to_s || "—"
        kpi_cell(e(val), fill: fill, color: BODY_CLR, bold: false,
                         w: period_col_w, h: row_h, align: "r")
      end.join
      "<a:tr h=\"#{row_h}\">#{name_cell}#{val_cells}</a:tr>"
    end.join

    grid_cols = "<a:gridCol w=\"#{metric_col_w}\"/>" +
                @period_labels.map { "<a:gridCol w=\"#{period_col_w}\"/>" }.join

    <<~XML
      <p:graphicFrame>
        <p:nvGraphicFramePr>
          <p:cNvPr id="#{id}" name="KpiTable_#{id}"/>
          <p:cNvGraphicFramePr><a:graphicFrameLocks noGrp="1"/></p:cNvGraphicFramePr>
          <p:nvPr/>
        </p:nvGraphicFramePr>
        <p:xfrm>
          <a:off x="#{MARGIN}" y="#{CONTENT_Y}"/>
          <a:ext cx="#{CONTENT_W}" cy="#{CONTENT_H}"/>
        </p:xfrm>
        <a:graphic>
          <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table">
            <a:tbl>
              <a:tblPr firstRow="1" bandRow="1">
                <a:solidFill><a:srgbClr val="#{WHITE}"/></a:solidFill>
              </a:tblPr>
              <a:tblGrid>#{grid_cols}</a:tblGrid>
              <a:tr h="#{row_h}">#{header_row}</a:tr>
              #{data_rows}
            </a:tbl>
          </a:graphicData>
        </a:graphic>
      </p:graphicFrame>
    XML
  end

  def kpi_cell(text, fill:, color:, bold:, w:, h:, align: "l")
    <<~XML
      <a:tc>
        <a:txBody>
          <a:bodyPr/>
          <a:lstStyle/>
          <a:p>
            <a:pPr algn="#{align}"/>
            <a:r>
              <a:rPr lang="en-US" sz="1200" b="#{bold ? 1 : 0}" dirty="0">
                <a:solidFill><a:srgbClr val="#{color}"/></a:solidFill>
              </a:rPr>
              <a:t>#{text}</a:t>
            </a:r>
          </a:p>
        </a:txBody>
        <a:tcPr>
          <a:solidFill><a:srgbClr val="#{fill}"/></a:solidFill>
          <a:lnL w="9525"><a:solidFill><a:srgbClr val="#{CELL_BORDER}"/></a:solidFill></a:lnL>
          <a:lnR w="9525"><a:solidFill><a:srgbClr val="#{CELL_BORDER}"/></a:solidFill></a:lnR>
          <a:lnT w="9525"><a:solidFill><a:srgbClr val="#{CELL_BORDER}"/></a:solidFill></a:lnT>
          <a:lnB w="9525"><a:solidFill><a:srgbClr val="#{CELL_BORDER}"/></a:solidFill></a:lnB>
        </a:tcPr>
      </a:tc>
    XML
  end

  # ── Utilities ────────────────────────────────────────────────────────────────

  # When an accent1 override is present (from uploaded style reference), apply it
  # uniformly so the deck is fully on-brand. Without an override the palette rotates.
  def accent_for(idx)
    @overrides[:accent1] || ACCENTS[idx % ACCENTS.length]
  end

  def ordered_sections
    all = @draft.portfolio_report.portfolio_report_sections.index_by(&:id)
    @template.ordered_section_ids.filter_map { |id| all[id] }
  end

  def extract_bullets(html)
    return ["No content generated."] if html.blank?

    doc     = Nokogiri::HTML.fragment(html)
    bullets = doc.css("li").map { |li| li.text.strip }.reject(&:empty?)
    bullets = doc.css("p").map  { |p|  p.text.strip  }.reject(&:empty?) if bullets.empty?
    bullets = html.split("\n").map(&:strip).reject(&:empty?) if bullets.empty?
    bullets.presence || ["No content generated."]
  end

  def e(text) = CGI.escapeHTML(text.to_s)

  # ── Slide XML wrapper ────────────────────────────────────────────────────────

  def slide_xml(&block)
    content = block ? yield : ""
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
             xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
             xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <p:cSld>
          <p:spTree>
            <p:nvGrpSpPr>
              <p:cNvPr id="1" name=""/>
              <p:cNvGrpSpPr><a:grpSpLocks noGrp="1"/></p:cNvGrpSpPr>
              <p:nvPr/>
            </p:nvGrpSpPr>
            <p:grpSpPr>
              <a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></a:xfrm>
            </p:grpSpPr>
            #{content}
          </p:spTree>
        </p:cSld>
      </p:sld>
    XML
  end

  # ── PPTX structural files ─────────────────────────────────────────────────────

  def write_content_types(zip, n)
    entries = (1..n).map do |i|
      "<Override PartName=\"/ppt/slides/slide#{i}.xml\" " \
        "ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/>"
    end.join("\n    ")
    zip.put_next_entry("[Content_Types].xml")
    zip.write(<<~XML)
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml"  ContentType="application/xml"/>
        <Override PartName="/ppt/presentation.xml"
                  ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
        <Override PartName="/ppt/theme/theme1.xml"
                  ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>
        <Override PartName="/ppt/slideMasters/slideMaster1.xml"
                  ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>
        <Override PartName="/ppt/slideLayouts/slideLayout1.xml"
                  ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>
        #{entries}
      </Types>
    XML
  end

  def write_top_rels(zip)
    zip.put_next_entry("_rels/.rels")
    zip.write(<<~XML)
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1"
          Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
          Target="ppt/presentation.xml"/>
      </Relationships>
    XML
  end

  def write_presentation(zip, n)
    slide_ids = (1..n).map.with_index(256) do |i, id|
      "<p:sldId id=\"#{id}\" r:id=\"rId#{i + 2}\"/>"
    end.join("\n    ")
    zip.put_next_entry("ppt/presentation.xml")
    zip.write(<<~XML)
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
                      xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
                      xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>
        <p:sldIdLst>#{slide_ids}</p:sldIdLst>
        <p:sldSz cx="#{SLIDE_W}" cy="#{SLIDE_H}" type="custom"/>
        <p:notesSz cx="6858000" cy="9144000"/>
      </p:presentation>
    XML
  end

  def write_presentation_rels(zip, n)
    entries = (1..n).map do |i|
      "<Relationship Id=\"rId#{i + 2}\" " \
        "Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" " \
        "Target=\"slides/slide#{i}.xml\"/>"
    end.join("\n    ")
    zip.put_next_entry("ppt/_rels/presentation.xml.rels")
    zip.write(<<~XML)
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>
        #{entries}
      </Relationships>
    XML
  end

  def write_theme(zip)
    zip.put_next_entry("ppt/theme/theme1.xml")
    # If a style-reference PPTX was uploaded, inject its theme verbatim so PowerPoint
    # sees the exact brand palette (fonts, shadows, etc.) from the reference file.
    return zip.write(@overrides[:theme_xml]) if @overrides[:theme_xml]

    zip.write(<<~XML)
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="PastelBusiness">
        <a:themeElements>
          <a:clrScheme name="PastelBusiness">
            <a:dk1><a:srgbClr val="1E293B"/></a:dk1>
            <a:lt1><a:srgbClr val="FFFFFF"/></a:lt1>
            <a:dk2><a:srgbClr val="334155"/></a:dk2>
            <a:lt2><a:srgbClr val="F8FAFC"/></a:lt2>
            <a:accent1><a:srgbClr val="3B82F6"/></a:accent1>
            <a:accent2><a:srgbClr val="10B981"/></a:accent2>
            <a:accent3><a:srgbClr val="8B5CF6"/></a:accent3>
            <a:accent4><a:srgbClr val="F59E0B"/></a:accent4>
            <a:accent5><a:srgbClr val="EF4444"/></a:accent5>
            <a:accent6><a:srgbClr val="06B6D4"/></a:accent6>
            <a:hlink><a:srgbClr val="3B82F6"/></a:hlink>
            <a:folHlink><a:srgbClr val="8B5CF6"/></a:folHlink>
          </a:clrScheme>
          <a:fontScheme name="PastelBusiness">
            <a:majorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>
            <a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont>
          </a:fontScheme>
          <a:fmtScheme name="PastelBusiness">
            <a:fillStyleLst>
              <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
              <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
              <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
            </a:fillStyleLst>
            <a:lnStyleLst>
              <a:ln w="6350"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>
              <a:ln w="12700"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>
              <a:ln w="19050"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>
            </a:lnStyleLst>
            <a:effectStyleLst>
              <a:effectStyle><a:effectLst/></a:effectStyle>
              <a:effectStyle><a:effectLst/></a:effectStyle>
              <a:effectStyle><a:effectLst/></a:effectStyle>
            </a:effectStyleLst>
            <a:bgFillStyleLst>
              <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
              <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
              <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
            </a:bgFillStyleLst>
          </a:fmtScheme>
        </a:themeElements>
      </a:theme>
    XML
  end

  def write_slide_master(zip)
    zip.put_next_entry("ppt/slideMasters/slideMaster1.xml")
    zip.write(<<~XML)
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <p:sldMaster xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
                   xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
                   xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <p:cSld>
          <p:bg><p:bgPr><a:solidFill><a:srgbClr val="FFFFFF"/></a:solidFill></p:bgPr></p:bg>
          <p:spTree>
            <p:nvGrpSpPr>
              <p:cNvPr id="1" name=""/>
              <p:cNvGrpSpPr/>
              <p:nvPr/>
            </p:nvGrpSpPr>
            <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></a:xfrm></p:grpSpPr>
          </p:spTree>
        </p:cSld>
        <p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>
        <p:txStyles>
          <p:titleStyle><a:lstStyle/></p:titleStyle>
          <p:bodyStyle><a:lstStyle/></p:bodyStyle>
          <p:otherStyle><a:lstStyle/></p:otherStyle>
        </p:txStyles>
      </p:sldMaster>
    XML
  end

  def write_slide_master_rels(zip)
    zip.put_next_entry("ppt/slideMasters/_rels/slideMaster1.xml.rels")
    zip.write(<<~XML)
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/>
      </Relationships>
    XML
  end

  def write_slide_layout(zip, n)
    zip.put_next_entry("ppt/slideLayouts/slideLayout#{n}.xml")
    zip.write(<<~XML)
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <p:sldLayout xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
                   xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
                   xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
                   type="blank" preserve="1">
        <p:cSld name="Blank">
          <p:spTree>
            <p:nvGrpSpPr>
              <p:cNvPr id="1" name=""/>
              <p:cNvGrpSpPr/>
              <p:nvPr/>
            </p:nvGrpSpPr>
            <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></a:xfrm></p:grpSpPr>
          </p:spTree>
        </p:cSld>
      </p:sldLayout>
    XML
  end

  def write_slide_layout_rels(zip, n)
    zip.put_next_entry("ppt/slideLayouts/_rels/slideLayout#{n}.xml.rels")
    zip.write(<<~XML)
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>
      </Relationships>
    XML
  end

  def slide_rels
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
      </Relationships>
    XML
  end
end
