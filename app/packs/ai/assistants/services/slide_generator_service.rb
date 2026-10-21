# frozen_string_literal: true

class SlideGeneratorService
  SYSTEM_PROMPT = <<~PROMPT
    You are a world-class presentation designer known for "Swiss Style" minimalism and high-end corporate aesthetics (think Apple Keynote or modern Fintech decks).
    Your goal is to transform a raw chat transcript into a clean, sophisticated, and visually spacious "Slide Blueprint" (JSON).

    STYLE GUIDELINES:
    - TONE: Modern, Minimalist, Professional, Sophisticated.
    - TITLES: Clear, concise, and elegant. No "clickbait" style.
    - CONTENT: Distill complex data into clear insights. Prioritize whitespace and brevity.
    - FLOW: Start with a clear Hero slide, follow with 4-6 Insight/Chart/Comparison slides that tell a calm, data-backed story.
    - GRAPHS: Ensure all charts and graphs use a professional color palette. Avoid black and white or grayscale for data visualizations.

    AVAILABLE TEMPLATES & SCHEMAS:

    1. `hero` (Minimalist title slide):
       - `template`: "hero"
       - `title`: string
       - `subtitle`: string
       - `icon`: string (A Tabler Icon name without "ti-", e.g. "rocket", "chart-pie", "shield-check")

    2. `bullets` (Clean insights list/grid):
       - `template`: "bullets"
       - `title`: string
       - `items`: array of objects { text: string, icon: string (e.g. "bolt", "trending-up") }

    3. `split_chart` (Data visualization with clear analysis):
       - `template`: "split_chart"
       - `title`: string
       - `analysis`: string
       - `icon`: string (e.g. "presentation-analytics")
       - `chart_config`: object (Valid Chart.js config)

    4. `comparison` (Side-by-side comparison):
       - `template`: "comparison"
       - `title`: string
       - `left_col`: { title: string, icon: string, items: array of strings }
       - `right_col`: { title: string, icon: string, items: array of strings }

    INSTRUCTIONS:
    - For icons, always choose relevant Tabler Icons that match the data context.
    - If the transcript contains lists of numbers, use `split_chart`.
    - If the user asks for a comparison or vs, use `comparison`.
    - RETURN ONLY A VALID JSON ARRAY. No preamble.

    CHAT TRANSCRIPT:
  PROMPT

  def initialize(chat_id:)
    @chat = Chat.find(chat_id)
    @messages = @chat.messages.where(role: %w[user assistant]).order(:created_at)
  end

  def call(force_generate: false)
    Rails.logger.info "[SlideGeneratorService] Starting service for chat_id: #{@chat.id} (force_generate: #{force_generate})"

    unless [true, "true"].include?(force_generate)
      existing = AiPresentation.find_by(chat_id: @chat.id, entity_id: @chat.entity_id)
      if existing
        Rails.logger.info "[SlideGeneratorService] Returning stored presentation for chat_id: #{@chat.id}"
        return existing.content_html
      end
    end

    blueprint = generate_blueprint
    Rails.logger.info "[SlideGeneratorService] Successfully parsed #{blueprint.size} slides from blueprint"

    html = render_slides(blueprint)

    # Store the generated presentation
    store_presentation(html, blueprint)

    html
  end

  private

  def store_presentation(html, blueprint)
    ActiveRecord::Base.connected_to(role: :writing) do
      presentation = AiPresentation.find_or_initialize_by(chat_id: @chat.id, entity_id: @chat.entity_id)
      presentation.update!(
        content_html: html,
        blueprint: blueprint.to_json
      )
      Rails.logger.info "[SlideGeneratorService] Stored presentation for chat_id: #{@chat.id}"
    end
  rescue StandardError => e
    Rails.logger.error "[SlideGeneratorService] Failed to store presentation: #{e.message}\n#{e.backtrace.join("\n")}"
  end

  def generate_blueprint(entity: nil)
    ts = transcript
    Rails.logger.info "[SlideGeneratorService] Sending transcript to LLM (length: #{ts.length})"
    system_prompt = "#{SYSTEM_PROMPT}\n#{ts}"

    llm_chat = LlmService.ruby_llm_chat(entity: entity)
    response = llm_chat.ask(system_prompt)

    # Extract response content for logging
    content_to_log = response.respond_to?(:content) ? response.content : response.to_s
    content_to_log = content_to_log.text if content_to_log.respond_to?(:text)
    Rails.logger.info "[SlideGeneratorService] Raw LLM Response (truncated): #{content_to_log.to_s[0..500]}..."

    raw_content = extract_json(response)
    Rails.logger.info "[SlideGeneratorService] Extracted JSON content: #{raw_content}"

    JSON.parse(raw_content)
  rescue JSON::ParserError => e
    Rails.logger.error "[SlideGeneratorService] JSON Parsing Error: #{e.message}\n#{e.backtrace.join("\n")}"
    []
  rescue StandardError => e
    Rails.logger.error "[SlideGeneratorService] Error generating blueprint: #{e.message}\n#{e.backtrace.join("\n")}"
    []
  end

  def transcript
    @messages.map { |m| "#{m.role.upcase}: #{m.content}" }.join("\n\n")
  end

  def extract_json(response)
    content = response.respond_to?(:content) ? response.content : response.to_s
    # Handle content objects that wrap their text, if any
    content = content.text if content.respond_to?(:text)

    # Extract JSON from code blocks if present
    if content =~ /```json\s*(.*?)\s*```/m
      ::Regexp.last_match(1)
    else
      content
    end
  end

  def render_slides(blueprint)
    renderer = ApplicationController.renderer.new

    slides_html = blueprint.filter_map do |slide_data|
      template = slide_data.delete("template")
      next unless %w[hero bullets split_chart comparison].include?(template)

      Rails.logger.info "[SlideGeneratorService] Rendering slide template: #{template}"

      # Ensure data is clean for partials
      content_data = slide_data.symbolize_keys

      renderer.render(
        partial: "assistants/presentation_templates/#{template}",
        locals: content_data
      )
    end

    slides_html.join("\n")
  end
end
