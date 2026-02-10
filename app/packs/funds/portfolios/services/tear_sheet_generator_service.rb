# frozen_string_literal: true

class TearSheetGeneratorService
  SYSTEM_PROMPT = <<~PROMPT
    Role: You are an expert UI/UX and Presentation Designer specializing in "2026 Modern Minimalist" aesthetics.
    Task: Generate slide layouts that prioritize negative space, asymmetric grids, and high-quality typography. Move away from container-heavy designs to a "Bento Grid" or "Open Canvas" approach.

    ### 1. Visual Design Principles
    - Layout: Use a 12-column grid. Avoid equal-sized boxes. Use varying widths (e.g., a 2/3 and 1/3 split) to create visual interest.
    - Typography: Use a bold, high-contrast sans-serif for headers (weight 700-800) and a clean, light sans-serif for body text (weight 300-400).
    - Containers: Replace solid boxes with subtle "Glassmorphism." Use a light background blur or ultra-thin 1px borders. Use border-radius: 24px for a softer, modern look.
    - Spacing: Implement "Breathable Design." Ensure margins are at least 8% of the slide width.

    ### 2. Dynamic Tabler Icon Logic
    For every key data point or section, you MUST select a relevant Tabler Icon (e.g., `icon-currency-rupee`, `icon-rocket`).
    - Placement: Place icons in the top-left or centered-above the text.
    - Styling: Use a consistent 1.5px or 2px stroke (standard in Tabler).
    - Mapping Hints:
      - Financials/Money → `icon-currency-rupee`, `icon-cash`, `icon-chart-dots`
      - Growth/Positive Trends → `icon-trending-up`, `icon-rocket`, `icon-arrow-up-right`
      - Logistics/Supply Chain → `icon-truck`, `icon-box`, `icon-map-pin-2`
      - Technology/Future → `icon-cpu`, `icon-sparkles`, `icon-bolt`
      - Infrastructure → `icon-building-warehouse`, `icon-stack-2`

    ### 3. Data Visualization
    - Big Numbers: Make KPI numbers (e.g., "₹2,194 Cr") the hero of the slide. Use a larger font size than the header.
    - Context: Place "YoY" or "Growth" metrics in small, pill-shaped badges next to the main number using `icon-arrow-narrow-up`.

    ### 4. Slide-Specific Directives
    - Financials/Metrics: Use a "Bento Box" layout. The primary metric gets the largest cell; secondary metrics fill the remaining grid (using grid-cols-12 and col-span-x).
    - Operational Wins/Highlights: Use a list but remove the boxes. Use a thin vertical line to connect the icons, creating a "timeline" feel.
    - Future Outlook/Thesis: Use a "Two-Thirds" split. The left 66% for narrative text; the right 33% is a clean list of "Key Takeaways" marked with `icon-circle-check-filled`.

    AVAILABLE TEMPLATES:
    1. `cover`: The title slide.
       - Schema: { "template": "cover", "title": string, "subtitle": string, "logo_url": string (optional) }
    2. `key_metrics`: Highlight 4-6 critical KPIs in a Bento Grid.
       - Schema: { "template": "key_metrics", "title": string, "metrics": [ { "label": string, "value": string, "trend": string (optional), "trend_direction": "up"|"down" (optional), "icon": string (optional), "description": string (optional) } ] }
    3. `strategic_highlights`: 3-4 major developments or operational wins.
       - Schema: { "template": "strategic_highlights", "title": string, "highlights": [ { "title": string, "description": string, "icon": string (optional) } ] }
    4. `investment_thesis`: The core value proposition and analytical outlook.
       - Schema: { "template": "investment_thesis", "title": string, "analysis": string (narrative), "points": [ string (key takeaways) ] }
    5. `risks`: Identify and categorize potential threats.
       - Schema: { "template": "risks", "title": string, "risks": [ { "category": string, "impact": "low"|"medium"|"high", "mitigation": string, "icon": string (optional) } ] }
    6. `portfolio_investments`: A detailed list of investments held by the company.
       - Schema: { "template": "portfolio_investments", "title": "Portfolio Investments", "investments": [ { "date": string, "fmv": string, "instrument": string, "category": string, "notes": string } ] }

    ### 5. Final Output
    RETURN ONLY A VALID JSON ARRAY OF SLIDE OBJECTS. No commentary.
  PROMPT

  KPI_SYSTEM_PROMPT = <<~PROMPT
    Role: You are an expert Financial Data Analyst and Presentation Designer.
    Task: Generate a detailed `kpi_table` slide for a Portfolio Company Tear Sheet, formatted as a matrix/table.

    AESTHETIC: "2026 Modern Minimalist". Professional, clean, and high-contrast.

    ### Slide Schema
    `kpi_table`: A matrix view of performance indicators over time.
    - Schema:
      {
        "template": "kpi_table",
        "title": string,
        "columns": [ { "key": string, "label": string, "sub_label": string (optional) } ],
        "rows": [
          {
            "kpi_id": integer,
            "kpi": string,
            "category": string,
            "data": {
              "column_key": { "value": string, "change": string (optional), "trend_direction": "up"|"down"|"neutral" }
            },
            "notes": string (optional)
          }
        ]
      }

    ### Strict Directives
    1. Data Structure: pivot the provided flat data into columns (Periods like "2024", "2023" or "Mar 2024", "Mar 2023") and rows (KPIs).
    2. Columns: Identify the distinct periods from the data and create columns for them. Sort columns chronologically descending (newest first).
    3. Rows: Group data by KPI. Each row represents one KPI.
    4. Data Mapping: Map the values to the correct column key for that row.
    5. Formatting: Format large numbers (Cr, L) consistently.
    6. Trends: Calculate or use provided percentage changes for the `change` field.

    RETURN ONLY A VALID JSON OBJECT FOR THE SLIDE. No commentary. The output must be a single JSON object.
  PROMPT

  def initialize(extract_id:)
    @extract = PortfolioReportExtract.find(extract_id)
  end

  def call(force_generate: false, palette: "serene_blue")
    unless [true, "true"].include?(force_generate)
      existing = @extract.tear_sheet_presentation
      return existing.content_html if existing
    end

    blueprint = generate_blueprint
    # Ensure we use a deep copy for rendering because partials/logic might mutate the hashes
    rendering_blueprint = JSON.parse(blueprint.to_json)
    html = render_slides(rendering_blueprint, palette: palette)

    store_presentation(html, blueprint, palette: palette)
    html
  end

  private

  def generate_blueprint
    main_blueprint = Array(generate_main_blueprint)
    kpi_blueprint = generate_kpi_blueprint

    Rails.logger.debug { "[TearSheetGeneratorService] Main Blueprint Size: #{main_blueprint.size}" }
    Rails.logger.debug { "[TearSheetGeneratorService] KPI Blueprint Present: #{!kpi_blueprint.nil?}" }

    combined = main_blueprint
    if kpi_blueprint.is_a?(Hash)
      combined << kpi_blueprint
    elsif kpi_blueprint.is_a?(Array)
      combined += kpi_blueprint
    end

    combined.select! { |s| s.is_a?(Hash) }

    # Final check before return
    combined.each_with_index do |s, i|
      Rails.logger.debug "[TearSheetGeneratorService] Blueprint Slide #{i} Template: #{s['template'] || s[:template] || 'MISSING'}"
    end

    combined
  end

  def generate_main_blueprint
    report = @extract.portfolio_report
    pc = @extract.portfolio_company

    transcript_data = begin
      JSON.parse(@extract.data)
    rescue StandardError
      { raw_data: @extract.data.to_s }
    end

    # Purge KPIs from main call to reduce noise
    transcript_data.delete("portfolio_kpis")
    transcript_data.delete(:portfolio_kpis)

    if report&.include_portfolio_investments && pc
      inv_data = pc.portfolio_investments.as_json(
        only: %i[investment_date quantity fmv_cents folio_id notes category],
        include: { investment_instrument: { only: [:name] } }
      )
      Rails.logger.debug { "[TearSheetGeneratorService] Adding #{inv_data.size} investments to transcript" }
      transcript_data[:portfolio_investments] = inv_data
    end

    prompt_data = JSON.pretty_generate(transcript_data)
    Rails.logger.debug { "[TearSheetGeneratorService] Main Transcript Keys: #{transcript_data.keys}" }
    prompt = "#{SYSTEM_PROMPT}\n\nEXTRACTED DATA:\n#{prompt_data}"

    content = ask_llm(prompt)
    JSON.parse(extract_json(content))
  rescue StandardError => e
    Rails.logger.error "[TearSheetGeneratorService] Main Blueprint Error: #{e.message}"
    []
  end

  def generate_kpi_blueprint
    report = @extract.portfolio_report
    pc = @extract.portfolio_company
    Rails.logger.debug { "[TearSheetGeneratorService] Generating KPI Blueprint. Report: #{report&.id}, Include KPI: #{report&.include_kpi}, PC: #{pc&.id}" }
    return nil unless report&.include_kpi && pc

    kpi_data = pc.portfolio_kpis.show_in_report.yearly.actuals
                 .select("kpis.*, kpi_reports.as_of as as_of_date")
                 .order("kpi_reports.as_of DESC")
                 .as_json(
                   only: %i[id name value display_value percentage_change notes],
                   methods: [:as_of_date]
                 ).map { |k| k.transform_keys { |key| key == "id" ? "kpi_id" : key } }

    # Grouping logic can be handled by LLM, but let's ensure it has enough info
    # The existing query `yearly.actuals` and order `as_of DESC` is good.

    Rails.logger.debug { "[TearSheetGeneratorService] KPI Data Count: #{kpi_data.size}" }
    Rails.logger.debug { "[TearSheetGeneratorService] KPI Data Sample: #{kpi_data.first.inspect}" } if kpi_data.any?
    return nil if kpi_data.empty?

    transcript_data = { portfolio_kpis: kpi_data }
    prompt = "#{KPI_SYSTEM_PROMPT}\n\nEXTRACTED DATA:\n#{JSON.pretty_generate(transcript_data)}"
    Rails.logger.debug { "[TearSheetGeneratorService] KPI Prompt Length: #{prompt.length}" }

    content = ask_llm(prompt)
    Rails.logger.debug { "[TearSheetGeneratorService] KPI LLM Response: #{content}" }

    parsed = JSON.parse(extract_json(content))
    Rails.logger.debug { "[TearSheetGeneratorService] KPI Parsed: #{parsed.inspect}" }
    parsed
  rescue StandardError => e
    Rails.logger.error "[TearSheetGeneratorService] KPI Blueprint Error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    nil
  end

  def ask_llm(prompt)
    llm_chat = LlmService.ruby_llm_chat(entity: @extract.entity)
    response = llm_chat.ask(prompt)

    content = response.respond_to?(:content) ? response.content : response.to_s
    content.respond_to?(:text) ? content.text : content
  end

  def extract_json(content)
    if content =~ /```json\s*(.*?)\s*```/m
      ::Regexp.last_match(1)
    else
      content
    end
  end

  def render_slides(blueprint, palette: "serene_blue")
    renderer = ApplicationController.renderer.new

    # We wrap the slides in a div that the controller/view can use,
    # but the layout handles the body class.
    # To handle live updates via Turbo Stream, we might need to broadcast the class too.

    slides_html = blueprint.filter_map do |slide_data|
      # Defensive duplicate to prevent any downstream mutation
      data = slide_data.dup
      template = data.delete("template") || data.delete(:template)

      next unless %w[cover key_metrics strategic_highlights investment_thesis risks kpi_table portfolio_investments].include?(template)

      # Ensure data is clean for partials (recursive transformation)
      content_data = data.deep_symbolize_keys
      content_data[:palette] = palette

      renderer.render(
        partial: "tear_sheet_presentations/templates/#{template}",
        locals: content_data
      )
    end

    slides_html.join("\n")
  end

  def store_presentation(html, blueprint, palette: "serene_blue")
    presentation = TearSheetPresentation.find_or_initialize_by(
      portfolio_report_extract_id: @extract.id,
      entity_id: @extract.entity_id
    )

    Rails.logger.debug { "[TearSheetGeneratorService] Storing Blueprint. First Slide Template: #{blueprint.first ? (blueprint.first['template'] || blueprint.first[:template]) : 'N/A'}" }

    presentation.update!(
      title: "Tear Sheet: #{@extract.portfolio_company&.name || 'Company'}",
      blueprint: { slides: blueprint, palette: palette },
      content_html: html
    )
  end
end
