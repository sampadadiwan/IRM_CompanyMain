namespace :portfolio_report do
  desc "Generate a brand-template PPTX (Emerald theme) and write it to tmp/brand_template_emerald.pptx.\n" \
       "Upload the file as a 'style reference' on any PPT template to apply the Emerald palette."
  task generate_brand_template: :environment do
    require_relative "../../app/packs/funds/portfolios/services/portfolio_report_brand_template_ppt_service"
    bytes = PortfolioReportBrandTemplatePptService.new.generate
    dir   = Rails.root.join("public", "sample_uploads", "portfolio_report_templates")
    FileUtils.mkdir_p(dir)
    path  = dir.join("brand_template_emerald.pptx")
    File.binwrite(path, bytes)
    puts "Written to #{path}  (#{(bytes.bytesize / 1024.0).round(1)} KB)"
    puts "Open it in PowerPoint to preview the Emerald brand theme, then upload it"
    puts "as a style reference on any PortfolioReportTemplate to use those brand colours."
  end


  desc "Generate a placeholder Word template (.docx) and write it to tmp/word_placeholder_template.docx.\n" \
       "Upload this as a style reference on a Word template — it contains [[ markers ]] you can edit in Word."
  task generate_word_template: :environment do
    require_relative "../../app/packs/funds/portfolios/services/portfolio_report_word_brand_template_service"
    bytes = PortfolioReportWordBrandTemplateService.new.generate
    dir   = Rails.root.join("public", "sample_uploads", "portfolio_report_templates")
    FileUtils.mkdir_p(dir)
    path  = dir.join("word_placeholder_template.docx")
    File.binwrite(path, bytes)
    puts "Written to #{path}  (#{(bytes.bytesize / 1024.0).round(1)} KB)"
    puts "Open in Word to review the layout, then upload as a style reference on any Word template."
  end

  desc "Generate a placeholder PPT template (.pptx) and write it to public/sample_uploads/portfolio_report_templates/.\n" \
       "Upload this as a style reference on a PPT template — it contains [[ markers ]] you can edit in PowerPoint."
  task generate_ppt_template: :environment do
    require_relative "../../app/packs/funds/portfolios/services/portfolio_report_ppt_placeholder_template_service"
    bytes = PortfolioReportPptPlaceholderTemplateService.new.generate
    dir   = Rails.root.join("public", "sample_uploads", "portfolio_report_templates")
    FileUtils.mkdir_p(dir)
    path  = dir.join("ppt_placeholder_template.pptx")
    File.binwrite(path, bytes)
    puts "Written to #{path}  (#{(bytes.bytesize / 1024.0).round(1)} KB)"
    puts "Open in PowerPoint to review the layout, then upload as a style reference on any PPT template."
  end

  desc <<~DESC
    Seed a portfolio company with all data needed to test portfolio report generation v2.

    Creates (idempotent — safe to re-run):
      - A portfolio company "Report Gen Test Co" under the given entity
      - InvestorKpiMapping records (Income Statement + Operational Metrics)
      - 6 months of monthly KpiReport + Kpi actuals
      - A PortfolioReport "Test Analyst Report" with 4 sections
      - A PortfolioReportTemplate "Test Analyst Report — Word" with a seeded style .docx
      - 3 notes on the portfolio company (used as LLM narrative context)
      - 2 PortfolioReportExtract records (fake LLM output for the Extracts tab)

    Usage:
      rails "portfolio_report:seed[157]"    # seed for entity 157 (quote required in zsh)

    After running, use the printed portco id and draft template id in the
    manual testing steps in docs/modules/portfolio/portfolio_report_generation_v2_prd.md.
  DESC

  task :seed, [:entity_id] => :environment do |_, args|
    abort "[portfolio_report:seed] Usage: rails portfolio_report:seed[entity_id]" unless args[:entity_id]

    entity = Entity.find_by(id: args[:entity_id].to_i)
    abort "[portfolio_report:seed] Entity #{args[:entity_id]} not found." unless entity

    user = User.where(entity_id: entity.id).first
    abort "[portfolio_report:seed] Entity #{entity.id} has no users — cannot set user on KpiReport." unless user

    puts "[portfolio_report:seed] Seeding for entity #{entity.id} (#{entity.name}), user #{user.email}"
    puts

    # ── 1. Portfolio company ─────────────────────────────────────────────────────
    # Investor.create! auto-creates the portco's own Entity from primary_email.
    # Use entity_id in the email to keep it unique per fund entity.

    portco_name  = "Report Gen Test Co"
    portco_email = "report-gen-test-co-#{entity.id}@example-seed.com"

    portco = Investor.find_by(entity_id: entity.id, investor_name: portco_name, category: "Portfolio Company")
    unless portco
      portco = Investor.create!(
        entity_id:     entity.id,
        investor_name: portco_name,
        primary_email: portco_email,
        category:      "Portfolio Company",
        tag_list:      "SaaS,Growth"
      )
      puts "  [created] Investor id=#{portco.id} (#{portco_name}), entity id=#{portco.investor_entity_id}"
    else
      puts "  [ok]      Investor id=#{portco.id} (#{portco_name})"
    end

    puts

    # ── 2. InvestorKpiMapping records ────────────────────────────────────────────

    kpi_definitions = [
      # [ reported_name,   category,               data_type,   denomination  ]
      ["Revenue",          "Income Statement",      "money",     "millions"],
      ["Gross Profit",     "Income Statement",      "money",     "millions"],
      ["EBITDA",           "Income Statement",      "money",     "millions"],
      ["Burn Rate",        "Income Statement",      "money",     "millions"],
      ["MRR",              "Operational Metrics",   "money",     "millions"],
      ["Active Users",     "Operational Metrics",   "numeric",   nil],
      ["Headcount",        "Operational Metrics",   "numeric",   nil],
      ["Churn Rate",       "Operational Metrics",   "percentage",nil]
    ]

    kpi_mappings = {}  # reported_name => InvestorKpiMapping

    kpi_definitions.each do |reported_name, category, data_type, denomination|
      ikm = InvestorKpiMapping.find_or_initialize_by(
        entity_id:   entity.id,
        investor_id: portco.id,
        reported_kpi_name: reported_name
      )
      if ikm.new_record?
        ikm.assign_attributes(
          standard_kpi_name: reported_name,
          category:          category,
          data_type:         data_type,
          denomination:      denomination,
          show_in_report:    true
        )
        ikm.save!
        puts "  [created] InvestorKpiMapping '#{reported_name}' (#{category})"
      else
        # Ensure show_in_report is true on re-runs
        ikm.update!(show_in_report: true) unless ikm.show_in_report
        puts "  [ok]      InvestorKpiMapping '#{reported_name}'"
      end
      kpi_mappings[reported_name] = ikm
    end

    puts

    # ── 3. KpiReport + Kpi records — 6 months of monthly actuals ────────────────

    # Base values and month-over-month growth factors for realistic data
    base_values = {
      "Revenue"      => 1_200_000,
      "Gross Profit" =>   480_000,
      "EBITDA"       =>   120_000,
      "Burn Rate"    =>   150_000,
      "MRR"          =>   100_000,
      "Active Users" =>    25_000,
      "Headcount"    =>        82,
      "Churn Rate"   =>      2.1
    }
    growth = {
      "Revenue"      => 1.08,
      "Gross Profit" => 1.07,
      "EBITDA"       => 1.10,
      "Burn Rate"    => 1.02,
      "MRR"          => 1.08,
      "Active Users" => 1.05,
      "Headcount"    => 1.03,
      "Churn Rate"   => 0.97   # churn improving (shrinking)
    }

    # Generate as_of dates: last 6 month-ends ending at last month
    as_of_dates = (0..5).map { |n| (Date.today - n.months).end_of_month }.reverse

    as_of_dates.each_with_index do |as_of, month_idx|
      kr = KpiReport.find_by(
        entity_id:          entity.id,
        portfolio_company:  portco,
        period:             "Month",
        as_of:              as_of,
        tag_list:           "Actual"
      )

      unless kr
        kr = KpiReport.create!(
          entity_id:         entity.id,
          portfolio_company: portco,
          period:            "Month",
          as_of:             as_of,
          tag_list:          "Actual",
          user:              user
        )
        puts "  [created] KpiReport id=#{kr.id} period=Month as_of=#{as_of}"
      else
        puts "  [ok]      KpiReport id=#{kr.id} period=Month as_of=#{as_of}"
      end

      # Create Kpi values for each metric (skip if they already exist)
      kpi_definitions.each do |reported_name, _category, _data_type, _denomination|
        next if Kpi.exists?(kpi_report: kr, name: reported_name)

        raw_value = base_values[reported_name] * (growth[reported_name] ** month_idx)
        value = reported_name == "Headcount" ? raw_value.round : raw_value.round(2)

        Kpi.create!(
          kpi_report:           kr,
          entity_id:            entity.id,
          portfolio_company:    portco,
          investor_kpi_mapping: kpi_mappings[reported_name],
          name:                 reported_name,
          value:                value
        )
      end
    end

    puts

    # ── 4. PortfolioReport + PortfolioReportSections ─────────────────────────────

    report_name = "Test Analyst Report"

    portfolio_report = PortfolioReport.find_by(entity_id: entity.id, name: report_name)
    unless portfolio_report
      portfolio_report = PortfolioReport.create!(
        entity_id: entity.id,
        name:      report_name,
        tags:      "SaaS,Growth"
      )
      puts "  [created] PortfolioReport id=#{portfolio_report.id} '#{report_name}'"
    else
      puts "  [ok]      PortfolioReport id=#{portfolio_report.id} '#{report_name}'"
    end

    sections_config = [
      {
        name: "Business Overview",
        data: "Summarise what the company does, its market position, and any notable strategic developments in this period. Keep it to 3-5 concise points.",
        icon: "building"
      },
      {
        name: "Financial Highlights",
        data: "Summarise the key financial results for the period: revenue growth, margin trends, burn rate, and any notable variances vs prior periods. Use the KPI data provided. 4-6 points.",
        icon: "chart-bar"
      },
      {
        name: "Operational Metrics",
        data: "Highlight key operational KPIs: MRR, active users, headcount growth, and churn trends. Note any metrics that are improving or deteriorating. 3-5 points.",
        icon: "activity"
      },
      {
        name: "Risks & Outlook",
        data: "Identify the 2-3 most significant risks or concerns for this portfolio company and summarise the near-term outlook based on the available documents and notes.",
        icon: "alert-triangle"
      }
    ]

    sections_config.each do |cfg|
      section = portfolio_report.portfolio_report_sections.find_or_initialize_by(name: cfg[:name])
      if section.new_record?
        section.update!(data: cfg[:data], icon: cfg[:icon], tags: portfolio_report.tags)
        puts "  [created] PortfolioReportSection '#{cfg[:name]}'"
      else
        puts "  [ok]      PortfolioReportSection '#{cfg[:name]}'"
      end
    end

    puts

    # ── 5. PortfolioReportTemplate ───────────────────────────────────────────────

    template_name = "Test Analyst Report — Word"

    section_ids = portfolio_report.portfolio_report_sections.order(:id).pluck(:id)

    template = PortfolioReportTemplate.find_by(portfolio_report_id: portfolio_report.id, name: template_name)
    unless template
      template = PortfolioReportTemplate.create!(
        portfolio_report: portfolio_report,
        name:             template_name,
        output_format:    "word",
        section_order:    section_ids,
        kpi_layout: {
          categories:   ["Income Statement", "Operational Metrics"],
          tags:         ["Actual"],
          n_periods:    6,
          side_by_side: false
        },
        branding: {
          primary_color: "#1A3C6E",
          font:          "Calibri"
        }
      )
      puts "  [created] PortfolioReportTemplate id=#{template.id} '#{template_name}'"
    else
      # Keep section_order in sync if sections were added on a re-run
      template.update!(section_order: section_ids) if template.section_order != section_ids
      puts "  [ok]      PortfolioReportTemplate id=#{template.id} '#{template_name}'"
    end

    # ── 5a. Style reference document — comprehensive .docx with named styles ────
    # Produces a valid OOXML package containing:
    #   styles.xml  — Title, Heading 1/2, Body Text, List Bullet, Caption, TableGrid
    #   theme1.xml  — brand colours (#1A3C6E primary) and Calibri font
    #   document.xml — sample page demonstrating every style and a KPI table
    # The export pipeline opens this file and applies its named styles to output.

    # ASCII-only name — em dashes break the S3 Content-Disposition header.
    style_doc_name = "Seed Style Reference - #{template_name.gsub('—', '-')}"

    if template.style_document.present?
      puts "  [ok]      Style document already set: '#{template.style_document.name}'"
    else
      require "zip"
      require "tempfile"

      wml  = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
      ct   = "http://schemas.openxmlformats.org/package/2006/content-types"
      rels = "http://schemas.openxmlformats.org/package/2006/relationships"
      off  = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

      content_types_xml = <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="#{ct}">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml"  ContentType="application/xml"/>
          <Override PartName="/word/document.xml"
                    ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
          <Override PartName="/word/styles.xml"
                    ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
          <Override PartName="/word/theme/theme1.xml"
                    ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>
        </Types>
      XML

      pkg_rels_xml = <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="#{rels}">
          <Relationship Id="rId1" Type="#{off}/officeDocument" Target="word/document.xml"/>
        </Relationships>
      XML

      doc_rels_xml = <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="#{rels}">
          <Relationship Id="rId1" Type="#{off}/styles"   Target="styles.xml"/>
          <Relationship Id="rId2" Type="#{off}/theme"    Target="theme/theme1.xml"/>
        </Relationships>
      XML

      # ── styles.xml ─────────────────────────────────────────────────────────
      # Named styles the report generator applies to paragraphs and tables.
      # Brand: Calibri font, #1A3C6E (navy) primary, #4A6FA5 secondary.
      styles_xml = <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="#{wml}" xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml">
          <w:docDefaults>
            <w:rPrDefault>
              <w:rPr>
                <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/>
                <w:sz w:val="22"/>
                <w:szCs w:val="22"/>
                <w:lang w:val="en-US"/>
              </w:rPr>
            </w:rPrDefault>
            <w:pPrDefault>
              <w:pPr>
                <w:spacing w:after="160" w:line="259" w:lineRule="auto"/>
              </w:pPr>
            </w:pPrDefault>
          </w:docDefaults>

          <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
            <w:name w:val="Normal"/>
            <w:qFormat/>
          </w:style>

          <w:style w:type="paragraph" w:styleId="Title">
            <w:name w:val="Title"/>
            <w:basedOn w:val="Normal"/>
            <w:qFormat/>
            <w:pPr>
              <w:spacing w:before="0" w:after="320"/>
              <w:jc w:val="center"/>
            </w:pPr>
            <w:rPr>
              <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/>
              <w:b/>
              <w:color w:val="1A3C6E"/>
              <w:sz w:val="56"/>
              <w:szCs w:val="56"/>
              <w:spacing w:val="-10"/>
            </w:rPr>
          </w:style>

          <w:style w:type="paragraph" w:styleId="Subtitle">
            <w:name w:val="Subtitle"/>
            <w:basedOn w:val="Normal"/>
            <w:qFormat/>
            <w:pPr>
              <w:spacing w:before="0" w:after="480"/>
              <w:jc w:val="center"/>
            </w:pPr>
            <w:rPr>
              <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/>
              <w:color w:val="4A6FA5"/>
              <w:sz w:val="28"/>
              <w:szCs w:val="28"/>
            </w:rPr>
          </w:style>

          <w:style w:type="paragraph" w:styleId="Heading1">
            <w:name w:val="heading 1"/>
            <w:basedOn w:val="Normal"/>
            <w:next w:val="Normal"/>
            <w:qFormat/>
            <w:pPr>
              <w:keepNext/>
              <w:spacing w:before="480" w:after="120"/>
              <w:pBdr>
                <w:bottom w:val="single" w:sz="6" w:space="1" w:color="1A3C6E"/>
              </w:pBdr>
            </w:pPr>
            <w:rPr>
              <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/>
              <w:b/>
              <w:color w:val="1A3C6E"/>
              <w:sz w:val="32"/>
              <w:szCs w:val="32"/>
            </w:rPr>
          </w:style>

          <w:style w:type="paragraph" w:styleId="Heading2">
            <w:name w:val="heading 2"/>
            <w:basedOn w:val="Normal"/>
            <w:next w:val="Normal"/>
            <w:qFormat/>
            <w:pPr>
              <w:keepNext/>
              <w:spacing w:before="240" w:after="80"/>
            </w:pPr>
            <w:rPr>
              <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/>
              <w:b/>
              <w:color w:val="2E5A9C"/>
              <w:sz w:val="26"/>
              <w:szCs w:val="26"/>
            </w:rPr>
          </w:style>

          <w:style w:type="paragraph" w:styleId="BodyText">
            <w:name w:val="Body Text"/>
            <w:basedOn w:val="Normal"/>
            <w:qFormat/>
            <w:pPr>
              <w:spacing w:before="0" w:after="120" w:line="276" w:lineRule="auto"/>
            </w:pPr>
            <w:rPr>
              <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/>
              <w:sz w:val="22"/>
              <w:szCs w:val="22"/>
            </w:rPr>
          </w:style>

          <w:style w:type="paragraph" w:styleId="ListBullet">
            <w:name w:val="List Bullet"/>
            <w:basedOn w:val="Normal"/>
            <w:qFormat/>
            <w:pPr>
              <w:spacing w:before="0" w:after="80"/>
              <w:ind w:left="720" w:hanging="360"/>
            </w:pPr>
            <w:rPr>
              <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/>
              <w:sz w:val="22"/>
              <w:szCs w:val="22"/>
            </w:rPr>
          </w:style>

          <w:style w:type="paragraph" w:styleId="Caption">
            <w:name w:val="Caption"/>
            <w:basedOn w:val="Normal"/>
            <w:qFormat/>
            <w:pPr>
              <w:spacing w:before="60" w:after="160"/>
              <w:jc w:val="center"/>
            </w:pPr>
            <w:rPr>
              <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/>
              <w:i/>
              <w:color w:val="888888"/>
              <w:sz w:val="18"/>
              <w:szCs w:val="18"/>
            </w:rPr>
          </w:style>

          <w:style w:type="table" w:styleId="TableGrid">
            <w:name w:val="Table Grid"/>
            <w:tblPr>
              <w:tblBorders>
                <w:top     w:val="single" w:sz="4" w:space="0" w:color="CCCCCC"/>
                <w:left    w:val="single" w:sz="4" w:space="0" w:color="CCCCCC"/>
                <w:bottom  w:val="single" w:sz="4" w:space="0" w:color="CCCCCC"/>
                <w:right   w:val="single" w:sz="4" w:space="0" w:color="CCCCCC"/>
                <w:insideH w:val="single" w:sz="4" w:space="0" w:color="CCCCCC"/>
                <w:insideV w:val="single" w:sz="4" w:space="0" w:color="CCCCCC"/>
              </w:tblBorders>
              <w:tblCellMar>
                <w:top    w:w="60"  w:type="dxa"/>
                <w:left   w:w="108" w:type="dxa"/>
                <w:bottom w:w="60"  w:type="dxa"/>
                <w:right  w:w="108" w:type="dxa"/>
              </w:tblCellMar>
            </w:tblPr>
            <w:rPr>
              <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/>
              <w:sz w:val="20"/>
              <w:szCs w:val="20"/>
            </w:rPr>
          </w:style>
        </w:styles>
      XML

      # ── theme1.xml ──────────────────────────────────────────────────────────
      # Sets dk1 (text) = #1A3C6E, accent1 = #1A3C6E, minor font = Calibri.
      theme_xml = <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="CapHive">
          <a:themeElements>
            <a:clrScheme name="CapHive Brand">
              <a:dk1><a:srgbClr val="1A3C6E"/></a:dk1>
              <a:lt1><a:srgbClr val="FFFFFF"/></a:lt1>
              <a:dk2><a:srgbClr val="2E5A9C"/></a:dk2>
              <a:lt2><a:srgbClr val="F5F7FA"/></a:lt2>
              <a:accent1><a:srgbClr val="1A3C6E"/></a:accent1>
              <a:accent2><a:srgbClr val="4A6FA5"/></a:accent2>
              <a:accent3><a:srgbClr val="7BA3D0"/></a:accent3>
              <a:accent4><a:srgbClr val="2ECC71"/></a:accent4>
              <a:accent5><a:srgbClr val="E74C3C"/></a:accent5>
              <a:accent6><a:srgbClr val="F39C12"/></a:accent6>
              <a:hlink><a:srgbClr val="2E5A9C"/></a:hlink>
              <a:folHlink><a:srgbClr val="1A3C6E"/></a:folHlink>
            </a:clrScheme>
            <a:fontScheme name="CapHive Fonts">
              <a:majorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>
              <a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont>
            </a:fontScheme>
            <a:fmtScheme name="Office">
              <a:fillStyleLst>
                <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
                <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
                <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
              </a:fillStyleLst>
              <a:lnStyleLst>
                <a:ln w="6350" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>
                <a:ln w="12700" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>
                <a:ln w="19050" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>
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

      # ── document.xml ────────────────────────────────────────────────────────
      # Sample page demonstrating every named style. The export pipeline reads
      # the styles from styles.xml; the sample content here just makes it easy
      # to open the file in Word and verify the look before uploading a real one.
      document_xml = <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="#{wml}">
          <w:body>

            <!-- Cover -->
            <w:p><w:pPr><w:pStyle w:val="Title"/></w:pPr>
              <w:r><w:t>Portfolio Company Name</w:t></w:r>
            </w:p>
            <w:p><w:pPr><w:pStyle w:val="Subtitle"/></w:pPr>
              <w:r><w:t>Q1 2026 | Demo Fund</w:t></w:r>
            </w:p>

            <!-- Section heading -->
            <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>
              <w:r><w:t>Business Overview</w:t></w:r>
            </w:p>
            <w:p><w:pPr><w:pStyle w:val="BodyText"/></w:pPr>
              <w:r><w:t>This paragraph uses the Body Text style. Narrative prose generated by the LLM will be rendered here. The style controls line height, paragraph spacing, and font size.</w:t></w:r>
            </w:p>
            <w:p><w:pPr><w:pStyle w:val="ListBullet"/></w:pPr>
              <w:r><w:t xml:space="preserve">&#x2022;  Bullet point one — each LLM output item becomes a bullet</w:t></w:r>
            </w:p>
            <w:p><w:pPr><w:pStyle w:val="ListBullet"/></w:pPr>
              <w:r><w:t xml:space="preserve">&#x2022;  Bullet point two — consistent indentation and spacing</w:t></w:r>
            </w:p>

            <!-- Sub-section -->
            <w:p><w:pPr><w:pStyle w:val="Heading2"/></w:pPr>
              <w:r><w:t>Financial Highlights</w:t></w:r>
            </w:p>
            <w:p><w:pPr><w:pStyle w:val="BodyText"/></w:pPr>
              <w:r><w:t>Revenue grew 8% MoM to $1.44M. EBITDA positive at $120K. Burn rate holding below budget.</w:t></w:r>
            </w:p>

            <!-- KPI table sample -->
            <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>
              <w:r><w:t>Income Statement KPIs</w:t></w:r>
            </w:p>
            <w:tbl>
              <w:tblPr>
                <w:tblStyle w:val="TableGrid"/>
                <w:tblW w:w="9360" w:type="dxa"/>
              </w:tblPr>
              <!-- Header row -->
              <w:tr>
                <w:trPr><w:tblHeader/></w:trPr>
                <w:tc><w:tcPr><w:shd w:val="clear" w:color="auto" w:fill="1A3C6E"/></w:tcPr>
                  <w:p><w:r><w:rPr><w:b/><w:color w:val="FFFFFF"/></w:rPr><w:t>Metric</w:t></w:r></w:p></w:tc>
                <w:tc><w:tcPr><w:shd w:val="clear" w:color="auto" w:fill="1A3C6E"/></w:tcPr>
                  <w:p><w:r><w:rPr><w:b/><w:color w:val="FFFFFF"/></w:rPr><w:t>Dec 2025</w:t></w:r></w:p></w:tc>
                <w:tc><w:tcPr><w:shd w:val="clear" w:color="auto" w:fill="1A3C6E"/></w:tcPr>
                  <w:p><w:r><w:rPr><w:b/><w:color w:val="FFFFFF"/></w:rPr><w:t>Jan 2026</w:t></w:r></w:p></w:tc>
                <w:tc><w:tcPr><w:shd w:val="clear" w:color="auto" w:fill="1A3C6E"/></w:tcPr>
                  <w:p><w:r><w:rPr><w:b/><w:color w:val="FFFFFF"/></w:rPr><w:t>Feb 2026</w:t></w:r></w:p></w:tc>
              </w:tr>
              <!-- Data rows -->
              <w:tr>
                <w:tc><w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Revenue</w:t></w:r></w:p></w:tc>
                <w:tc><w:p><w:r><w:t>$1.20M</w:t></w:r></w:p></w:tc>
                <w:tc><w:p><w:r><w:t>$1.30M</w:t></w:r></w:p></w:tc>
                <w:tc><w:p><w:r><w:t>$1.40M</w:t></w:r></w:p></w:tc>
              </w:tr>
              <w:tr>
                <w:tc><w:tcPr><w:shd w:val="clear" w:color="auto" w:fill="F0F4FA"/></w:tcPr>
                  <w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Gross Profit</w:t></w:r></w:p></w:tc>
                <w:tc><w:tcPr><w:shd w:val="clear" w:color="auto" w:fill="F0F4FA"/></w:tcPr>
                  <w:p><w:r><w:t>$0.48M</w:t></w:r></w:p></w:tc>
                <w:tc><w:tcPr><w:shd w:val="clear" w:color="auto" w:fill="F0F4FA"/></w:tcPr>
                  <w:p><w:r><w:t>$0.51M</w:t></w:r></w:p></w:tc>
                <w:tc><w:tcPr><w:shd w:val="clear" w:color="auto" w:fill="F0F4FA"/></w:tcPr>
                  <w:p><w:r><w:t>$0.55M</w:t></w:r></w:p></w:tc>
              </w:tr>
              <w:tr>
                <w:tc><w:p><w:r><w:rPr><w:b/></w:rPr><w:t>EBITDA</w:t></w:r></w:p></w:tc>
                <w:tc><w:p><w:r><w:t>$0.12M</w:t></w:r></w:p></w:tc>
                <w:tc><w:p><w:r><w:t>$0.13M</w:t></w:r></w:p></w:tc>
                <w:tc><w:p><w:r><w:t>$0.14M</w:t></w:r></w:p></w:tc>
              </w:tr>
            </w:tbl>
            <w:p><w:pPr><w:pStyle w:val="Caption"/></w:pPr>
              <w:r><w:t>Table 1 — Income Statement KPIs (Actuals, USD millions)</w:t></w:r>
            </w:p>

            <!-- Risks section -->
            <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>
              <w:r><w:t>Risks and Outlook</w:t></w:r>
            </w:p>
            <w:p><w:pPr><w:pStyle w:val="ListBullet"/></w:pPr>
              <w:r><w:t xml:space="preserve">&#x2022;  CAC payback period 18 months vs 14-month target — management tracking to close gap by Q3.</w:t></w:r>
            </w:p>
            <w:p><w:pPr><w:pStyle w:val="ListBullet"/></w:pPr>
              <w:r><w:t xml:space="preserve">&#x2022;  Enterprise pipeline conversion risk — 4 late-stage deals totalling $420K ARR.</w:t></w:r>
            </w:p>
            <w:p><w:pPr><w:pStyle w:val="ListBullet"/></w:pPr>
              <w:r><w:t xml:space="preserve">&#x2022;  Tier-1 bank partnership live — expected to contribute 15% of new ARR in H2.</w:t></w:r>
            </w:p>

            <w:sectPr>
              <w:pgSz w:w="12240" w:h="15840"/>
              <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>
            </w:sectPr>
          </w:body>
        </w:document>
      XML

      # Write to a tempfile so Shrine can attach it as a real file
      style_doc = nil
      tmp = Tempfile.new(["seed_style_reference", ".docx"])
      begin
        Zip::OutputStream.open(tmp.path) do |zip|
          zip.put_next_entry("[Content_Types].xml");              zip.write content_types_xml
          zip.put_next_entry("_rels/.rels");                      zip.write pkg_rels_xml
          zip.put_next_entry("word/document.xml");                zip.write document_xml
          zip.put_next_entry("word/_rels/document.xml.rels");     zip.write doc_rels_xml
          zip.put_next_entry("word/styles.xml");                  zip.write styles_xml
          zip.put_next_entry("word/theme/theme1.xml");            zip.write theme_xml
        end

        style_doc = Document.create!(
          name:      style_doc_name,
          owner:     template,
          file:      File.open(tmp.path, "rb"),
          user:      user,
          orignal:   true,
          owner_tag: "Style"
        )
      ensure
        tmp.close
        tmp.unlink
      end

      template.update!(style_document: style_doc)
      puts "  [created] Style document id=#{style_doc.id} '#{style_doc_name}'"
    end

    puts

    # ── 5b. Additional templates from public sample uploads ──────────────────────
    # Attaches the pre-built placeholder / brand-theme files from
    # public/sample_uploads/portfolio_report_templates/ as style references.

    sample_dir = Rails.root.join("public", "sample_uploads", "portfolio_report_templates")

    sample_templates = [
      {
        name:          "Test Analyst Report — Word Placeholder",
        output_format: "word",
        file:          sample_dir.join("word_placeholder_template.docx"),
        branding:      { primary_color: "#047857", font: "Calibri" },
        kpi_layout:    { categories: [], tags: ["Actual"], n_periods: 6, side_by_side: false }
      },
      {
        name:          "Test Analyst Report — PPT Placeholder",
        output_format: "ppt",
        file:          sample_dir.join("ppt_placeholder_template.pptx"),
        branding:      { ppt_theme: "pastel", primary_color: "#047857", font: "Calibri" },
        kpi_layout:    { categories: [], tags: ["Actual"], n_periods: 6, side_by_side: false }
      },
      {
        name:          "Test Analyst Report — PPT Brand Theme",
        output_format: "ppt",
        file:          sample_dir.join("brand_template_emerald.pptx"),
        branding:      { ppt_theme: "pastel", primary_color: "#047857", font: "Calibri" },
        kpi_layout:    { categories: [], tags: ["Actual"], n_periods: 6, side_by_side: false }
      }
    ]

    sample_templates.each do |cfg|
      unless File.exist?(cfg[:file])
        puts "  [skip]    Sample file missing: #{cfg[:file]} — run rails portfolio_report:generate_#{cfg[:output_format] == 'word' ? 'word' : cfg[:name].include?('Brand') ? 'brand' : 'ppt'}_template first"
        next
      end

      tmpl = PortfolioReportTemplate.find_by(portfolio_report_id: portfolio_report.id, name: cfg[:name])
      unless tmpl
        tmpl = PortfolioReportTemplate.create!(
          portfolio_report: portfolio_report,
          name:             cfg[:name],
          output_format:    cfg[:output_format],
          section_order:    section_ids,
          kpi_layout:       cfg[:kpi_layout],
          branding:         cfg[:branding]
        )
        puts "  [created] PortfolioReportTemplate id=#{tmpl.id} '#{cfg[:name]}'"
      else
        puts "  [ok]      PortfolioReportTemplate id=#{tmpl.id} '#{cfg[:name]}'"
      end

      if tmpl.style_document.present?
        puts "  [ok]      Style document already set: '#{tmpl.style_document.name}'"
      else
        doc = Document.create!(
          owner:     tmpl,
          name:      File.basename(cfg[:file].to_s),
          file:      File.open(cfg[:file].to_s, "rb"),
          user:      user,
          orignal:   true,
          owner_tag: "Style"
        )
        tmpl.update!(style_document: doc)
        puts "  [created] Style document id=#{doc.id} '#{doc.name}' → set as style reference"
      end
    end

    puts

    # ── 6. Notes — narrative context for the LLM ────────────────────────────────

    notes_content = [
      {
        details: "Board meeting held. Management presented Q1 results showing strong revenue growth of 28% YoY. Key concern raised around rising CAC in the SEA market. CEO committed to improving payback period from 18 to 14 months by Q3.",
        tags:    "SaaS,Growth"
      },
      {
        details: "Engineering team expanded by 12 engineers in Q1. New VP of Engineering hired from a Series C SaaS company. Product roadmap for next 6 months approved — focuses on enterprise tier features and API integrations.",
        tags:    "SaaS,Growth"
      },
      {
        details: "Competitive landscape update: two new entrants in the market but both focused on SMB segment. Company's enterprise moat remains intact. Partnership with a Tier-1 bank signed — expected to contribute 15% of new ARR in H2.",
        tags:    "SaaS,Growth"
      }
    ]

    existing_count = Note.where(entity_id: entity.id, investor_id: portco.id).count

    if existing_count >= notes_content.length
      puts "  [ok]      #{existing_count} notes already present"
    else
      notes_content.each_with_index do |note_attrs, idx|
        Note.create!(
          entity_id:   entity.id,
          investor_id: portco.id,
          user_id:     user.id,
          details:     note_attrs[:details],
          tags:        note_attrs[:tags]
        )
        puts "  [created] Note #{idx + 1}"
      end
    end

    puts

    # ── 7. PortfolioReportExtracts — fake LLM output for the Extracts tab ───────
    # One extract per quarter (last 2 quarters), no section_id (whole-report extract).

    sections = portfolio_report.portfolio_report_sections.order(:id)

    extract_periods = [
      { start_date: 3.months.ago.beginning_of_month.to_date,
        end_date:   3.months.ago.end_of_month.to_date },
      { start_date: 1.month.ago.beginning_of_month.to_date,
        end_date:   1.month.ago.end_of_month.to_date }
    ]

    extract_data_by_period = [
      # Period 1 — slightly earlier quarter
      {
        "Business Overview" => [
          "SaaS platform serving mid-market and enterprise clients across APAC.",
          "Completed Series B at $45M; runway extended to 24 months.",
          "New enterprise tier launched, targeting Fortune 500 procurement teams.",
          "Market share in core SEA verticals estimated at 18%, up from 14% a year ago."
        ],
        "Financial Highlights" => [
          "Revenue reached $1.44M for the month, representing 27% YoY growth.",
          "Gross margin steady at 40%, in line with prior quarters.",
          "EBITDA positive at $120K; burn rate tracking below budget at $150K/month.",
          "MRR crossed $100K milestone — management target achieved 1 month ahead of plan."
        ],
        "Operational Metrics" => [
          "Active users grew 5% MoM to 25,000; retention cohorts remain strong at 88%.",
          "Headcount at 82 FTEs following 12 new engineering hires in Q1.",
          "Monthly churn rate at 2.1%, down from 2.6% in the same period last year.",
          "Customer support ticket volume stable; NPS improved 4 points to 47."
        ],
        "Risks & Outlook" => [
          "Rising CAC in SEA market (+22% YoY); payback period now 18 months vs 14-month target.",
          "Two new entrants noted but both focused on SMB — enterprise moat appears intact.",
          "Tier-1 bank partnership signed; projected to contribute 15% of new ARR in H2.",
          "Near-term outlook positive; key risk is sales cycle elongation in enterprise segment."
        ]
      },
      # Period 2 — most recent month
      {
        "Business Overview" => [
          "Continued expansion in enterprise segment; 3 new logos signed in the period.",
          "Product roadmap approved for next 6 months: enterprise tier features and API integrations.",
          "New VP Engineering onboarded; engineering headcount target lifted to 100 by year-end.",
          "No material changes to competitive positioning; Tier-1 bank partnership now live."
        ],
        "Financial Highlights" => [
          "Revenue up to approximately $1.56M, tracking ahead of board budget.",
          "EBITDA improved to $130K; management expects continued operating leverage.",
          "Burn rate held at $153K — marginal increase due to new engineering hires.",
          "ARR now exceeds $1.2M annualised run rate; Series B proceeds 60% deployed."
        ],
        "Operational Metrics" => [
          "Active users reached 26,250 — 5th consecutive month of 5%+ MoM growth.",
          "Headcount increased to 84 FTEs; two senior hires pending offer acceptance.",
          "Churn rate improved to 2.04%, best reading in 18 months.",
          "API integration usage up 30% MoM following enterprise tier release."
        ],
        "Risks & Outlook" => [
          "CAC payback period improving but still above 14-month target; management confident of Q3 improvement.",
          "Enterprise pipeline conversion risk: 4 deals in late-stage negotiation totalling $420K ARR.",
          "Macro headwinds in key verticals (financial services) could delay deal closures.",
          "Outlook: on track for full-year revenue target; H2 growth dependent on bank partnership ramp."
        ]
      }
    ]

    # Build a section name → section_id lookup for convenience
    section_map = sections.index_by(&:name)

    extract_periods.each_with_index do |period, idx|
      existing = PortfolioReportExtract.find_by(
        entity_id:            entity.id,
        portfolio_company_id: portco.id,
        portfolio_report_id:  portfolio_report.id,
        start_date:           period[:start_date],
        end_date:             period[:end_date]
      )

      if existing
        puts "  [ok]      PortfolioReportExtract id=#{existing.id} (#{period[:start_date]} – #{period[:end_date]})"
      else
        extract = PortfolioReportExtract.create!(
          entity_id:                 entity.id,
          portfolio_company_id:      portco.id,
          portfolio_report_id:       portfolio_report.id,
          portfolio_report_section_id: nil,   # whole-report extract, not per-section
          start_date:                period[:start_date],
          end_date:                  period[:end_date],
          data:                      extract_data_by_period[idx]
        )
        puts "  [created] PortfolioReportExtract id=#{extract.id} (#{period[:start_date]} – #{period[:end_date]})"
      end
    end

    puts
    puts "=" * 60
    puts "Seed complete. Use these values in the manual testing guide:"
    puts "  Portfolio company id : #{portco.id}"
    puts "  PortfolioReport id   : #{portfolio_report.id} (#{report_name})"
    puts "  Template id          : #{template.id} (#{template_name})"
    puts "  Entity id            : #{entity.id} (#{entity.name})"
    puts
    puts "Generate report at:"
    puts "  /investors/#{portco.id}/generate_reports"
    puts
    puts "Extracts tab:"
    puts "  /portfolio_reports/#{portfolio_report.id} → Extracts tab"
    puts "=" * 60
  end
end
