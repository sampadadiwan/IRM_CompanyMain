# app/packs/ai/ai_portfolio_reports/services/portfolio_chart_agent_service.rb
# Separate chart service for Portfolio Reports - does not affect other Caphive features
require "json"
require "ruby_llm"

class PortfolioChartAgentService
  # Minimal whitelist to keep outputs valid for Chart.js
  ALLOWED_TYPES = %w[bar line pie doughnut scatter radar polarArea].freeze

  def initialize(csv_paths: [], json_data: nil)
    @csv_paths = csv_paths # array of paths to .csv files on disk
    @json_data = json_data
  end

  def build_system_msg
  <<~SYS
    You are a Chart.js config generator.
    TASK: Output ONLY a single JSON object representing a valid Chart.js config:
      {
        "type": "<one of: #{ALLOWED_TYPES.join(', ')}>",
        "data": {
          "labels": [<strings or numbers>],
          "datasets": [
            {
              "label": "<name>",
              "data": [<numbers>],
              "backgroundColor": [<array of colors for pie/bar> or <single color for line>],
              "borderColor": "<color>",
              "borderWidth": 2,
              "fill": false
            }
          ]
        },
        "options": { }
      }
    RULES:
    - No markdown, no code fences, no commentary - just JSON.
    - IMPORTANT: Always use LIGHT, PASTEL colors - NOT dark saturated colors
    - For pie/doughnut charts: Use array of light pastel colors like ["#93C5FD", "#A5B4FC", "#F9A8D4", "#FCD34D", "#6EE7B7", "#FDBA74"]
    - For bar charts: Use array of light colors like ["#93C5FD", "#A5B4FC", "#F9A8D4", "#FCD34D", "#6EE7B7", "#FDBA74"]
    - For line charts: Use borderColor like "#60A5FA" and backgroundColor "rgba(96, 165, 250, 0.15)"
    - Use these LIGHT color palettes (prefer Pastel):
      * Pastel (PREFERRED): ["#93C5FD", "#A5B4FC", "#F9A8D4", "#FCD34D", "#6EE7B7", "#FDBA74", "#C4B5FD", "#FCA5A5"]
      * Soft Blue-Green: ["#7DD3FC", "#67E8F9", "#5EEAD4", "#6EE7B7", "#86EFAC", "#A3E635"]
      * Warm Pastels: ["#FECACA", "#FED7AA", "#FDE68A", "#FEF08A", "#D9F99D", "#BBF7D0"]
      * Cool Pastels: ["#BFDBFE", "#C7D2FE", "#DDD6FE", "#F5D0FE", "#FBCFE8", "#FECDD3"]
    - If CSV files are provided, use them as primary data; if JSON is provided, merge it sensibly.
    - Ensure arrays are equal length where required by Chart.js.
    - Prefer sensible defaults; do not invent extra fields not in Chart.js.
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
    chat = RubyLLM.chat(model: 'gpt-4o-mini')

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
    # Parse & validate the LLM's JSON
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
