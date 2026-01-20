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
    2. `key_metrics`: Highlight 4-6 critical KPIs.
       - Schema: { "template": "key_metrics", "title": string, "metrics": [ { "label": string, "value": string, "trend": string (optional), "trend_direction": "up"|"down" (optional), "icon": string (optional, e.g. "trending-up"), "description": string (optional) } ] }
    3. `strategic_highlights`: 3-4 major developments or operational wins.
       - Schema: { "template": "strategic_highlights", "title": string, "highlights": [ { "title": string, "description": string, "icon": string (optional) } ] }
    4. `investment_thesis`: The core value proposition and analytical outlook.
       - Schema: { "template": "investment_thesis", "title": string, "analysis": string (narrative), "points": [ string (key takeaways) ] }
    5. `risks`: Identify and categorize potential threats.
       - Schema: { "template": "risks", "title": string, "risks": [ { "category": string, "impact": "low"|"medium"|"high", "mitigation": string, "icon": string (optional) } ] }

    RETURN ONLY A VALID JSON ARRAY OF SLIDE OBJECTS. No commentary.
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
    # Add palette to blueprint metadata if needed, but for now we'll just use it in store
    html = render_slides(blueprint, palette: palette)

    store_presentation(html, blueprint, palette: palette)
    html
  end

  private

  def generate_blueprint
    data_transcript = begin
      JSON.pretty_generate(JSON.parse(@extract.data))
    rescue StandardError
      @extract.data.to_s
    end

    prompt = "#{SYSTEM_PROMPT}\n\nEXTRACTED DATA:\n#{data_transcript}"

    llm_chat = RubyLLM.chat(model: ENV.fetch("DEFAULT_MODEL", nil))
    response = llm_chat.ask(prompt)

    content = response.respond_to?(:content) ? response.content : response.to_s
    content = content.text if content.respond_to?(:text)

    json_str = extract_json(content)
    JSON.parse(json_str)
  rescue StandardError => e
    Rails.logger.error "[TearSheetGeneratorService] LLM Error: #{e.message}"
    []
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
      template = slide_data.delete("template")
      next unless %w[cover key_metrics strategic_highlights investment_thesis risks].include?(template)

      # Ensure data is clean for partials (recursive transformation)
      content_data = slide_data.deep_symbolize_keys
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

    presentation.update!(
      title: "Tear Sheet: #{@extract.portfolio_company&.name || 'Company'}",
      blueprint: { slides: blueprint, palette: palette },
      content_html: html
    )
  end
end
