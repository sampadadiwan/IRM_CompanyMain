require 'cgi'
require 'zip'
require 'nokogiri'

# Generates a .pptx file from a PortfolioReportDraft.
# Produces a multi-slide deck:
#   Slide 1  — Cover (company name, report title, period)
#   Slide 2  — Table of contents
#   Slide 3  — KPI data table (if any KPI mappings exist)
#   Slide N+ — One slide per section (header bar + bullet list)
#
# All positioning uses EMUs (1 inch = 914_400 EMUs).
class PortfolioReportPptService
  # ── Canvas ────────────────────────────────────────────────────────────────
  SLIDE_W = 12_192_000   # 13.33" widescreen
  SLIDE_H  =  6_858_000  # 7.5"
  MARGIN   =    457_200  # 0.5"
  CONTENT_W = SLIDE_W - MARGIN * 2
  HEADER_H  =    914_400  # 1" header bar

  # ── Brand palette (hex without #) ─────────────────────────────────────────
  NAVY  = "1A3C6E"
  BLUE  = "2563EB"
  WHITE = "FFFFFF"
  DARK  = "1A1A1A"
  GRAY  = "6B7280"
  LIGHT = "EEF2F8"

  def initialize(draft, theme_overrides: {})
    @draft     = draft
    @portco    = draft.portfolio_company
    @template  = draft.portfolio_report_template
    @sections  = ordered_sections
    @mappings  = InvestorKpiMapping
                   .where(id: Array(draft.selected_kpi_mapping_ids).map(&:to_i))
                   .order(:position)
    @period_labels = draft.effective_kpi_table.values.first&.keys || []
    @overrides = theme_overrides
  end

  # Returns the raw .pptx bytes as a String.
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

  # ── Slide builders ────────────────────────────────────────────────────────

  def build_slides
    slides = []
    slides << cover_slide
    slides << toc_slide
    slides << kpi_slide if @mappings.any? && @period_labels.any?
    @sections.each { |s| slides << section_slide(s) }
    slides
  end

  def cover_slide
    period = "#{@draft.kpi_period_type} #{@draft.kpi_tag} · " \
             "#{@draft.start_date.strftime('%b %Y')} – #{@draft.end_date.strftime('%b %Y')} · " \
             "#{@draft.n_periods} periods"
    slide_xml do
      background(NAVY) +
      text_box(e(@portco.to_s), x: MARGIN, y: 1_371_600, w: CONTENT_W, h: 1_371_600,
               size: 4000, bold: true, color: WHITE, align: "ctr") +
      text_box(e(@template.portfolio_report.name), x: MARGIN, y: 2_895_000, w: CONTENT_W, h: 685_800,
               size: 2400, bold: false, color: "93C5FD", align: "ctr") +
      text_box(e(period), x: MARGIN, y: 3_657_600, w: CONTENT_W, h: 457_200,
               size: 1400, bold: false, color: "BFDBFE", align: "ctr") +
      text_box(e("Prepared #{Date.today.strftime('%d %b %Y')}"),
               x: MARGIN, y: SLIDE_H - MARGIN - 342_900, w: CONTENT_W, h: 342_900,
               size: 1000, bold: false, color: "93C5FD", align: "ctr")
    end
  end

  def toc_slide
    section_bullets = @sections.map { |s| e(s.name) }
    section_bullets.unshift(e("KPI Data")) if @mappings.any?

    slide_xml do
      header_bar(e("Contents")) +
      bullet_text_box(section_bullets,
                      x: MARGIN, y: HEADER_H + MARGIN,
                      w: CONTENT_W, h: SLIDE_H - HEADER_H - MARGIN * 2,
                      size: 2000)
    end
  end

  def kpi_slide
    slide_xml do
      header_bar(e("KPI Data")) +
      kpi_table
    end
  end

  def section_slide(section)
    narrative = @draft.narrative_for(section.id)
    bullets   = extract_bullets(narrative)

    slide_xml do
      header_bar(e(section.name)) +
      bullet_text_box(bullets.map { |b| e(b) },
                      x: MARGIN, y: HEADER_H + MARGIN,
                      w: CONTENT_W, h: SLIDE_H - HEADER_H - MARGIN * 2,
                      size: 1600)
    end
  end

  # ── Slide XML helpers ─────────────────────────────────────────────────────

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

  # Full-slide background fill
  def background(color)
    <<~XML
      <p:sp>
        <p:nvSpPr>
          <p:cNvPr id="2" name="bg"/>
          <p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>
          <p:nvPr/>
        </p:nvSpPr>
        <p:spPr>
          <a:xfrm><a:off x="0" y="0"/><a:ext cx="#{SLIDE_W}" cy="#{SLIDE_H}"/></a:xfrm>
          <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
          <a:solidFill><a:srgbClr val="#{color}"/></a:solidFill>
          <a:ln><a:noFill/></a:ln>
        </p:spPr>
        <p:txBody><a:bodyPr/><a:lstStyle/><a:p/></p:txBody>
      </p:sp>
    XML
  end

  # Header bar spanning full width — uses brand override color when a style ref is uploaded.
  def header_bar(title_text)
    bar_color = @overrides[:accent1] || NAVY
    bar = <<~XML
      <p:sp>
        <p:nvSpPr>
          <p:cNvPr id="10" name="header_bar"/>
          <p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>
          <p:nvPr/>
        </p:nvSpPr>
        <p:spPr>
          <a:xfrm><a:off x="0" y="0"/><a:ext cx="#{SLIDE_W}" cy="#{HEADER_H}"/></a:xfrm>
          <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
          <a:solidFill><a:srgbClr val="#{bar_color}"/></a:solidFill>
          <a:ln><a:noFill/></a:ln>
        </p:spPr>
        <p:txBody><a:bodyPr/><a:lstStyle/><a:p/></p:txBody>
      </p:sp>
    XML

    bar + text_box(title_text, x: MARGIN, y: 0, w: CONTENT_W, h: HEADER_H,
                   size: 2800, bold: true, color: WHITE, align: "l", valign: "ctr")
  end

  # Generic text box shape (single paragraph / run)
  def text_box(text, x:, y:, w:, h:, size: 1800, bold: false, color: DARK, align: "l", valign: "ctr")
    @shape_id ||= 20
    @shape_id += 1
    <<~XML
      <p:sp>
        <p:nvSpPr>
          <p:cNvPr id="#{@shape_id}" name="text_#{@shape_id}"/>
          <p:cNvSpPr txBox="1"/>
          <p:nvPr/>
        </p:nvSpPr>
        <p:spPr>
          <a:xfrm><a:off x="#{x}" y="#{y}"/><a:ext cx="#{w}" cy="#{h}"/></a:xfrm>
          <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
          <a:noFill/>
        </p:spPr>
        <p:txBody>
          <a:bodyPr anchor="#{valign}" wrap="square">
            <a:normAutofit/>
          </a:bodyPr>
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

  # Multi-paragraph bullet text box
  def bullet_text_box(lines, x:, y:, w:, h:, size: 1800)
    @shape_id ||= 20
    @shape_id += 1

    paras = lines.map do |line|
      <<~PARA
        <a:p>
          <a:pPr marL="342900" indent="-342900">
            <a:buChar char="•"/>
          </a:pPr>
          <a:r>
            <a:rPr lang="en-US" sz="#{size}" b="0" dirty="0">
              <a:solidFill><a:srgbClr val="#{DARK}"/></a:solidFill>
            </a:rPr>
            <a:t>#{line}</a:t>
          </a:r>
        </a:p>
      PARA
    end.join

    <<~XML
      <p:sp>
        <p:nvSpPr>
          <p:cNvPr id="#{@shape_id}" name="bullets_#{@shape_id}"/>
          <p:cNvSpPr txBox="1"/>
          <p:nvPr/>
        </p:nvSpPr>
        <p:spPr>
          <a:xfrm><a:off x="#{x}" y="#{y}"/><a:ext cx="#{w}" cy="#{h}"/></a:xfrm>
          <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
          <a:noFill/>
        </p:spPr>
        <p:txBody>
          <a:bodyPr anchor="t" wrap="square"><a:normAutofit/></a:bodyPr>
          <a:lstStyle/>
          #{paras.presence || "<a:p><a:r><a:rPr lang=\"en-US\" sz=\"#{size}\" dirty=\"0\"/><a:t>No content.</a:t></a:r></a:p>"}
        </p:txBody>
      </p:sp>
    XML
  end

  # KPI data table as a PPTX graphic frame
  def kpi_table
    @shape_id ||= 20
    @shape_id += 1

    table_top    = HEADER_H + MARGIN
    table_h      = SLIDE_H - table_top - MARGIN
    col_count    = @period_labels.length + 1
    metric_col_w = (CONTENT_W * 0.35).to_i
    period_col_w = ((CONTENT_W - metric_col_w) / [@period_labels.length, 1].max).to_i
    row_h        = 400_000  # per row height

    header_row = table_cell(e("Metric"), fill: NAVY, text_color: WHITE, bold: true,
                             w: metric_col_w, h: row_h) +
                 @period_labels.map { |l|
                   table_cell(e(l), fill: NAVY, text_color: WHITE, bold: true,
                              w: period_col_w, h: row_h)
                 }.join

    data_rows = @mappings.each_with_index.map do |ikm, row_idx|
      fill = row_idx.even? ? LIGHT : WHITE
      cell = table_cell(e(ikm.reported_kpi_name), fill: fill, text_color: DARK, bold: false,
                        w: metric_col_w, h: row_h)
      cells = @period_labels.map do |lbl|
        val = @draft.effective_kpi_table.dig(ikm.id.to_s, lbl)&.to_s || "—"
        table_cell(e(val), fill: fill, text_color: DARK, bold: false,
                   w: period_col_w, h: row_h, align: "r")
      end.join
      "<a:tr h=\"#{row_h}\">#{cell}#{cells}</a:tr>"
    end.join

    grid_cols = "<a:gridCol w=\"#{metric_col_w}\"/>" +
                @period_labels.map { "<a:gridCol w=\"#{period_col_w}\"/>" }.join

    <<~XML
      <p:graphicFrame>
        <p:nvGraphicFramePr>
          <p:cNvPr id="#{@shape_id}" name="KPI Table"/>
          <p:cNvGraphicFramePr><a:graphicFrameLocks noGrp="1"/></p:cNvGraphicFramePr>
          <p:nvPr/>
        </p:nvGraphicFramePr>
        <p:xfrm>
          <a:off x="#{MARGIN}" y="#{table_top}"/>
          <a:ext cx="#{CONTENT_W}" cy="#{table_h}"/>
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

  def table_cell(text, fill:, text_color:, bold:, w:, h:, align: "l")
    <<~XML
      <a:tc>
        <a:txBody>
          <a:bodyPr/>
          <a:lstStyle/>
          <a:p>
            <a:pPr algn="#{align}"/>
            <a:r>
              <a:rPr lang="en-US" sz="1200" b="#{bold ? 1 : 0}" dirty="0">
                <a:solidFill><a:srgbClr val="#{text_color}"/></a:solidFill>
              </a:rPr>
              <a:t>#{text}</a:t>
            </a:r>
          </a:p>
        </a:txBody>
        <a:tcPr>
          <a:solidFill><a:srgbClr val="#{fill}"/></a:solidFill>
        </a:tcPr>
      </a:tc>
    XML
  end

  # ── PPTX structural files ─────────────────────────────────────────────────

  def write_content_types(zip, slide_count)
    slide_entries = (1..slide_count).map do |n|
      "<Override PartName=\"/ppt/slides/slide#{n}.xml\" " \
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
        #{slide_entries}
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

  def write_presentation(zip, slide_count)
    slide_ids = (1..slide_count).map.with_index(256) do |n, id|
      "<p:sldId id=\"#{id}\" r:id=\"rId#{n + 2}\"/>"
    end.join("\n    ")

    zip.put_next_entry("ppt/presentation.xml")
    zip.write(<<~XML)
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
                      xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
                      xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <p:sldMasterIdLst>
          <p:sldMasterId id="2147483648" r:id="rId1"/>
        </p:sldMasterIdLst>
        <p:sldIdLst>
          #{slide_ids}
        </p:sldIdLst>
        <p:sldSz cx="#{SLIDE_W}" cy="#{SLIDE_H}" type="custom"/>
        <p:notesSz cx="6858000" cy="9144000"/>
      </p:presentation>
    XML
  end

  def write_presentation_rels(zip, slide_count)
    slide_rels_entries = (1..slide_count).map do |n|
      "<Relationship Id=\"rId#{n + 2}\" " \
      "Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" " \
      "Target=\"slides/slide#{n}.xml\"/>"
    end.join("\n    ")

    zip.put_next_entry("ppt/_rels/presentation.xml.rels")
    zip.write(<<~XML)
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1"
          Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster"
          Target="slideMasters/slideMaster1.xml"/>
        <Relationship Id="rId2"
          Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme"
          Target="theme/theme1.xml"/>
        #{slide_rels_entries}
      </Relationships>
    XML
  end

  def write_theme(zip)
    zip.put_next_entry("ppt/theme/theme1.xml")
    return zip.write(@overrides[:theme_xml]) if @overrides[:theme_xml]
    zip.write(<<~XML)
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="CapHive">
        <a:themeElements>
          <a:clrScheme name="CapHive">
            <a:dk1><a:srgbClr val="#{DARK}"/></a:dk1>
            <a:lt1><a:srgbClr val="#{WHITE}"/></a:lt1>
            <a:dk2><a:srgbClr val="#{NAVY}"/></a:dk2>
            <a:lt2><a:srgbClr val="#{LIGHT}"/></a:lt2>
            <a:accent1><a:srgbClr val="#{BLUE}"/></a:accent1>
            <a:accent2><a:srgbClr val="2563EB"/></a:accent2>
            <a:accent3><a:srgbClr val="059669"/></a:accent3>
            <a:accent4><a:srgbClr val="D97706"/></a:accent4>
            <a:accent5><a:srgbClr val="9333EA"/></a:accent5>
            <a:accent6><a:srgbClr val="DC2626"/></a:accent6>
            <a:hlink><a:srgbClr val="#{BLUE}"/></a:hlink>
            <a:folHlink><a:srgbClr val="7C3AED"/></a:folHlink>
          </a:clrScheme>
          <a:fontScheme name="CapHive">
            <a:majorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>
            <a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont>
          </a:fontScheme>
          <a:fmtScheme name="CapHive">
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
          <p:bg>
            <p:bgPr>
              <a:solidFill><a:srgbClr val="#{WHITE}"/></a:solidFill>
            </p:bgPr>
          </p:bg>
          <p:spTree>
            <p:nvGrpSpPr>
              <p:cNvPr id="1" name=""/>
              <p:cNvGrpSpPr/>
              <p:nvPr/>
            </p:nvGrpSpPr>
            <p:grpSpPr>
              <a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></a:xfrm>
            </p:grpSpPr>
          </p:spTree>
        </p:cSld>
        <p:sldLayoutIdLst>
          <p:sldLayoutId id="2147483649" r:id="rId1"/>
        </p:sldLayoutIdLst>
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
        <Relationship Id="rId1"
          Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout"
          Target="../slideLayouts/slideLayout1.xml"/>
        <Relationship Id="rId2"
          Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme"
          Target="../theme/theme1.xml"/>
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
            <p:grpSpPr>
              <a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></a:xfrm>
            </p:grpSpPr>
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
        <Relationship Id="rId1"
          Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster"
          Target="../slideMasters/slideMaster1.xml"/>
      </Relationships>
    XML
  end

  # Each slide references the single slide layout
  def slide_rels
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1"
          Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout"
          Target="../slideLayouts/slideLayout1.xml"/>
      </Relationships>
    XML
  end

  # ── Utilities ─────────────────────────────────────────────────────────────

  def ordered_sections
    all = @draft.portfolio_report.portfolio_report_sections.index_by(&:id)
    @draft.portfolio_report_template.ordered_section_ids.filter_map { |id| all[id] }
  end

  # Extract plain-text bullet lines from HTML narrative.
  def extract_bullets(html)
    return ["No content generated."] if html.blank?

    doc = Nokogiri::HTML.fragment(html)
    bullets = doc.css("li").map { |li| li.text.strip }.reject(&:empty?)
    bullets = doc.css("p").map  { |p|  p.text.strip  }.reject(&:empty?) if bullets.empty?
    bullets = html.split("\n").map(&:strip).reject(&:empty?)             if bullets.empty?
    bullets.presence || ["No content generated."]
  end

  # XML-escape text for embedding in PPTX XML
  def e(text)
    CGI.escapeHTML(text.to_s)
  end
end
