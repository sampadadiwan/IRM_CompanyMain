require 'cgi'
require 'date'
require 'zip'

# Generates a standalone "brand showcase" PPTX file that the user downloads and then
# uploads as a style reference on a PortfolioReportTemplate.
#
# When uploaded, PortfolioReportPptThemeReader reads ppt/theme/theme1.xml from this file
# and extracts accent1 + font, which are passed as overrides to the export service so
# every generated report inherits this brand palette.
#
# Theme: Emerald — deep green primary, teal secondary, amber highlight.
# Usage (Rails console or Rake task):
#   bytes = PortfolioReportBrandTemplatePptService.new.generate
#   File.binwrite("tmp/brand_emerald.pptx", bytes)
class PortfolioReportBrandTemplatePptService
  # ── Canvas ──────────────────────────────────────────────────────────────────
  SLIDE_W = 12_192_000
  SLIDE_H = 6_858_000
  MARGIN =    685_800

  # ── Emerald brand palette ────────────────────────────────────────────────────
  EMERALD_900 = "064E3B".freeze   # near-black green — dk1 / primary heading text
  EMERALD_800 = "065F46".freeze   # deep brand green — slide headers
  EMERALD_700 = "047857".freeze   # accent1 — primary accent (read by theme reader)
  EMERALD_500 = "10B981".freeze   # accent2 — lighter green highlight
  EMERALD_100 = "D1FAE5".freeze   # very light mint — table alt rows / cover band
  EMERALD_50  = "ECFDF5".freeze   # near-white mint — cover background tint
  TEAL_700    = "0F766E".freeze   # accent3 — teal complement
  AMBER_700   = "B45309".freeze   # accent4 — warm contrast / highlight
  AMBER_100   = "FEF3C7".freeze   # amber tint
  WHITE       = "FFFFFF".freeze
  SLATE_700   = "334155".freeze   # body text
  SLATE_400   = "94A3B8".freeze   # caption / meta
  GOLD_LINE   = "D4A847".freeze   # decorative rule / stripe

  CONTENT_W = SLIDE_W - (MARGIN * 2)

  def initialize(brand_name: "CapHive Emerald")
    @brand_name = brand_name
    @shape_id   = 100
  end

  # Returns raw .pptx bytes.
  def generate
    Zip::OutputStream.write_buffer do |zip|
      slides = [
        cover_slide,
        palette_slide,
        typography_slide,
        sample_data_slide,
        section_sample_slide
      ]
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

  # ── Slides ──────────────────────────────────────────────────────────────────

  def cover_slide
    slide_xml do
      # Mint background
      filled_rect(0, 0, SLIDE_W, SLIDE_H, EMERALD_50) +
        # Left brand panel (deep emerald)
        filled_rect(0, 0, SLIDE_W / 3, SLIDE_H, EMERALD_800) +
        # Decorative gold rule on the right edge of the panel
        filled_rect(SLIDE_W / 3, 0, 28_575, SLIDE_H, GOLD_LINE) +
        # Brand name in the left panel
        text_box(e(@brand_name),
                 x: MARGIN / 2, y: (SLIDE_H / 2) - 600_000, w: (SLIDE_W / 3) - MARGIN,
                 h: 600_000, size: 2000, bold: true, color: WHITE, align: "l", valign: "t") +
        # Sub-label
        text_box(e("Brand Theme Template"),
                 x: MARGIN / 2, y: (SLIDE_H / 2) + 57_150, w: (SLIDE_W / 3) - MARGIN,
                 h: 342_900, size: 1200, bold: false, color: EMERALD_100, align: "l", valign: "t") +
        # Large accent1 swatch label on the right
        text_box(e("accent1"),
                 x: MARGIN / 2, y: SLIDE_H - 800_000, w: (SLIDE_W / 3) - MARGIN,
                 h: 285_750, size: 900, bold: false, color: EMERALD_500, align: "l", valign: "t") +
        text_box(e("##{EMERALD_700}"),
                 x: MARGIN / 2, y: SLIDE_H - 520_000, w: (SLIDE_W / 3) - MARGIN,
                 h: 285_750, size: 1000, bold: true, color: EMERALD_100, align: "l", valign: "t") +
        # Main heading on the right
        text_box(e("Portfolio Report"),
                 x: (SLIDE_W / 3) + MARGIN, y: 1_200_000, w: CONTENT_W - (SLIDE_W / 3) + MARGIN,
                 h: 1_371_600, size: 5200, bold: true, color: EMERALD_900, align: "l", valign: "t") +
        text_box(e("Brand Reference Deck"),
                 x: (SLIDE_W / 3) + MARGIN, y: 2_743_200, w: CONTENT_W - (SLIDE_W / 3) + MARGIN,
                 h: 685_800, size: 2400, bold: false, color: TEAL_700, align: "l", valign: "t") +
        text_box(e("Upload this file as a style reference on any PPT template\nto apply the Emerald brand palette to your exports."),
                 x: (SLIDE_W / 3) + MARGIN, y: 3_600_000, w: CONTENT_W - (SLIDE_W / 3) + MARGIN,
                 h: 800_000, size: 1300, bold: false, color: SLATE_700, align: "l", valign: "t") +
        # Date bottom-right
        text_box(e("Generated #{Time.zone.today.strftime('%d %b %Y')}"),
                 x: (SLIDE_W / 3) + MARGIN, y: SLIDE_H - 400_000,
                 w: CONTENT_W - (SLIDE_W / 3) + MARGIN, h: 285_750,
                 size: 900, bold: false, color: SLATE_400, align: "r", valign: "t")
    end
  end

  def palette_slide
    slide_xml do
      slide_chrome("Brand Colour Palette") +
        # Row of 5 colour swatches with labels underneath
        swatch_block(EMERALD_800, "Emerald 800\n##{EMERALD_800}", x: MARGIN, y: 1_500_000) +
        swatch_block(EMERALD_700, "Emerald 700\n##{EMERALD_700}\naccent1", x: MARGIN + 2_057_400, y: 1_500_000) +
        swatch_block(EMERALD_500, "Emerald 500\n##{EMERALD_500}\naccent2", x: MARGIN + 4_114_800, y: 1_500_000) +
        swatch_block(TEAL_700,    "Teal 700\n##{TEAL_700}\naccent3",    x: MARGIN + 6_172_200, y: 1_500_000) +
        swatch_block(AMBER_700,   "Amber 700\n##{AMBER_700}\naccent4",  x: MARGIN + 8_229_600, y: 1_500_000) +
        text_box(e("The accent1 colour (##{EMERALD_700}) is read by the theme reader when this file is uploaded as a style reference."),
                 x: MARGIN, y: 4_800_000, w: CONTENT_W, h: 400_000,
                 size: 1100, bold: false, color: SLATE_400, align: "l", valign: "t")
    end
  end

  def typography_slide
    slide_xml do
      slide_chrome("Typography") +
        # Heading samples
        text_box(e("Heading 1 — Report Title  (52pt, bold, Calibri)"),
                 x: MARGIN, y: 1_300_000, w: CONTENT_W, h: 685_800,
                 size: 5200, bold: true, color: EMERALD_900, align: "l", valign: "t") +
        text_box(e("Heading 2 — Section Title  (28pt, bold)"),
                 x: MARGIN, y: 2_200_000, w: CONTENT_W, h: 457_200,
                 size: 2800, bold: true, color: EMERALD_800, align: "l", valign: "t") +
        text_box(e("Body text — supporting narrative and bullet points  (17pt, regular)"),
                 x: MARGIN, y: 2_800_000, w: CONTENT_W, h: 400_000,
                 size: 1700, bold: false, color: SLATE_700, align: "l", valign: "t") +
        text_box(e("Caption / footer text  (10pt, light)"),
                 x: MARGIN, y: 3_300_000, w: CONTENT_W, h: 342_900,
                 size: 1000, bold: false, color: SLATE_400, align: "l", valign: "t") +
        # Divider
        filled_rect(MARGIN, 3_800_000, CONTENT_W, 9_525, EMERALD_700) +
        text_box(e("All typefaces inherit the theme's majorFont / minorFont (Calibri by default). " \
                   "To change the font, edit the style template in PowerPoint and re-upload."),
                 x: MARGIN, y: 3_900_000, w: CONTENT_W, h: 500_000,
                 size: 1100, bold: false, color: SLATE_400, align: "l", valign: "t")
    end
  end

  def sample_data_slide
    slide_xml do
      slide_chrome("KPI Data Table — Sample") +
        sample_table
    end
  end

  def section_sample_slide
    slide_xml do
      slide_chrome("Investment Highlights", accent: TEAL_700) +
        bullets_block([
                        "Portfolio company delivered 42% revenue growth YoY, exceeding the base case by 8pp",
                        "EBITDA margin expanded to 18.3% from 14.1% driven by improved operating leverage",
                        "Completed bolt-on acquisition of TechCo Ltd in Q3; integration on track",
                        "Management team strengthened with appointment of new CFO from industry",
                        "Pipeline remains active — 3 follow-on deals under review for H2"
                      ])
    end
  end

  # ── Slide chrome ─────────────────────────────────────────────────────────────

  def slide_chrome(title, accent: EMERALD_700)
    filled_rect(0, 0, SLIDE_W, SLIDE_H, WHITE) +
      filled_rect(0, 0, SLIDE_W, 114_300, accent) +
      filled_rect(0, 114_300, SLIDE_W, 971_550, "F8FAFC") +
      text_box(e(title),
               x: MARGIN, y: 114_300, w: CONTENT_W, h: 971_550,
               size: 2800, bold: true, color: EMERALD_900, align: "l", valign: "ctr") +
      filled_rect(MARGIN, 1_085_850, CONTENT_W, 28_575, "E2E8F0") +
      # Brand mark — small emerald swatch top-right
      filled_rect(SLIDE_W - 400_000, 0, 400_000, 114_300, EMERALD_800)
  end

  def bullets_block(lines)
    id    = @shape_id += 1
    paras = lines.map.with_index do |line, i|
      spc = i.positive? ? "<a:spcBef><a:spcPts val=\"180\"/></a:spcBef>" : ""
      <<~PARA
        <a:p>
          <a:pPr marL="342900" indent="-342900">
            #{spc}
            <a:buClr><a:srgbClr val="#{EMERALD_700}"/></a:buClr>
            <a:buChar char="●"/>
          </a:pPr>
          <a:r>
            <a:rPr lang="en-US" sz="1700" b="0" dirty="0">
              <a:solidFill><a:srgbClr val="#{SLATE_700}"/></a:solidFill>
            </a:rPr>
            <a:t>#{e(line)}</a:t>
          </a:r>
        </a:p>
      PARA
    end.join
    <<~XML
      <p:sp>
        <p:nvSpPr>
          <p:cNvPr id="#{id}" name="bullets_#{id}"/>
          <p:cNvSpPr txBox="1"/>
          <p:nvPr/>
        </p:nvSpPr>
        <p:spPr>
          <a:xfrm><a:off x="#{MARGIN}" y="1228725"/><a:ext cx="#{CONTENT_W}" cy="5286375"/></a:xfrm>
          <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
          <a:noFill/>
          <a:ln><a:noFill/></a:ln>
        </p:spPr>
        <p:txBody>
          <a:bodyPr anchor="t" wrap="square"><a:normAutofit/></a:bodyPr>
          <a:lstStyle/>
          #{paras}
        </p:txBody>
      </p:sp>
    XML
  end

  def swatch_block(color, label, x:, y:)
    id1 = @shape_id += 1
    id2 = @shape_id += 1
    swatch_h = 1_371_600
    swatch_w = 1_828_800
    text_h   = 685_800
    lines    = label.split("\n")

    text_paras = lines.map.with_index do |line, i|
      bold = i.zero? ? 1 : 0
      txt_color = i == 2 ? EMERALD_700 : SLATE_700
      <<~PARA
        <a:p>
          <a:r>
            <a:rPr lang="en-US" sz="#{i == 2 ? 900 : 1000}" b="#{bold}" dirty="0">
              <a:solidFill><a:srgbClr val="#{txt_color}"/></a:solidFill>
            </a:rPr>
            <a:t>#{e(line)}</a:t>
          </a:r>
        </a:p>
      PARA
    end.join

    <<~XML
      <p:sp>
        <p:nvSpPr>
          <p:cNvPr id="#{id1}" name="swatch_#{id1}"/>
          <p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>
          <p:nvPr/>
        </p:nvSpPr>
        <p:spPr>
          <a:xfrm><a:off x="#{x}" y="#{y}"/><a:ext cx="#{swatch_w}" cy="#{swatch_h}"/></a:xfrm>
          <a:prstGeom prst="roundRect"><a:avLst><a:gd name="adj" fmla="val 10000"/></a:avLst></a:prstGeom>
          <a:solidFill><a:srgbClr val="#{color}"/></a:solidFill>
          <a:ln><a:noFill/></a:ln>
        </p:spPr>
        <p:txBody><a:bodyPr/><a:lstStyle/><a:p/></p:txBody>
      </p:sp>
      <p:sp>
        <p:nvSpPr>
          <p:cNvPr id="#{id2}" name="swatch_lbl_#{id2}"/>
          <p:cNvSpPr txBox="1"/>
          <p:nvPr/>
        </p:nvSpPr>
        <p:spPr>
          <a:xfrm><a:off x="#{x}" y="#{y + swatch_h + 114_300}"/><a:ext cx="#{swatch_w}" cy="#{text_h}"/></a:xfrm>
          <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
          <a:noFill/>
          <a:ln><a:noFill/></a:ln>
        </p:spPr>
        <p:txBody>
          <a:bodyPr anchor="t" wrap="square"><a:normAutofit/></a:bodyPr>
          <a:lstStyle/>
          #{text_paras}
        </p:txBody>
      </p:sp>
    XML
  end

  # ── KPI sample table ─────────────────────────────────────────────────────────

  def sample_table
    id        = @shape_id += 1
    row_h     = 400_000
    table_top = 1_300_000
    table_h   = SLIDE_H - table_top - (MARGIN / 2)
    col_w     = [CONTENT_W / 5] * 5
    col_w[0]  = (CONTENT_W * 0.40).to_i
    rest_w    = ((CONTENT_W - col_w[0]) / 4).to_i
    (1..4).each { |i| col_w[i] = rest_w }

    headers   = %w[Metric FY2021 FY2022 FY2023 FY2024]
    rows      = [
      ["Revenue (€m)",      "12.4", "18.7", "26.3", "37.4"],
      ["EBITDA (€m)",       "1.8",  "3.1",  "4.8",  "6.9"],
      ["EBITDA Margin (%)", "14.5", "16.6", "18.3", "18.5"],
      ["Headcount",         "48",   "71",   "103",  "138"],
      ["ARR (€m)",          "9.6",  "15.2", "22.7", "33.1"]
    ]

    header_row = headers.each_with_index.map do |h, i|
      sample_cell(e(h), fill: EMERALD_700, color: WHITE, bold: true,
                        w: col_w[i], h: row_h, align: i.zero? ? "l" : "r")
    end.join

    data_rows = rows.each_with_index.map do |row, ri|
      fill = ri.even? ? EMERALD_100 : WHITE
      cells = row.each_with_index.map do |val, ci|
        sample_cell(e(val), fill: fill, color: EMERALD_900, bold: false,
                            w: col_w[ci], h: row_h, align: ci.zero? ? "l" : "r")
      end.join
      "<a:tr h=\"#{row_h}\">#{cells}</a:tr>"
    end.join

    grid = col_w.map { |w| "<a:gridCol w=\"#{w}\"/>" }.join

    <<~XML
      <p:graphicFrame>
        <p:nvGraphicFramePr>
          <p:cNvPr id="#{id}" name="SampleTable_#{id}"/>
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
              <a:tblGrid>#{grid}</a:tblGrid>
              <a:tr h="#{row_h}">#{header_row}</a:tr>
              #{data_rows}
            </a:tbl>
          </a:graphicData>
        </a:graphic>
      </p:graphicFrame>
    XML
  end

  def sample_cell(text, fill:, color:, bold:, w:, h:, align: "l")
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
          <a:lnL w="9525"><a:solidFill><a:srgbClr val="D1FAE5"/></a:solidFill></a:lnL>
          <a:lnR w="9525"><a:solidFill><a:srgbClr val="D1FAE5"/></a:solidFill></a:lnR>
          <a:lnT w="9525"><a:solidFill><a:srgbClr val="D1FAE5"/></a:solidFill></a:lnT>
          <a:lnB w="9525"><a:solidFill><a:srgbClr val="D1FAE5"/></a:solidFill></a:lnB>
        </a:tcPr>
      </a:tc>
    XML
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
               color: SLATE_700, align: "l", valign: "ctr")
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

  def e(text) = CGI.escapeHTML(text.to_s)

  # ── PPTX structure ───────────────────────────────────────────────────────────

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
    ids = (1..n).map.with_index(256) do |i, id|
      "<p:sldId id=\"#{id}\" r:id=\"rId#{i + 2}\"/>"
    end.join("\n    ")
    zip.put_next_entry("ppt/presentation.xml")
    zip.write(<<~XML)
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
                      xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
                      xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>
        <p:sldIdLst>#{ids}</p:sldIdLst>
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

  # The theme XML is what PortfolioReportPptThemeReader reads when this file is uploaded.
  # accent1 = EMERALD_700 = #047857 is the key colour that gets extracted.
  def write_theme(zip)
    zip.put_next_entry("ppt/theme/theme1.xml")
    zip.write(<<~XML)
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="CapHiveEmerald">
        <a:themeElements>
          <a:clrScheme name="CapHiveEmerald">
            <a:dk1><a:srgbClr val="#{EMERALD_900}"/></a:dk1>
            <a:lt1><a:srgbClr val="#{WHITE}"/></a:lt1>
            <a:dk2><a:srgbClr val="#{EMERALD_800}"/></a:dk2>
            <a:lt2><a:srgbClr val="#{EMERALD_50}"/></a:lt2>
            <a:accent1><a:srgbClr val="#{EMERALD_700}"/></a:accent1>
            <a:accent2><a:srgbClr val="#{EMERALD_500}"/></a:accent2>
            <a:accent3><a:srgbClr val="#{TEAL_700}"/></a:accent3>
            <a:accent4><a:srgbClr val="#{AMBER_700}"/></a:accent4>
            <a:accent5><a:srgbClr val="#{EMERALD_100}"/></a:accent5>
            <a:accent6><a:srgbClr val="#{GOLD_LINE}"/></a:accent6>
            <a:hlink><a:srgbClr val="#{TEAL_700}"/></a:hlink>
            <a:folHlink><a:srgbClr val="#{EMERALD_500}"/></a:folHlink>
          </a:clrScheme>
          <a:fontScheme name="CapHiveEmerald">
            <a:majorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>
            <a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont>
          </a:fontScheme>
          <a:fmtScheme name="CapHiveEmerald">
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
