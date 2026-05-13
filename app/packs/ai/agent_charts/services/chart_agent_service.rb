# app/agents/chart_agent.rb
require "json"
require "ruby_llm"

class ChartAgentService
  # Minimal whitelist to keep outputs valid for Chart.js
  ALLOWED_TYPES = %w[bar line pie doughnut scatter radar polarArea].freeze

  def initialize(csv_paths: [], json_data: nil, entity: nil)
    @csv_paths = csv_paths # array of paths to .csv files on disk
    @json_data = json_data
    # entity is used by LlmService.ruby_llm_chat to pick entity-specific API keys
    # (Gemini, OpenAI, Anthropic). When nil, falls back to global credentials.
    @entity = entity
  end

  def build_system_msg
    <<~SYS
      You are a Chart.js v4 config generator.

      TASK: Output ONLY a single JSON object representing a valid Chart.js configuration. The JSON must follow this structure exactly:

      {
        "type": "<one of: #{ALLOWED_TYPES.join(', ')}>",
        "data": {
          "labels": [<strings or numbers>],
          "datasets": [
            {
              "label": "<name>",
              "data": [<numbers>],
              "borderWidth": 1
            }
          ]
        },
        "options": { }
      }

      STRICT RULES:
      - Output ONLY raw JSON. No markdown, no comments, no code fences, no explanation.
      - JSON must be syntactically valid and self-contained (e.g., ensure all colons and brackets are correctly placed).
      - Use ONLY Chart.js v4 fields. Do NOT add any fields not recognized by Chart.js.
      - CRITICAL: Ensure every dataset has a "data" key. Dataset format: {"label": "...", "data": [...]}.
      - DO NOT add tooltip callbacks, plugin definitions, scales configuration, or extra options unless explicitly requested in the user prompt.
      - If tooltip callbacks ARE requested, ALL of them must be valid functions inside `options.plugins.tooltip.callbacks` and NEVER strings, numbers, arrays, objects, or null.
      - NEVER generate a callback unless it is explicitly requested; omit the entire tooltip block otherwise.

      DATA RULES:
      - If CSV files are provided, use them as the primary quantitative data source.
      - If JSON is provided, treat it as metadata or supplementary configuration and merge sensibly.
      - If both CSV and JSON are provided, reconcile them: CSV drives datasets, JSON drives metadata/options.
      - If multiple CSV files are provided, treat each as a separate dataset or dimension. Combine or compare them only if this satisfies the user request.
      - All dataset arrays must be equal length where required by Chart.js. Do not invent or remove data; align sensibly with labels.
      - If labels represent dates, represent them as ISO-8601 strings.

      ADDITIONAL RULES:
      - Prefer minimal, correct defaults. Do NOT invent additional visual properties such as colors unless specifically asked for.
      - Do NOT reference undefined variables.
      - If the user request cannot be satisfied within Chart.js rules, adjust the data minimally to produce valid JSON.


    SYS
  end

  def build_user_msg(prompt)
    <<~USER
      USER PROMPT:
      #{prompt}

      JSON INPUT (may be nil):
      #{JSON.dump(@json_data)}

      IMPORTANT:
      - Output must be a single JSON object (no backticks).
    USER
  end

  # Returns a Ruby Hash ready to pass to Chart.js on the frontend.
  def generate_chart!(prompt:)
    # NOTE: must use @entity (instance variable), not bare `entity` — this class has no
    # entity method and calling it bare raises NameError.
    chat = LlmService.ruby_llm_chat(entity: @entity)

    system_msg = build_system_msg
    user_msg   = build_user_msg(prompt)

    Rails.logger.debug user_msg.inspect

    raw = ask_llm(chat, system_msg, user_msg)
    Rails.logger.debug raw.inspect

    config = parse_json(raw)

    # Retry once with an explicit correction prompt if the first parse attempt
    # failed.  LLM output occasionally includes stray markdown fences or trailing
    # characters that survive parse_json’s cleanup; a single nudge usually fixes it
    # because the conversation context is preserved across chat.ask calls.
    if config.nil?
      Rails.logger.warn "ChartAgentService: first parse attempt failed, retrying with correction prompt"
      raw    = chat.ask("Your previous response was not valid JSON. Output ONLY a raw JSON object — no markdown, no code fences, no explanation.")
      config = parse_json(raw)
    end

    validate_chartjs!(config)
    cleanup
    config
  end

  private

  # Sends the system primer and user prompt as two separate turns in all cases.
  # Previously, the non-CSV path concatenated both into a single string, causing
  # the LLM to treat instructions and data as one blob — producing less reliable JSON.
  # Now both paths use a two-turn structure: system primer first, user data second.
  def ask_llm(chat, system_msg, user_msg)
    chat.ask(system_msg) # prime with instructions
    if @csv_paths.any?
      chat.ask(user_msg, with: @csv_paths)
    else
      chat.ask(user_msg)
    end
  end

  def cleanup
    @csv_paths.each do |path|
      FileUtils.rm_f(path)
    end
  end

  def parse_json(obj)
    case obj
    when String
      begin
        # strip accidental fences if any
        cleaned = obj.strip
        cleaned = cleaned.sub(/\A```(?:json)?\s*/i, "").sub(/\s*```\z/, "")
        JSON.parse(cleaned)
      rescue JSON::ParserError
        nil
      end
    when Hash
      obj
    when RubyLLM::Message
      parse_json(obj.content.is_a?(RubyLLM::Content) ? obj.content.text : obj.content) # Recursively call with the text content
    when nil
      nil
    end
  end

  def validate_chartjs!(cfg)
    raise "Chart config is empty" unless cfg.is_a?(Hash)

    type = cfg["type"]
    data = cfg["data"]
    raise "Missing type" unless type.is_a?(String)
    raise "Unsupported type: #{type}" unless ALLOWED_TYPES.include?(type)

    raise "Missing data" unless data.is_a?(Hash)

    labels   = data["labels"]
    datasets = data["datasets"]
    raise "data.labels must be an Array" unless labels.is_a?(Array)
    raise "data.datasets must be an Array" unless datasets.is_a?(Array)
    raise "datasets cannot be empty" if datasets.empty?

    datasets.each_with_index do |ds, idx|
      raise "datasets[#{idx}] must be an object with a data array" unless ds.is_a?(Hash) && ds["data"].is_a?(Array)
    end

    cfg["options"] ||= {}

    # Always enforce responsive sizing so the chart fills its container and
    # respects the canvas height set by the chart-renderer Stimulus controller.
    # Chart.js defaults maintainAspectRatio to true, which ignores any fixed height
    # and derives it from the width instead — overriding this lets CSS/inline style
    # on the canvas element control the actual rendered size.
    cfg["options"]["responsive"]          = true
    cfg["options"]["maintainAspectRatio"] = false

    cfg
  end
end
