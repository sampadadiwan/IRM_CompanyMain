require "json"
require "ruby_llm"

class ReportInsightRunner < Trailblazer::Operation
  include LlmResponseParser

  step :initialize_llm, Output(:failure) => End(:failure)
  step :get_report_data, Output(:failure) => End(:failure)
  step :save_data_as_json
  step :build_prompt
  step :get_llm_response, Output(:failure) => End(:failure)
  step :close_tempfile
  step :process_response, Output(:failure) => End(:failure)
  step :update_report_insight, Output(:failure) => End(:failure)

  #  Make a trailblazer operation
  ALLOWED_CHARTS = %w[bar line pie doughnut scatter radar polarArea].freeze
  MAX_RECORDS = 500
  # Initializes the LLM client using the configured model.
  # Sets up the chat client in the context for later use.
  def initialize_llm(ctx, **)
    # TODO: - set temperature so that the output is more deterministic
    ctx[:chat] = LlmService.ruby_llm_chat(entity: ctx[:report_insight].entity)
  end

  # Fetches the report data based on the report configuration.
  # 1. Validates the report and user existence.
  # 2. Parses the report URL to extract query parameters.
  # 3. Dynamically finds and calls the list service for the report's model.
  # 4. Scopes the data using Pundit policy.
  # 5. Stores the result in the context or adds errors if something fails.
  def get_report_data(ctx, report_insight:, **)
    ctx[:report] = report_insight.report
    report = ctx[:report]
    ctx[:errors] ||= []
    if report.blank?
      ctx[:errors] << "Report Missing"
      return false
    end

    user = report.user
    if user.blank?
      ctx[:errors] << "Report Missing User"
      return false
    end

    _path, query_string = report.url.split("?", 2)
    params = Rack::Utils.parse_nested_query(query_string || "").with_indifferent_access

    list_service_name = "#{report.model}List"

    if Object.const_defined?(list_service_name)
      service_class = list_service_name.constantize
      result = service_class.call(user, params) do |relation|
        Pundit.policy_scope!(user, relation)
      end

      accessor = report.model.underscore.pluralize
      if result.respond_to?(accessor)
        ctx[:report_data] = result.public_send(accessor)
      else
        ctx[:errors] << "Service #{list_service_name} did not return #{accessor}"
        false
      end
    else
      ctx[:errors] << "Service #{list_service_name} not found"
      false
    end
  end

  # Serializes the report data to a JSON file.
  # 1. Enforces a record limit to prevent overloading the LLM.
  # 2. Extracts schema information for the model.
  # 3. Constructs a payload with metadata and the dataset.
  # 4. Writes the payload to a temporary file.
  def save_data_as_json(ctx, report:, report_data:, **)
    model_klass = report.model.constantize

    # enforce a cap
    limited = report_data.limit(MAX_RECORDS + 1)
    count = limited.count
    if count > MAX_RECORDS
      error_message = "Too many records (#{count}). Refine filters."
      ctx[:errors] << error_message
      return false
    end

    schema_info = model_klass.columns_hash.transform_values do |col|
      { type: col.type.to_s, sql_type: col.sql_type, nullable: col.null }
    end

    payload = {
      meta: {
        report_name: report.name,
        model: report.model,
        record_count: count,
        schema_info: schema_info
      },
      dataset: limited.as_json
    }

    tmpfile = Tempfile.new(["report_insight_data", ".json"])
    tmpfile.write(JSON.pretty_generate(payload))
    tmpfile.rewind

    ctx[:tmpfile] = tmpfile
    ctx[:record_count] = count
  end

  # Construct the detailed prompt using the gathered information.
  # Includes instructions for the LLM on how to format the response,
  # available chart types, and color palettes.
  def build_prompt(ctx, report:, record_count:, **) # rubocop:disable Metrics/MethodLength
    ctx[:prompt] = <<~PROMPT
      You are generating a client-ready report insight for a busy professional.
      The dataset is provided as an attached JSON file. Use it for analysis.

      Output format:
      Return ONLY valid JSON. No backticks. No markdown fences. No text outside JSON.

      {
        "md_body": "string (a complete Markdown document for the platform view)",
        "charts": [
          { "id": "string", "library": "chartjs", "config": { "type": "...", "data": {...}, "options": {...} } }
        ],
        "summary_md": "string (EMAIL-FIRST Markdown teaser, designed to compel a click)",
        "notes": "string (optional)"
      }

      Summary requirements (summary_md):
      - Write for an email card. Keep it SHORT and skimmable (75-95 words).
      - MUST include:
        1) A one-line headline that states the main insight (bold it).
        2) 3 to 5 bullet points with metrics.
          - Every bullet MUST include BOTH a count and percentage if total exists:
            Format: "<Metric label>: <count>/<total> (<percent>%)"
          - If total is unknown: "<count> records" (no %)
          - NEVER write "X% out of Y"
        3) "Why it matters:" followed by 1 crisp sentence.
        4) "Next step:" followed by 1 action sentence.
        5) End with ONE curiosity hook question.

      Metrics style guide:
      - Use "x/y (z%)"
      - Do NOT include a "Summary" heading.
      - Avoid long paragraphs.
      - Do NOT mention JSON, dataset, attached file, or implementation details.
      - Assume the reader can click to view details; tease, don't dump.

      md_body requirements (platform view):
      - md_body must be a complete Markdown document with headings, bullets, and (if useful) tables.
      - Start md_body with a brief executive summary (can be longer than summary_md).
      - Include “Key Drivers”, “Notable Outliers”, and “Recommendations” sections if relevant.
      - Use the placeholder token to place charts: {{chart:<id>}}
        * Ensure <id> contains no underscores.
      - Prefer 1-3 charts max. Allowed chart types: #{ALLOWED_CHARTS.join(', ')}.
      - If charts are not meaningful, return "charts": [] and explain why in md_body.

      Chart rules:
      - charts[*].config must be JSON compatible with Chart.js.
      - No executable JavaScript, functions, callbacks, or HTML.
      - Use LIGHT pastel palettes:
        * Pastel (PREFERRED): ["#93C5FD", "#A5B4FC", "#F9A8D4", "#FCD34D", "#6EE7B7", "#FDBA74", "#C4B5FD", "#FCA5A5"]
        * Warm Pastels: ["#FECACA", "#FED7AA", "#FDE68A", "#FEF08A", "#D9F99D", "#BBF7D0"]
        * Cool Pastels: ["#BFDBFE", "#C7D2FE", "#DDD6FE", "#F5D0FE", "#FBCFE8", "#FECDD3"]
        * Soft Blue-Green: ["#7DD3FC", "#67E8F9", "#5EEAD4", "#6EE7B7", "#86EFAC", "#A3E635"]

      User prompt:
      #{report.ai_prompt}

      Record count: #{record_count}
    PROMPT
  end

  # Sends the prompt and the data file to the LLM.
  # Logs the prompt and stores the raw response.
  def get_llm_response(ctx, report:, chat:, **)
    # Implementation for running the Report Insight
    Rails.logger.debug { "Running Report Insight for Report ID: #{report.id}" }

    Rails.logger.debug { "Report Insight Prompt: #{ctx[:prompt]}" }

    ctx[:triggered_at] = Time.zone.now
    raw_response = chat.ask(ctx[:prompt], with: ctx[:tmpfile].path)

    ctx[:raw_response] = raw_response
  end

  # Cleans up the temporary file used for data transfer.
  def close_tempfile(ctx, **)
    return true unless ctx[:tmpfile].is_a?(Tempfile)

    ctx[:tmpfile].close
    ctx[:tmpfile].unlink
  end

  # Processes the raw response from the LLM.
  # 1. Parses the JSON response.
  # 2. Extracts markdown body, charts, and notes.
  # 3. Validates chart configurations if present.
  def process_response(ctx, raw_response:, **)
    parsed = parse_llm_json(raw_response)
    Rails.logger.debug { "Report Insight Raw Response:\n #{raw_response}" }
    return false unless parsed.is_a?(Hash)

    ctx[:md_body] = parsed.fetch("md_body")
    ctx[:charts]  = parsed.fetch("charts")
    ctx[:summary] = parsed.fetch("summary_md", nil)
    ctx[:notes] = parsed.fetch("notes", nil)
    ctx[:charts].each do |c|
      validate_chartjs!(c["config"]) if c["library"] == "chartjs"
    rescue StandardError => e
      ctx[:errors] << "Invalid chart config for chart id #{c['id']}: #{e.message}"
      return false
    end

    true
  end

  # Updates the ReportInsight record with the results.
  # Sets status to success or failed based on the outcome.
  def update_report_insight(ctx, report_insight:, md_body:, summary:, charts:, triggered_at:, **)
    report_insight.update!(
      ai_response: md_body,
      charts_spec: charts,
      summary: summary,
      status: "success",
      prompt_used: ctx[:prompt],
      record_count: ctx[:report_data]&.count,
      notes: ctx[:notes],
      triggered_at: triggered_at,
      status_message: nil
    )
  rescue StandardError => e
    report_insight.update!(
      status: "failed",
      status_message: e.message,
      prompt_used: ctx[:prompt],
      triggered_at: triggered_at
    )
    Rails.logger.error { "Report Insight failed: #{e.message}" }
    ctx[:errors] << e.message
    false
  end

  # Validates the Chart.js configuration structure.
  # Ensures required fields (type, data, labels, datasets) are present and correct.
  def validate_chartjs!(cfg)
    raise "Chart config is empty" unless cfg.is_a?(Hash)

    type = cfg["type"]
    data = cfg["data"]
    raise "Missing type" unless type.is_a?(String)
    raise "Unsupported type: #{type}" unless ALLOWED_CHARTS.include?(type)

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
