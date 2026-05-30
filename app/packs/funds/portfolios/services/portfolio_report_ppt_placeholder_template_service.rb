require 'cgi'
require 'date'
require 'zip'

# Generates a fully-designed .pptx placeholder template with [[ marker ]] shapes.
#
# When uploaded as a style reference on a PPT template and exported, the
# PortfolioReportPptTemplateService fills each marker with real draft content
# while preserving every other visual element (chrome, colors, logos, backgrounds).
#
# Slides generated:
#   1  — Cover         [[ company name ]], [[ fund name ]], [[ period ]], [[ prepared date ]]
#   2  — Contents      static TOC showing what the deck covers
#   3  — KPI Data      [[ kpi table ]]  (shape sized to fill the content area)
#   4  — Business Overview        [[ section: Business Overview ]]
#   5  — Financial Highlights     [[ section: Financial Highlights ]]
#   6  — Operational Metrics      [[ section: Operational Metrics ]]
#   7  — Risks & Outlook          [[ section: Risks & Outlook ]]
#   8  — Closing / Appendix       static
#
# Usage:
#   bytes = PortfolioReportPptPlaceholderTemplateService.new.generate
#   File.binwrite("tmp/ppt_placeholder_template.pptx", bytes)
class PortfolioReportPptPlaceholderTemplateService
  # ── Canvas ───────────────────────────────────────────────────────────────────
  SLIDE_W = 12_192_000
  SLIDE_H  =  6_858_000
  MARGIN   =    685_800
  CONTENT_W = SLIDE_W - MARGIN * 2

  # ── Emerald brand palette ────────────────────────────────────────────────────
  EMERALD_900 = "064E3B"
  EMERALD_800 = "065F46"
  EMERALD_700 = "047857"
  EMERALD_500 = "10B981"
  EMERALD_100 = "D1FAE5"
  EMERALD_50  = "ECFDF5"
  TEAL_700    = "0F766E"
  TEAL_100    = "CCFBF1"
  AMBER_700   = "B45309"
  AMBER_100   = "FEF3C7"
  GOLD        = "D4A847"
  WHITE       = "FFFFFF"
  SLATE_800   = "1E293B"
  SLATE_700   = "334155"
  SLATE_400   = "94A3B8"
  SLATE_100   = "F1F5F9"

  # Section accent colours — one per section slide
  SECTION_ACCENTS = [EMERALD_700, TEAL_700, AMBER_700, EMERALD_800].freeze

  SECTIONS = [
    "Business Overview",
    "Financial Highlights",
    "Operational Metrics",
    "Risks & Outlook"
  ].freeze

  # Layout constants (EMU)
  STRIPE_H    =   114_300   # top accent stripe
  TITLE_BG_H  =   971_550   # title band
  RULE_Y      = STRIPE_H + TITLE_BG_H           # 1_085_850
  RULE_H      =    28_575
  CONTENT_Y   = RULE_Y + RULE_H + 114_300       # 1_228_725
  FOOTER_H    =   285_750
  FOOTER_Y    = SLIDE_H - FOOTER_H              # 6_572_250
  CONTENT_H   = FOOTER_Y - CONTENT_Y - 57_150  # ~5_286_375

  # Cover layout
  PANEL_W     = SLIDE_W / 3                     # left brand panel ≈ 4_064_000
  PANEL_GAP   =    28_575                       # gold stripe between panels

  def initialize(brand_name: "CapHive")
    @brand_name = brand_name
    @shape_id   = 100
  end

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

  # ── Slide builders ────────────────────────────────────────────────────────────

  def build_slides
    slides = []
    slides << cover_slide
    slides << toc_slide
    slides << kpi_slide
    SECTIONS.each_with_index { |name, i| slides << section_slide(name, i) }
    slides << closing_slide
    slides
  end

  # ── Slide 1: Cover ───────────────────────────────────────────────────────────

  def cover_slide
    right_x = PANEL_W + PANEL_GAP
    right_w = SLIDE_W - right_x - MARGIN / 2

    slide_xml do
      # Backgrounds
      filled_rect(0, 0, SLIDE_W, SLIDE_H, EMERALD_50) +
      # Left brand panel — deep emerald
      filled_rect(0, 0, PANEL_W, SLIDE_H, EMERALD_800) +
      # Gold separator stripe
      filled_rect(PANEL_W, 0, PANEL_GAP, SLIDE_H, GOLD) +
      # Brand name in left panel
      text_box(e(@brand_name),
               x: MARGIN / 2, y: SLIDE_H / 2 - 800_000, w: PANEL_W - MARGIN,
               h: 500_000, size: 1800, bold: true, color: WHITE, align: "l", valign: "t") +
      text_box(e("Portfolio Report"),
               x: MARGIN / 2, y: SLIDE_H / 2 - 280_000, w: PANEL_W - MARGIN,
               h: 342_900, size: 1100, bold: false, color: EMERALD_100, align: "l", valign: "t") +
      # accent1 colour chip at bottom of left panel
      filled_rect(MARGIN / 2, SLIDE_H - 600_000, 228_600, 228_600, EMERALD_700) +
      text_box(e("accent1: ##{EMERALD_700}"),
               x: MARGIN / 2 + 285_750, y: SLIDE_H - 600_000, w: PANEL_W - MARGIN,
               h: 228_600, size: 800, bold: false, color: EMERALD_100, align: "l", valign: "ctr") +

      # Right side — placeholder content shapes
      # Company name — large
      placeholder_shape(e("[[ company name ]]"),
               x: right_x + MARGIN / 2, y: 800_000, w: right_w,
               h: 1_200_000, size: 4400, bold: true, color: EMERALD_900) +
      # Divider rule
      filled_rect(right_x + MARGIN / 2, 2_100_000, right_w, 19_050, EMERALD_700) +
      # Fund / report name
      placeholder_shape(e("[[ fund name ]]"),
               x: right_x + MARGIN / 2, y: 2_200_000, w: right_w,
               h: 600_000, size: 2000, bold: false, color: TEAL_700) +
      # Period
      placeholder_shape(e("[[ period ]]"),
               x: right_x + MARGIN / 2, y: 2_900_000, w: right_w / 2,
               h: 342_900, size: 1400, bold: false, color: SLATE_700) +
      # Prepared date — label + placeholder side by side
      text_box(e("Prepared:"),
               x: right_x + MARGIN / 2, y: 3_350_000, w: 800_000,
               h: 285_750, size: 1100, bold: true, color: SLATE_400, align: "l", valign: "ctr") +
      placeholder_shape(e("[[ prepared date ]]"),
               x: right_x + MARGIN / 2 + 857_250, y: 3_350_000, w: right_w - 857_250,
               h: 285_750, size: 1100, bold: false, color: SLATE_700) +
      # Confidential tag bottom
      filled_rect(right_x + MARGIN / 2, SLIDE_H - 400_000, 1_371_600, 228_600, AMBER_100) +
      text_box(e("CONFIDENTIAL"),
               x: right_x + MARGIN / 2, y: SLIDE_H - 400_000, w: 1_371_600,
               h: 228_600, size: 900, bold: true, color: AMBER_700, align: "ctr", valign: "ctr")
    end
  end

  # ── Slide 2: Table of Contents ───────────────────────────────────────────────

  def toc_slide
    items = ["Key Performance Indicators"] + SECTIONS

    slide_xml do
      content_chrome(e("Contents"), EMERALD_700) +
      numbered_list(items.map { |s| e(s) },
                    x: MARGIN, y: CONTENT_Y, w: CONTENT_W * 55 / 100, h: CONTENT_H,
                    size: 1900, color: SLATE_700, accent: EMERALD_700) +
      # Right panel — design notes box
      filled_rect(MARGIN + CONTENT_W * 57 / 100, CONTENT_Y,
                  CONTENT_W * 43 / 100, CONTENT_H, EMERALD_50) +
      filled_rect(MARGIN + CONTENT_W * 57 / 100, CONTENT_Y,
                  9_525, CONTENT_H, EMERALD_700) +
      text_box(e("How to use this template"),
               x: MARGIN + CONTENT_W * 57 / 100 + 57_150, y: CONTENT_Y + 114_300,
               w: CONTENT_W * 43 / 100 - 171_450, h: 400_000,
               size: 1300, bold: true, color: EMERALD_900, align: "l", valign: "t") +
      text_box(e("• Each [[ marker ]] shape is replaced with live data on export\n" \
                 "• Rename [[ section: Name ]] to match your section names\n" \
                 "• [[ kpi table ]] expands to fit the shape you drew\n" \
                 "• All other shapes are preserved exactly as designed\n" \
                 "• Edit in PowerPoint then re-upload as your style reference"),
               x: MARGIN + CONTENT_W * 57 / 100 + 57_150, y: CONTENT_Y + 570_000,
               w: CONTENT_W * 43 / 100 - 171_450, h: CONTENT_H - 700_000,
               size: 1100, bold: false, color: SLATE_700, align: "l", valign: "t") +
      slide_footer
    end
  end

  # ── Slide 3: KPI Data ────────────────────────────────────────────────────────

  def kpi_slide
    # Two summary stat boxes above the table, then the big table placeholder
    stat_w = (CONTENT_W - 228_600) / 3
    stat_y = CONTENT_Y + 57_150

    slide_xml do
      content_chrome(e("Key Performance Indicators"), TEAL_700) +

      # Three "stat chip" boxes — decorative, user edits these in PowerPoint
      stat_chip("Revenue",     "e.g. €26.3m", EMERALD_700, x: MARGIN,                  y: stat_y, w: stat_w) +
      stat_chip("EBITDA Mgn",  "e.g. 18.3%",  TEAL_700,    x: MARGIN + stat_w + 114_300, y: stat_y, w: stat_w) +
      stat_chip("Headcount",   "e.g. 138",    AMBER_700,   x: MARGIN + (stat_w + 114_300) * 2, y: stat_y, w: stat_w) +

      # Large KPI table placeholder — user can resize this in PowerPoint
      placeholder_shape(e("[[ kpi table ]]"),
               x: MARGIN, y: stat_y + 685_800 + 114_300,
               w: CONTENT_W, h: CONTENT_H - 685_800 - 228_600,
               size: 1600, bold: false, color: TEAL_700) +
      slide_footer
    end
  end

  # ── Slides 4–7: Section slides ───────────────────────────────────────────────

  def section_slide(section_name, idx)
    accent   = SECTION_ACCENTS[idx % SECTION_ACCENTS.length]
    bg_color = section_bg(idx)

    slide_xml do
      content_chrome(e(section_name), accent) +
      # Left column — main narrative placeholder (65% width)
      placeholder_shape(e("[[ section: #{section_name} ]]"),
               x: MARGIN, y: CONTENT_Y,
               w: CONTENT_W * 63 / 100, h: CONTENT_H,
               size: 1600, bold: false, color: SLATE_700) +
      # Right column — "Key Takeaway" callout panel (35% width)
      filled_rect(MARGIN + CONTENT_W * 65 / 100, CONTENT_Y,
                  CONTENT_W * 35 / 100, CONTENT_H, bg_color) +
      filled_rect(MARGIN + CONTENT_W * 65 / 100, CONTENT_Y,
                  9_525, CONTENT_H, accent) +
      text_box(e("Key Takeaway"),
               x: MARGIN + CONTENT_W * 65 / 100 + 57_150, y: CONTENT_Y + 114_300,
               w: CONTENT_W * 35 / 100 - 171_450, h: 342_900,
               size: 1300, bold: true, color: accent, align: "l", valign: "t") +
      text_box(e("Edit this panel in PowerPoint to add a key stat, quote, or summary for #{section_name}."),
               x: MARGIN + CONTENT_W * 65 / 100 + 57_150, y: CONTENT_Y + 514_350,
               w: CONTENT_W * 35 / 100 - 171_450, h: CONTENT_H - 628_650,
               size: 1100, bold: false, color: SLATE_400, align: "l", valign: "t") +
      slide_footer
    end
  end

  # ── Slide 8: Closing ─────────────────────────────────────────────────────────

  def closing_slide
    slide_xml do
      filled_rect(0, 0, SLIDE_W, SLIDE_H, EMERALD_800) +
      filled_rect(0, 0, SLIDE_W, 114_300, GOLD) +
      filled_rect(0, SLIDE_H - 114_300, SLIDE_W, 114_300, EMERALD_900) +
      text_box(e("Appendix & Disclosures"),
               x: MARGIN, y: SLIDE_H / 2 - 700_000, w: CONTENT_W, h: 685_800,
               size: 4000, bold: true, color: WHITE, align: "ctr", valign: "t") +
      text_box(e("This document is confidential and prepared solely for the intended recipient. " \
                 "All financial information is unaudited and subject to change. " \
                 "Past performance is not a reliable indicator of future results."),
               x: MARGIN, y: SLIDE_H / 2 + 114_300, w: CONTENT_W, h: 685_800,
               size: 1200, bold: false, color: EMERALD_100, align: "ctr", valign: "t") +
      text_box(e("#{@brand_name}  ·  Generated #{Date.today.strftime('%d %b %Y')}"),
               x: MARGIN, y: SLIDE_H - 342_900, w: CONTENT_W, h: 228_600,
               size: 900, bold: false, color: EMERALD_700, align: "ctr", valign: "ctr")
    end
  end

  # ── Chrome helpers ────────────────────────────────────────────────────────────

  def content_chrome(title, accent)
    filled_rect(0, 0, SLIDE_W, SLIDE_H, WHITE) +
    filled_rect(0, 0, SLIDE_W, STRIPE_H, accent) +
    filled_rect(0, STRIPE_H, SLIDE_W, TITLE_BG_H, SLATE_100) +
    text_box(title,
             x: MARGIN, y: STRIPE_H, w: CONTENT_W * 75 / 100, h: TITLE_BG_H,
             size: 2800, bold: true, color: SLATE_800, align: "l", valign: "ctr") +
    # Brand badge top-right
    filled_rect(SLIDE_W - 400_000, 0, 400_000, STRIPE_H, EMERALD_800) +
    text_box(e(@brand_name),
             x: SLIDE_W - 380_000, y: 0, w: 360_000, h: STRIPE_H,
             size: 700, bold: true, color: WHITE, align: "ctr", valign: "ctr") +
    filled_rect(MARGIN, RULE_Y, CONTENT_W, RULE_H, EMERALD_100)
  end

  def slide_footer
    text_box(e("CONFIDENTIAL  ·  #{@brand_name}"),
             x: MARGIN, y: FOOTER_Y + 57_150, w: CONTENT_W / 2, h: FOOTER_H,
             size: 800, bold: false, color: SLATE_400, align: "l", valign: "ctr") +
    text_box(e(Date.today.strftime('%d %b %Y')),
             x: MARGIN + CONTENT_W / 2, y: FOOTER_Y + 57_150, w: CONTENT_W / 2, h: FOOTER_H,
             size: 800, bold: false, color: SLATE_400, align: "r", valign: "ctr")
  end

  # ── Shape primitives ──────────────────────────────────────────────────────────

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
          <a:noFill/><a:ln><a:noFill/></a:ln>
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

  # A placeholder shape — dashed teal border + light mint fill to make markers obvious
  def placeholder_shape(text, x:, y:, w:, h:, size: 1600, bold: false, color: TEAL_700)
    id = @shape_id += 1
    <<~XML
      <p:sp>
        <p:nvSpPr>
          <p:cNvPr id="#{id}" name="placeholder_#{id}"/>
          <p:cNvSpPr txBox="1"/>
          <p:nvPr/>
        </p:nvSpPr>
        <p:spPr>
          <a:xfrm><a:off x="#{x}" y="#{y}"/><a:ext cx="#{w}" cy="#{h}"/></a:xfrm>
          <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
          <a:solidFill><a:srgbClr val="#{EMERALD_50}"/></a:solidFill>
          <a:ln w="12700">
            <a:solidFill><a:srgbClr val="#{TEAL_700}"/></a:solidFill>
            <a:prstDash val="dash"/>
          </a:ln>
        </p:spPr>
        <p:txBody>
          <a:bodyPr anchor="ctr" wrap="square"><a:normAutofit/></a:bodyPr>
          <a:lstStyle/>
          <a:p>
            <a:pPr algn="ctr"/>
            <a:r>
              <a:rPr lang="en-US" sz="#{size}" b="#{bold ? 1 : 0}" i="0" dirty="0">
                <a:solidFill><a:srgbClr val="#{color}"/></a:solidFill>
              </a:rPr>
              <a:t>#{text}</a:t>
            </a:r>
          </a:p>
        </p:txBody>
      </p:sp>
    XML
  end

  # Numbered TOC list
  def numbered_list(items, x:, y:, w:, h:, size: 1900, color: SLATE_700, accent: EMERALD_700)
    id    = @shape_id += 1
    paras = items.each_with_index.map do |item, i|
      spc = i > 0 ? "<a:spcBef><a:spcPts val=\"280\"/></a:spcBef>" : ""
      <<~PARA
        <a:p>
          <a:pPr marL="457200" indent="-457200">#{spc}</a:pPr>
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
    <<~XML
      <p:sp>
        <p:nvSpPr>
          <p:cNvPr id="#{id}" name="list_#{id}"/><p:cNvSpPr txBox="1"/><p:nvPr/>
        </p:nvSpPr>
        <p:spPr>
          <a:xfrm><a:off x="#{x}" y="#{y}"/><a:ext cx="#{w}" cy="#{h}"/></a:xfrm>
          <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
          <a:noFill/><a:ln><a:noFill/></a:ln>
        </p:spPr>
        <p:txBody>
          <a:bodyPr anchor="t" wrap="square"><a:normAutofit/></a:bodyPr>
          <a:lstStyle/>#{paras}
        </p:txBody>
      </p:sp>
    XML
  end

  # Small summary stat chip for the KPI slide header row
  def stat_chip(label, hint, accent, x:, y:, w:)
    h = 571_500
    id1 = @shape_id += 1
    id2 = @shape_id += 1
    id3 = @shape_id += 1
    <<~XML
      <p:sp>
        <p:nvSpPr><p:cNvPr id="#{id1}" name="chip_bg_#{id1}"/>
          <p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr/>
        </p:nvSpPr>
        <p:spPr>
          <a:xfrm><a:off x="#{x}" y="#{y}"/><a:ext cx="#{w}" cy="#{h}"/></a:xfrm>
          <a:prstGeom prst="roundRect"><a:avLst><a:gd name="adj" fmla="val 10000"/></a:avLst></a:prstGeom>
          <a:solidFill><a:srgbClr val="#{EMERALD_50}"/></a:solidFill>
          <a:ln w="9525"><a:solidFill><a:srgbClr val="#{accent}"/></a:solidFill></a:ln>
        </p:spPr>
        <p:txBody><a:bodyPr/><a:lstStyle/><a:p/></p:txBody>
      </p:sp>
      <p:sp>
        <p:nvSpPr><p:cNvPr id="#{id2}" name="chip_val_#{id2}"/>
          <p:cNvSpPr txBox="1"/><p:nvPr/>
        </p:nvSpPr>
        <p:spPr>
          <a:xfrm><a:off x="#{x}" y="#{y + 57_150}"/><a:ext cx="#{w}" cy="#{285_750}"/></a:xfrm>
          <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
          <a:noFill/><a:ln><a:noFill/></a:ln>
        </p:spPr>
        <p:txBody>
          <a:bodyPr anchor="ctr" wrap="square"><a:normAutofit/></a:bodyPr>
          <a:lstStyle/>
          <a:p><a:pPr algn="ctr"/>
            <a:r>
              <a:rPr lang="en-US" sz="2200" b="1" dirty="0">
                <a:solidFill><a:srgbClr val="#{accent}"/></a:solidFill>
              </a:rPr>
              <a:t>#{e(hint)}</a:t>
            </a:r>
          </a:p>
        </p:txBody>
      </p:sp>
      <p:sp>
        <p:nvSpPr><p:cNvPr id="#{id3}" name="chip_lbl_#{id3}"/>
          <p:cNvSpPr txBox="1"/><p:nvPr/>
        </p:nvSpPr>
        <p:spPr>
          <a:xfrm><a:off x="#{x}" y="#{y + 342_900}"/><a:ext cx="#{w}" cy="#{228_600}"/></a:xfrm>
          <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
          <a:noFill/><a:ln><a:noFill/></a:ln>
        </p:spPr>
        <p:txBody>
          <a:bodyPr anchor="t" wrap="square"><a:normAutofit/></a:bodyPr>
          <a:lstStyle/>
          <a:p><a:pPr algn="ctr"/>
            <a:r>
              <a:rPr lang="en-US" sz="1000" b="0" dirty="0">
                <a:solidFill><a:srgbClr val="#{SLATE_400}"/></a:solidFill>
              </a:rPr>
              <a:t>#{e(label)}</a:t>
            </a:r>
          </a:p>
        </p:txBody>
      </p:sp>
    XML
  end

  def section_bg(idx)
    [EMERALD_50, TEAL_100, AMBER_100, EMERALD_50][idx % 4]
  end

  def e(text) = CGI.escapeHTML(text.to_s)

  # ── Slide XML wrapper ─────────────────────────────────────────────────────────

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
            <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></a:xfrm></p:grpSpPr>
            #{content}
          </p:spTree>
        </p:cSld>
      </p:sld>
    XML
  end

  # ── PPTX structural files ─────────────────────────────────────────────────────

  def write_content_types(zip, n)
    entries = (1..n).map { |i|
      "<Override PartName=\"/ppt/slides/slide#{i}.xml\" " \
      "ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/>"
    }.join("\n    ")
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
    ids = (1..n).map.with_index(256) { |i, id| "<p:sldId id=\"#{id}\" r:id=\"rId#{i + 2}\"/>" }.join
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
    entries = (1..n).map { |i|
      "<Relationship Id=\"rId#{i + 2}\" " \
      "Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" " \
      "Target=\"slides/slide#{i}.xml\"/>"
    }.join
    zip.put_next_entry("ppt/_rels/presentation.xml.rels")
    zip.write(<<~XML)
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme"       Target="theme/theme1.xml"/>
        #{entries}
      </Relationships>
    XML
  end

  def write_theme(zip)
    zip.put_next_entry("ppt/theme/theme1.xml")
    zip.write(<<~XML)
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="CapHiveEmerald">
        <a:themeElements>
          <a:clrScheme name="CapHiveEmerald">
            <a:dk1><a:srgbClr val="#{EMERALD_900}"/></a:dk1>
            <a:lt1><a:srgbClr val="FFFFFF"/></a:lt1>
            <a:dk2><a:srgbClr val="#{EMERALD_800}"/></a:dk2>
            <a:lt2><a:srgbClr val="#{EMERALD_50}"/></a:lt2>
            <a:accent1><a:srgbClr val="#{EMERALD_700}"/></a:accent1>
            <a:accent2><a:srgbClr val="#{TEAL_700}"/></a:accent2>
            <a:accent3><a:srgbClr val="#{AMBER_700}"/></a:accent3>
            <a:accent4><a:srgbClr val="#{EMERALD_500}"/></a:accent4>
            <a:accent5><a:srgbClr val="#{EMERALD_100}"/></a:accent5>
            <a:accent6><a:srgbClr val="#{GOLD}"/></a:accent6>
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
            <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
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
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme"       Target="../theme/theme1.xml"/>
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
            <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
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
