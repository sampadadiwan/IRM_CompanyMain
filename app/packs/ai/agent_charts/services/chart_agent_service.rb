# app/agents/chart_agent.rb
require "json"
require "ruby_llm"

class ChartAgentService
  # Minimal whitelist to keep outputs valid for Chart.js
  ALLOWED_TYPES = %w[bar line pie doughnut scatter radar polarArea].freeze

  def initialize(csv_paths: [], json_data: nil)
    @csv_paths = csv_paths # array of paths to .csv files on disk
    @json_data = json_data
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
      - JSON must be syntactically valid and self-contained.
      - Use ONLY Chart.js v4 fields. Do NOT add any fields not recognized by Chart.js.
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

  # Returns a Ruby Hash ready to pass to Chart.js on the frontend
  def generate_chart!(prompt:)
    chat = RubyLLM.chat(model: 'gemini-2.5-pro')

    # Build the system message with instructions
    system_msg = build_system_msg

    # Build the single user message with instructions and JSON (inline)
    user_msg = build_user_msg(prompt)

    Rails.logger.debug user_msg.inspect

    # Attach the CSV files if provided; otherwise just send the message
    raw = if @csv_paths.any?
            chat.ask(system_msg) # prime the system instruction
            chat.ask(user_msg, with: @csv_paths)
          else
            chat.ask([system_msg, user_msg].join("\n\n"))
          end

    Rails.logger.debug raw.inspect
    # Parse & validate the LLM’s JSON
    config = parse_json(raw)
    validate_chartjs!(config)

    # Cleanup the csv files downloaded
    cleanup

    config
  end

  private

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
    cfg
  end
end
