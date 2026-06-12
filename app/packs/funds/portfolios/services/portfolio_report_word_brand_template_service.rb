require 'cgi'
require 'date'
require 'zip'

# Generates a fully-styled .docx placeholder template that the user downloads,
# optionally edits in Word, and uploads as a style reference for a Word template.
#
# Design: Emerald brand theme — matches the PPT brand template.
# The document has a rich cover page, KPI table slot, and four section slots.
# When exported the [[ marker ]] paragraphs are replaced by real content.
#
# Usage (Rake task):
#   bytes = PortfolioReportWordBrandTemplateService.new.generate
#   File.binwrite("tmp/word_placeholder_template.docx", bytes)
class PortfolioReportWordBrandTemplateService
  # ── Brand palette ────────────────────────────────────────────────────────────
  EMERALD      = "047857".freeze
  EMERALD_DARK = "064E3B".freeze
  EMERALD_MID  = "065F46".freeze
  EMERALD_LITE = "D1FAE5".freeze
  TEAL         = "0F766E".freeze
  AMBER        = "B45309".freeze
  GOLD         = "D4A847".freeze
  WHITE        = "FFFFFF".freeze
  BODY         = "334155".freeze
  CAPTION      = "94A3B8".freeze
  SLATE_LITE   = "F8FAFC".freeze

  W_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main".freeze

  SECTIONS = [
    "Business Overview",
    "Financial Highlights",
    "Operational Metrics",
    "Risks & Outlook"
  ].freeze

  def initialize(brand_name: "CapHive")
    @brand_name = brand_name
  end

  def generate
    Zip::OutputStream.write_buffer do |zip|
      write_content_types(zip)
      write_top_rels(zip)
      write_document_rels(zip)
      write_document(zip)
      write_styles(zip)
      write_numbering(zip)
      write_theme(zip)
      write_settings(zip)
      write_font_table(zip)
    end.string
  end

  private

  # ── Document body ────────────────────────────────────────────────────────────

  def write_document(zip)
    zip.put_next_entry("word/document.xml")
    zip.write(<<~XML)
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <w:document xmlns:w="#{W_NS}">
        <w:body>

          #{cover_xml}
          #{page_break_xml}
          #{kpi_section_xml}
          #{sections_xml}
          #{closing_note_xml}

          <w:sectPr>
            <w:headerReference w:type="default" r:id="rId6"
              xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/>
            <w:footerReference w:type="default" r:id="rId7"
              xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/>
            <w:pgSz w:w="12240" w:h="15840"/>
            <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"
                     w:header="720" w:footer="720" w:gutter="0"/>
          </w:sectPr>
        </w:body>
      </w:document>
    XML
  end

  # Cover page — emerald header band, company name, report metadata
  def cover_xml
    <<~XML
      #{shaded_para('[[ company name ]]',
                    fill: EMERALD_DARK, color: WHITE, sz: 80, bold: true,
                    spacing_before: 3600, spacing_after: 3600,
                    border_bottom_color: GOLD, border_bottom_sz: 36)}

      #{shaded_para('[[ fund name ]]',
                    fill: TEAL, color: WHITE, sz: 36,
                    spacing_before: 720, spacing_after: 720)}

      #{plain_para('', spacing_before: 240, spacing_after: 0)}

      #{run_para([
                   { text: 'Period: ', bold: true, color: BODY, sz: 22 },
                   { text: '[[ period ]]', bold: false, color: EMERALD, sz: 22 }
                 ], spacing_before: 0, spacing_after: 80)}

      #{run_para([
                   { text: 'Prepared: ', bold: true, color: BODY, sz: 22 },
                   { text: '[[ prepared date ]]', bold: false, color: EMERALD, sz: 22 }
                 ], spacing_before: 0, spacing_after: 80)}

      #{run_para([
                   { text: 'Report: ', bold: true, color: BODY, sz: 22 },
                   { text: '[[ template name ]]', bold: false, color: TEAL, sz: 22 }
                 ], spacing_before: 0, spacing_after: 480)}

      #{separator_para(EMERALD)}

      #{callout_box_xml}
    XML
  end

  # Executive summary callout box — thick left border, light background
  def callout_box_xml
    <<~XML
      #{shaded_para('Executive Summary',
                    fill: EMERALD_LITE, color: EMERALD_DARK, sz: 24, bold: true,
                    border_left_color: EMERALD, border_left_sz: 24,
                    spacing_before: 240, spacing_after: 80)}
      #{shaded_para(
        'This report covers [[ company name ]] for the period [[ period ]]. ' \
        'Key performance data, operational highlights, and strategic updates are detailed below. ' \
        'All figures are unaudited unless otherwise stated.',
        fill: EMERALD_LITE, color: BODY, sz: 20,
        border_left_color: EMERALD, border_left_sz: 24,
        spacing_before: 0, spacing_after: 320
      )}
    XML
  end

  def kpi_section_xml
    <<~XML
      #{heading1_para('Key Performance Indicators')}

      #{plain_para(
        'The table below is generated automatically from your KPI data for the selected period. ' \
        'Column headers reflect the reporting periods; rows map to your KPI mappings.',
        color: CAPTION, sz: 18, italic: true, spacing_before: 0, spacing_after: 160
      )}

      #{placeholder_para('[[ kpi table ]]')}

      #{separator_para(EMERALD_LITE)}
    XML
  end

  def sections_xml
    accent_colors = [EMERALD, TEAL, AMBER, EMERALD_MID]

    SECTIONS.each_with_index.map do |section_name, i|
      accent = accent_colors[i % accent_colors.length]
      <<~XML
        #{heading2_para(section_name, color: accent)}
        #{placeholder_para("[[ section: #{section_name} ]]")}
        #{plain_para('', spacing_before: 160, spacing_after: 0)}
      XML
    end.join("\n")
  end

  def closing_note_xml
    <<~XML
      #{separator_para(GOLD)}
      #{plain_para(
        'Template note: Rename the [[ section: Name ]] markers above to match your ' \
        "portfolio report's section names exactly (case-insensitive). " \
        'For example, change [[ section: Business Overview ]] if your section is named differently. ' \
        'The [[ kpi table ]] placeholder is replaced with your full KPI dataset automatically.',
        color: CAPTION, sz: 16, italic: true, spacing_before: 160, spacing_after: 160
      )}
    XML
  end

  # ── Paragraph XML helpers ────────────────────────────────────────────────────

  def shaded_para(text, fill:, color: WHITE, sz: 22, bold: false, italic: false,
                  spacing_before: 160, spacing_after: 160,
                  border_bottom_color: nil, border_bottom_sz: 4,
                  border_left_color: nil,   border_left_sz: 4)
    borders_xml = ""
    borders_xml += "<w:bottom w:val=\"single\" w:sz=\"#{border_bottom_sz}\" w:space=\"0\" w:color=\"#{border_bottom_color}\"/>" if border_bottom_color
    borders_xml += "<w:left w:val=\"single\" w:sz=\"#{border_left_sz}\" w:space=\"120\" w:color=\"#{border_left_color}\"/>" if border_left_color
    border_block = borders_xml.empty? ? "" : "<w:pBdr>#{borders_xml}</w:pBdr>"

    <<~XML
      <w:p>
        <w:pPr>
          #{border_block}
          <w:shd w:val="clear" w:color="auto" w:fill="#{fill}"/>
          <w:spacing w:before="#{spacing_before}" w:after="#{spacing_after}"/>
        </w:pPr>
        <w:r>
          <w:rPr>
            #{'<w:b/>' if bold}
            #{'<w:i/>' if italic}
            <w:color w:val="#{color}"/>
            <w:sz w:val="#{sz}"/><w:szCs w:val="#{sz}"/>
          </w:rPr>
          <w:t xml:space="preserve">#{CGI.escapeHTML(text)}</w:t>
        </w:r>
      </w:p>
    XML
  end

  def plain_para(text, color: BODY, sz: 22, bold: false, italic: false,
                 spacing_before: 0, spacing_after: 160)
    <<~XML
      <w:p>
        <w:pPr>
          <w:spacing w:before="#{spacing_before}" w:after="#{spacing_after}"/>
        </w:pPr>
        <w:r>
          <w:rPr>
            #{'<w:b/>' if bold}
            #{'<w:i/>' if italic}
            <w:color w:val="#{color}"/>
            <w:sz w:val="#{sz}"/><w:szCs w:val="#{sz}"/>
          </w:rPr>
          <w:t xml:space="preserve">#{CGI.escapeHTML(text)}</w:t>
        </w:r>
      </w:p>
    XML
  end

  # Multi-run paragraph — takes array of {text:, bold:, color:, sz:}
  def run_para(runs, spacing_before: 0, spacing_after: 160)
    run_xml = runs.map do |r|
      "<w:r><w:rPr>#{'<w:b/>' if r[:bold]}" \
        "<w:color w:val=\"#{r[:color]}\"/>" \
        "<w:sz w:val=\"#{r[:sz]}\"/><w:szCs w:val=\"#{r[:sz]}\"/>" \
        "</w:rPr><w:t xml:space=\"preserve\">#{CGI.escapeHTML(r[:text])}</w:t></w:r>"
    end.join
    <<~XML
      <w:p>
        <w:pPr><w:spacing w:before="#{spacing_before}" w:after="#{spacing_after}"/></w:pPr>
        #{run_xml}
      </w:p>
    XML
  end

  # Placeholder paragraph — visually distinct: light fill, teal dashed left border, monospace-like style
  def placeholder_para(marker)
    <<~XML
      <w:p>
        <w:pPr>
          <w:pBdr>
            <w:left w:val="dashed" w:sz="12" w:space="120" w:color="#{TEAL}"/>
          </w:pBdr>
          <w:shd w:val="clear" w:color="auto" w:fill="ECFDF5"/>
          <w:spacing w:before="120" w:after="120"/>
        </w:pPr>
        <w:r>
          <w:rPr>
            <w:rFonts w:ascii="Courier New" w:hAnsi="Courier New"/>
            <w:color w:val="#{EMERALD}"/>
            <w:sz w:val="20"/><w:szCs w:val="20"/>
          </w:rPr>
          <w:t>#{CGI.escapeHTML(marker)}</w:t>
        </w:r>
      </w:p>
    XML
  end

  def heading1_para(text)
    <<~XML
      <w:p>
        <w:pPr>
          <w:pStyle w:val="Heading1"/>
        </w:pPr>
        <w:r><w:t>#{CGI.escapeHTML(text)}</w:t></w:r>
      </w:p>
    XML
  end

  def heading2_para(text, color: TEAL)
    <<~XML
      <w:p>
        <w:pPr>
          <w:pStyle w:val="Heading2"/>
        </w:pPr>
        <w:r>
          <w:rPr><w:color w:val="#{color}"/></w:rPr>
          <w:t>#{CGI.escapeHTML(text)}</w:t>
        </w:r>
      </w:p>
    XML
  end

  def separator_para(color)
    <<~XML
      <w:p>
        <w:pPr>
          <w:pBdr>
            <w:bottom w:val="single" w:sz="6" w:space="4" w:color="#{color}"/>
          </w:pBdr>
          <w:spacing w:before="240" w:after="240"/>
        </w:pPr>
      </w:p>
    XML
  end

  def page_break_xml
    <<~XML
      <w:p>
        <w:r><w:br w:type="page"/></w:r>
      </w:p>
    XML
  end

  # ── Word structural files ─────────────────────────────────────────────────────

  def write_content_types(zip)
    zip.put_next_entry("[Content_Types].xml")
    zip.write(<<~XML)
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml"  ContentType="application/xml"/>
        <Override PartName="/word/document.xml"
          ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        <Override PartName="/word/styles.xml"
          ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
        <Override PartName="/word/numbering.xml"
          ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
        <Override PartName="/word/theme/theme1.xml"
          ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>
        <Override PartName="/word/settings.xml"
          ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>
        <Override PartName="/word/fontTable.xml"
          ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.fontTable+xml"/>
        <Override PartName="/word/header1.xml"
          ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>
        <Override PartName="/word/footer1.xml"
          ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>
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
          Target="word/document.xml"/>
      </Relationships>
    XML
  end

  def write_document_rels(zip)
    zip.put_next_entry("word/_rels/document.xml.rels")
    zip.write(<<~XML)
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles"     Target="styles.xml"/>
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering"  Target="numbering.xml"/>
        <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme"      Target="theme/theme1.xml"/>
        <Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings"   Target="settings.xml"/>
        <Relationship Id="rId5" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/fontTable"  Target="fontTable.xml"/>
        <Relationship Id="rId6" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header"     Target="header1.xml"/>
        <Relationship Id="rId7" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer"     Target="footer1.xml"/>
      </Relationships>
    XML

    # Document header — company/report name top-right with emerald underline
    zip.put_next_entry("word/header1.xml")
    zip.write(<<~XML)
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <w:hdr xmlns:w="#{W_NS}">
        <w:p>
          <w:pPr>
            <w:jc w:val="right"/>
            <w:pBdr>
              <w:bottom w:val="single" w:sz="4" w:space="4" w:color="#{EMERALD}"/>
            </w:pBdr>
          </w:pPr>
          <w:r>
            <w:rPr>
              <w:color w:val="#{EMERALD}"/><w:sz w:val="16"/><w:szCs w:val="16"/>
            </w:rPr>
            <w:t>Portfolio Report  |  CONFIDENTIAL</w:t>
          </w:r>
        </w:p>
      </w:hdr>
    XML

    # Document footer — page number centred + generation date
    zip.put_next_entry("word/footer1.xml")
    zip.write(<<~XML)
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <w:ftr xmlns:w="#{W_NS}">
        <w:p>
          <w:pPr>
            <w:jc w:val="center"/>
            <w:pBdr>
              <w:top w:val="single" w:sz="4" w:space="4" w:color="#{EMERALD_LITE}"/>
            </w:pBdr>
          </w:pPr>
          <w:r>
            <w:rPr><w:color w:val="#{CAPTION}"/><w:sz w:val="16"/><w:szCs w:val="16"/></w:rPr>
            <w:t xml:space="preserve">Page </w:t>
          </w:r>
          <w:fldChar w:fldCharType="begin"/>
          <w:instrText>PAGE</w:instrText>
          <w:fldChar w:fldCharType="end"/>
          <w:r>
            <w:rPr><w:color w:val="#{CAPTION}"/><w:sz w:val="16"/><w:szCs w:val="16"/></w:rPr>
            <w:t xml:space="preserve">  |  Generated: #{Time.zone.today.strftime('%d %b %Y')}  |  #{@brand_name}</w:t>
          </w:r>
        </w:p>
      </w:ftr>
    XML
  end

  def write_styles(zip)
    zip.put_next_entry("word/styles.xml")
    zip.write(<<~XML)
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <w:styles xmlns:w="#{W_NS}">
        <w:docDefaults>
          <w:rPrDefault>
            <w:rPr>
              <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/>
              <w:color w:val="#{BODY}"/>
              <w:sz w:val="22"/><w:szCs w:val="22"/>
              <w:lang w:val="en-US"/>
            </w:rPr>
          </w:rPrDefault>
          <w:pPrDefault>
            <w:pPr>
              <w:spacing w:after="160" w:line="276" w:lineRule="auto"/>
            </w:pPr>
          </w:pPrDefault>
        </w:docDefaults>

        <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
          <w:name w:val="Normal"/>
        </w:style>

        <w:style w:type="character" w:default="1" w:styleId="DefaultParagraphFont">
          <w:name w:val="Default Paragraph Font"/>
        </w:style>

        <w:style w:type="paragraph" w:styleId="Heading1">
          <w:name w:val="heading 1"/>
          <w:basedOn w:val="Normal"/>
          <w:next w:val="Normal"/>
          <w:pPr>
            <w:pBdr>
              <w:bottom w:val="single" w:sz="6" w:space="4" w:color="#{EMERALD}"/>
            </w:pBdr>
            <w:spacing w:before="480" w:after="200"/>
            <w:outlineLvl w:val="0"/>
          </w:pPr>
          <w:rPr>
            <w:b/>
            <w:color w:val="#{EMERALD_DARK}"/>
            <w:sz w:val="40"/><w:szCs w:val="40"/>
          </w:rPr>
        </w:style>

        <w:style w:type="paragraph" w:styleId="Heading2">
          <w:name w:val="heading 2"/>
          <w:basedOn w:val="Normal"/>
          <w:next w:val="Normal"/>
          <w:pPr>
            <w:spacing w:before="360" w:after="120"/>
            <w:outlineLvl w:val="1"/>
          </w:pPr>
          <w:rPr>
            <w:b/>
            <w:color w:val="#{TEAL}"/>
            <w:sz w:val="28"/><w:szCs w:val="28"/>
          </w:rPr>
        </w:style>

        <w:style w:type="paragraph" w:styleId="ListBullet">
          <w:name w:val="List Bullet"/>
          <w:basedOn w:val="Normal"/>
          <w:pPr>
            <w:numPr>
              <w:ilvl w:val="0"/>
              <w:numId w:val="1"/>
            </w:numPr>
            <w:spacing w:before="0" w:after="100"/>
          </w:pPr>
        </w:style>

        <w:style w:type="table" w:styleId="TableGrid">
          <w:name w:val="Table Grid"/>
          <w:tblPr>
            <w:tblBorders>
              <w:top    w:val="single" w:sz="4" w:space="0" w:color="#{EMERALD_LITE}"/>
              <w:left   w:val="single" w:sz="4" w:space="0" w:color="#{EMERALD_LITE}"/>
              <w:bottom w:val="single" w:sz="4" w:space="0" w:color="#{EMERALD_LITE}"/>
              <w:right  w:val="single" w:sz="4" w:space="0" w:color="#{EMERALD_LITE}"/>
              <w:insideH w:val="single" w:sz="4" w:space="0" w:color="#{EMERALD_LITE}"/>
              <w:insideV w:val="single" w:sz="4" w:space="0" w:color="#{EMERALD_LITE}"/>
            </w:tblBorders>
          </w:tblPr>
          <w:tcPr>
            <w:tcMar>
              <w:top    w:w="80" w:type="dxa"/>
              <w:left   w:w="120" w:type="dxa"/>
              <w:bottom w:w="80" w:type="dxa"/>
              <w:right  w:w="120" w:type="dxa"/>
            </w:tcMar>
          </w:tcPr>
        </w:style>

      </w:styles>
    XML
  end

  def write_numbering(zip)
    zip.put_next_entry("word/numbering.xml")
    zip.write(<<~XML)
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <w:numbering xmlns:w="#{W_NS}">
        <w:abstractNum w:abstractNumId="0">
          <w:multiLevelType w:val="singleLevel"/>
          <w:lvl w:ilvl="0">
            <w:start w:val="1"/>
            <w:numFmt w:val="bullet"/>
            <w:lvlText w:val="•"/>
            <w:lvlJc w:val="left"/>
            <w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr>
            <w:rPr>
              <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/>
              <w:color w:val="#{EMERALD}"/>
            </w:rPr>
          </w:lvl>
        </w:abstractNum>
        <w:num w:numId="1">
          <w:abstractNumId w:val="0"/>
        </w:num>
      </w:numbering>
    XML
  end

  def write_theme(zip)
    zip.put_next_entry("word/theme/theme1.xml")
    zip.write(<<~XML)
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="CapHiveEmerald">
        <a:themeElements>
          <a:clrScheme name="CapHiveEmerald">
            <a:dk1><a:srgbClr val="#{EMERALD_DARK}"/></a:dk1>
            <a:lt1><a:srgbClr val="FFFFFF"/></a:lt1>
            <a:dk2><a:srgbClr val="#{EMERALD}"/></a:dk2>
            <a:lt2><a:srgbClr val="ECFDF5"/></a:lt2>
            <a:accent1><a:srgbClr val="#{EMERALD}"/></a:accent1>
            <a:accent2><a:srgbClr val="#{TEAL}"/></a:accent2>
            <a:accent3><a:srgbClr val="#{AMBER}"/></a:accent3>
            <a:accent4><a:srgbClr val="10B981"/></a:accent4>
            <a:accent5><a:srgbClr val="D1FAE5"/></a:accent5>
            <a:accent6><a:srgbClr val="#{GOLD}"/></a:accent6>
            <a:hlink><a:srgbClr val="#{TEAL}"/></a:hlink>
            <a:folHlink><a:srgbClr val="#{EMERALD}"/></a:folHlink>
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

  def write_settings(zip)
    zip.put_next_entry("word/settings.xml")
    zip.write(<<~XML)
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <w:settings xmlns:w="#{W_NS}">
        <w:defaultTabStop w:val="720"/>
        <w:displayBackgroundShape/>
      </w:settings>
    XML
  end

  def write_font_table(zip)
    zip.put_next_entry("word/fontTable.xml")
    zip.write(<<~XML)
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <w:fonts xmlns:w="#{W_NS}">
        <w:font w:name="Calibri">
          <w:panose1 w:val="020F0502020204030204"/>
          <w:family w:val="swiss"/>
          <w:pitch w:val="variable"/>
        </w:font>
        <w:font w:name="Courier New">
          <w:panose1 w:val="02070309020205020404"/>
          <w:family w:val="modern"/>
          <w:pitch w:val="fixed"/>
        </w:font>
      </w:fonts>
    XML
  end
end
