# frozen_string_literal: true

# Turns an assistant conversation into a slide deck ("AI Slides"): the model writes a JSON blueprint of
# slides, and each slide type is drawn by a template in assistants/presentation_templates. Every slide
# explains itself ("What this means") and the deck has a real footer (record · date · n / total).
class SlideGeneratorService
  # Slide types the templates draw, in the order a deck uses them.
  TEMPLATES = %w[title key_figures insights chart table comparison next_steps].freeze
  # Slide types decks saved before the redesign used → the template that now draws them.
  LEGACY_TEMPLATES = { "hero" => "title", "bullets" => "insights", "split_chart" => "chart" }.freeze

  # The Tabler icons a slide may use. An icon outside this set falls back to its slide type's own, so a
  # made-up name never leaves an empty icon box.
  ICONS = %w[chart-line chart-bar chart-pie chart-dots trending-up trending-down coin currency-rupee
             currency-dollar cash wallet receipt report-money report-analytics building-bank building
             briefcase file-text files calendar calendar-event clock users user-check user-x id-badge
             shield-check shield-x alert-triangle circle-check circle-x info-circle bulb target scale
             arrows-exchange percentage presentation-analytics database list-check tool rocket flag world
             seeding certificate].freeze
  DEFAULT_ICONS = { "title" => "presentation-analytics", "key_figures" => "chart-dots", "insights" => "bulb",
                    "chart" => "chart-line", "table" => "database", "comparison" => "arrows-exchange",
                    "next_steps" => "list-check" }.freeze
  TONES = %w[positive negative neutral].freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You turn a conversation between a fund manager and CapHive's assistant into a short, clear slide deck.
    Return ONLY a JSON array of slides — no preamble, no code fence.

    RULES
    - 5 to 8 slides, in this order: one "title" slide, then "key_figures", then "insights" and/or "chart"
      slides, then "table" or "comparison" if they help, then "next_steps" only if something needs doing.
      Leave out any slide type the conversation has no material for. Never make an empty or filler slide.
    - Use only facts and numbers that appear in the conversation. Never invent figures, dates or names.
    - Every slide except "title" has a "takeaway": one plain sentence saying what the slide means for the
      reader (e.g. "Cost is fully covered: FMV is ₹8,551 above it.").
    - Titles are short statements of the point, not labels ("Revenue fell 62% in Q1 2025", not "Revenue").
    - #{AiChatAnswerLayout::AMOUNTS}
    - "icon" is one of: #{ICONS.join(', ')}.
    - "tone" is "positive", "negative" or "neutral" — whether the item is good news, bad news or neither.

    SLIDE TYPES (JSON fields)
    1. {"template":"title","title":…,"subtitle": one sentence on what the deck covers,
        "figures":[{"value":…,"label":…}] — up to 3 headline numbers}
    2. {"template":"key_figures","title":…,"icon":…,"figures":[{"value":…,"label":…,"context": a short
        comparison like "vs ₹2,25,665 cost","icon":…,"tone":…}] — 2 to 4,"takeaway":…}
    3. {"template":"insights","title":…,"icon":…,"items":[{"title": 2-5 words,"text": one sentence,
        "icon":…,"tone":…}] — 2 to 6,"takeaway":…}
    4. {"template":"chart","title":…,"icon":…,"chart_config": a Chart.js config (type line, bar or
        doughnut; data.labels and data.datasets with label and data),"notes":[up to 3 short sentences],
        "takeaway":…}
    5. {"template":"table","title":…,"icon":…,"columns":[…],"rows":[[…]] — up to 8 rows,
        "highlight": the name of the column that matters most,"takeaway":…}
    6. {"template":"comparison","title":…,"icon":…,"left":{"title":…,"icon":…,"items":[…]},
        "right":{"title":…,"icon":…,"items":[…]},"takeaway":…}
    7. {"template":"next_steps","title":…,"icon":…,"steps":[{"title":…,"text":…}] — 2 to 4,"takeaway":…}

    CONVERSATION:
  PROMPT

  # Draws a blueprint as slides — also used by tests and to redraw a saved blueprint.
  #
  # @param blueprint [Array<Hash>] the slides the model returned (string or symbol keys)
  # @param record [String] what the deck is about (the chat's record), for the footer
  # @param date [String] the deck's date, locale-formatted, for the footer
  # @return [String] the slides' HTML
  def self.render_blueprint(blueprint, record:, date:)
    slides = Array(blueprint).filter_map { |slide| normalize_slide(slide) }
    renderer = ApplicationController.renderer.new
    slides.each_with_index.map do |slide, index|
      renderer.render(partial: "assistants/presentation_templates/#{slide['template']}",
                      locals: { slide:, index: index + 1, total: slides.size, record:, date: })
    end.join("\n")
  end

  # One slide, made safe to draw: its template resolved (legacy names mapped), icons and tones limited to
  # the known sets, and nil when it has nothing to show (no empty slides).
  #
  # @param raw [Hash]
  # @return [Hash, nil]
  def self.normalize_slide(raw)
    # The blueprint comes from a model: anything that is not a slide object is skipped, never raised on.
    return nil unless raw.is_a?(Hash)

    slide = raw.deep_stringify_keys
    template = slide["template"].presence || infer_template(slide)
    template = LEGACY_TEMPLATES.fetch(template.to_s, template.to_s)
    return nil unless TEMPLATES.include?(template)

    slide = legacy_fields(slide.merge("template" => template))
    slide["icon"] = icon(slide["icon"], DEFAULT_ICONS[template])
    %w[figures items steps].each do |key|
      next unless slide[key].is_a?(Array)

      slide[key] = slide[key].filter_map do |entry|
        entry = { "text" => entry.to_s } unless entry.is_a?(Hash)
        entry.merge("icon" => icon(entry["icon"], slide["icon"]), "tone" => TONES.include?(entry["tone"]) ? entry["tone"] : "neutral")
      end
    end
    %w[left right].each { |side| slide[side] = slide[side].merge("icon" => icon(slide[side]["icon"], slide["icon"])) if slide[side].is_a?(Hash) }
    content?(slide) ? slide : nil
  end

  # Decks saved before the redesign lost their "template" key (the old renderer deleted it before the
  # blueprint was saved), so the slide type is read from the fields only that type had.
  #
  # @return [String, nil]
  def self.infer_template(slide)
    if slide["chart_config"] then "chart"
    elsif slide["left_col"] || slide["left"] then "comparison"
    elsif slide["items"] then "insights"
    elsif slide["subtitle"] || slide["title"] then "title"
    end
  end

  # Decks saved before the redesign named some fields differently.
  def self.legacy_fields(slide)
    slide["takeaway"] ||= slide.delete("analysis")
    slide["left"] ||= slide.delete("left_col")
    slide["right"] ||= slide.delete("right_col")
    slide
  end

  # @return [Boolean] whether the slide has what its template draws
  def self.content?(slide)
    case slide["template"]
    when "title" then slide["title"].present?
    when "key_figures" then Array(slide["figures"]).any? { |f| f["value"].present? }
    when "insights" then Array(slide["items"]).any? { |i| i["text"].present? || i["title"].present? }
    when "chart" then chart_data?(slide["chart_config"])
    when "table" then Array(slide["columns"]).any? && Array(slide["rows"]).any?
    when "comparison" then slide["left"].is_a?(Hash) && slide["right"].is_a?(Hash)
    when "next_steps" then Array(slide["steps"]).any?
    end
  end

  # @return [Boolean] whether a model-written chart config has a data object with datasets (anything else,
  #   e.g. "data" as a string, would raise when the template reads it)
  def self.chart_data?(config)
    config.is_a?(Hash) && config["data"].is_a?(Hash) && Array(config["data"]["datasets"]).any?
  end

  # @return [String] the icon when it is a known Tabler icon, else the fallback
  def self.icon(name, fallback)
    name = name.to_s.delete_prefix("ti-")
    ICONS.include?(name) ? name : fallback
  end

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
        # Redraw the saved blueprint with today's templates (no AI call), so saved decks get template fixes;
        # the saved HTML only when the blueprint draws nothing.
        return redraw(existing).presence || existing.content_html
      end
    end

    blueprint = generate_blueprint
    Rails.logger.info "[SlideGeneratorService] Successfully parsed #{blueprint.size} slides from blueprint"

    html = self.class.render_blueprint(blueprint, record: deck_record, date: I18n.l(Time.zone.today))

    # Store the generated presentation
    store_presentation(html, blueprint)

    html
  end

  private

  # What the deck is about: the chat's record (a fund, a company, a commitment), else the chat's name.
  def deck_record
    owner = @chat.owner
    return @chat.name.to_s if owner.nil? || owner.is_a?(User)

    owner.try(:name).presence || owner.to_s
  end

  # A saved deck drawn again from its blueprint, dated when it was made.
  #
  # @param presentation [AiPresentation]
  # @return [String] the slides' HTML ("" when the blueprint is unreadable or draws nothing)
  def redraw(presentation)
    blueprint = JSON.parse(presentation.blueprint.to_s)
    self.class.render_blueprint(blueprint, record: deck_record, date: I18n.l(presentation.created_at.to_date))
  rescue JSON::ParserError
    ""
  end

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

  def generate_blueprint
    ts = transcript
    Rails.logger.info "[SlideGeneratorService] Sending transcript to LLM (length: #{ts.length})"

    llm_chat = LlmService.ruby_llm_chat(entity: @chat.entity)
    response = llm_chat.ask("#{SYSTEM_PROMPT}\n#{ts}")

    raw_content = extract_json(response)
    Rails.logger.info "[SlideGeneratorService] Raw LLM blueprint (truncated): #{raw_content.to_s[0..500]}..."

    parsed = JSON.parse(raw_content)
    parsed.is_a?(Array) ? parsed : []
  rescue JSON::ParserError => e
    Rails.logger.error "[SlideGeneratorService] JSON Parsing Error: #{e.message}"
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
    if content =~ /```(?:json)?\s*(.*?)\s*```/m
      ::Regexp.last_match(1)
    else
      content
    end
  end
end
