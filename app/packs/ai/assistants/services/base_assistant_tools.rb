# BaseAssistantTools
#
# Shared tool definitions for all assistants.
#
class BaseAssistantTools
  # Tool to generate chart visualizations from data.
  class PlotChart < RubyLLM::Tool
    description "Generates an interactive Chart.js chart (HTML) from a dataset and a prompt describing the desired visualization. Use this when the user asks for a graph, plot, or chart."
    parameter :data, type: :string, description: "A JSON string of the data to be plotted."
    parameter :prompt, type: :string, description: "A natural language prompt describing what the chart should represent."

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(data: nil, prompt: nil, **args)
      # Some LLMs might pass parameters via the **args hash instead of direct keywords,
      # or they might use different names. We prioritize the direct keywords.
      data ||= args[:data]
      prompt ||= args[:prompt]

      # Log what we received to help debug if it fails again
      Rails.logger.debug { "PlotChart#execute called with data: #{data.inspect}, prompt: #{prompt.inspect}, args: #{args.inspect}" }

      raise ArgumentError, "PlotChart requires both :data and :prompt (received data: #{data.inspect}, prompt: #{prompt.inspect}, args: #{args.inspect})" if data.nil? || prompt.nil?

      generate_chart_html(data, prompt)
    end

    private

    # Returns an HTML snippet that renders the chart client-side using Stimulus + Chart.js.
    # This avoids server-side rendering/screenshot dependencies (e.g., Playwright).
    def generate_chart_html(json_data_string, prompt)
      json_data = JSON.parse(json_data_string)
      # Pass entity so ChartAgentService uses entity-specific API keys rather than global credentials.
      # @assistant.entity works because PortfolioAssistant delegates :entity to :@user.
      agent = ChartAgentService.new(json_data: json_data, entity: @assistant.entity)
      chart_config = agent.generate_chart!(prompt: prompt)
      normalize_chart_config!(chart_config)

      spec_json = chart_config.to_json
      escaped_spec = ERB::Util.html_escape(spec_json)
      escaped_title = ERB::Util.html_escape(prompt.to_s)

      canvas_id = "chart_#{SecureRandom.hex(8)}"

      <<~HTML
        <div class="my-3">
          <div class="fw-semibold mb-2">#{escaped_title}</div>
          <div class="chart-wrap">
            <div data-controller="chart-renderer" data-chart-renderer-spec-value="#{escaped_spec}" style="height: 100%;">
              <canvas id="#{canvas_id}" data-chart-renderer-target="canvas"></canvas>
            </div>
          </div>
        </div>
      HTML
    end

    # ensures the legend is meaningful and points/series are identifiable.
    # Also nudges line/scatter charts to actually render points.
    def normalize_chart_config!(cfg)
      return unless cfg.is_a?(Hash)

      cfg["options"] ||= {}
      cfg["options"]["responsive"] = true
      cfg["options"]["maintainAspectRatio"] = false
      cfg["options"]["resizeDelay"] = 150
      cfg["options"]["plugins"] ||= {}
      cfg["options"]["plugins"]["legend"] ||= {}

      # Always show legend unless explicitly set otherwise (we keep explicit false).
      cfg["options"]["plugins"]["legend"]["display"] = true if cfg["options"]["plugins"]["legend"]["display"].nil?

      datasets = cfg.dig("data", "datasets")
      return unless datasets.is_a?(Array) && datasets.any?

      datasets.each_with_index do |ds, idx|
        next unless ds.is_a?(Hash)

        label = ds["label"].to_s.strip
        next unless label.empty?

        ds["label"] = datasets.length == 1 ? "Value" : "Series #{idx + 1}"
      end

      # Ensure line/scatter charts actually show points (helps "data points inline").
      if %w[line scatter].include?(cfg["type"].to_s)
        datasets.each do |ds|
          next unless ds.is_a?(Hash)

          ds["pointRadius"] = 3 if ds["pointRadius"].nil?
          ds["pointHoverRadius"] = 4 if ds["pointHoverRadius"].nil?
        end
      end
    end
  end

  # Tool to generate chart visualizations directly from a data query.
  # This avoids sending large JSON datasets back and forth between the LLM and the server.
  class PlotChartFromQuery < PlotChart
    description "Generates an interactive Chart.js chart by fetching data directly from the database using a query. " \
                "Use this for large datasets instead of fetching data first. " \
                "Supported resources: 'funds', 'capital_calls', 'capital_commitments', 'capital_remittances', 'capital_distributions', 'portfolio_investments', 'fund_ratios'."
    parameter :resource, type: :string, description: "The resource name to query (e.g., 'capital_remittances')."
    parameter :query, type: :object, description: "Ransack query hash.", required: false
    parameter :scope, type: :string, description: "Predefined scope name.", required: false
    parameter :sort, type: :string, description: "Optional sort string.", required: false
    parameter :limit, type: :integer, description: "Optional limit.", required: false
    parameter :prompt, type: :string, description: "A natural language prompt describing what the chart should represent."

    def execute(resource: nil, query: {}, scope: nil, sort: nil, limit: nil, prompt: nil, **args)
      resource ||= args[:resource]
      query ||= args[:query]
      scope ||= args[:scope]
      sort ||= args[:sort]
      limit ||= args[:limit]
      prompt ||= args[:prompt]

      Rails.logger.debug { "PlotChartFromQuery#execute called for #{resource} with prompt: #{prompt.inspect}" }

      raise ArgumentError, "PlotChartFromQuery requires :resource and :prompt" if resource.nil? || prompt.nil?

      # Map resource name to data manager method
      method_name = "list_#{resource}"
      data_manager = @assistant.respond_to?(:data_manager) ? @assistant.data_manager : @assistant

      return "Error: Unsupported resource '#{resource}' for chart plotting." unless data_manager.respond_to?(method_name)

      # Fetch data directly via data manager
      data_results = data_manager.public_send(method_name, query: query, scope: scope, sort: sort, limit: limit)

      # list_* methods can now return { error: "..." } (e.g. an unrecognized/unsupported
      # `scope`) instead of raising -- that Hash is never `blank?`, so without this check it
      # would fall through into generate_chart_html as if it were real chart data, silently
      # rendering/summarizing a chart from an error payload instead of surfacing the error.
      return "Error: #{data_results[:error]}" if data_results.is_a?(Hash) && data_results[:error].present?

      return "No data found for the given query to plot a chart." if data_results.blank?

      # Generate chart HTML
      html = generate_chart_html(data_results.to_json, prompt)

      # Provide a summary so the LLM knows what was plotted without seeing the raw data
      summary = "Successfully plotted a chart for #{resource}. "
      summary += "Data points: #{data_results.size}. "
      summary += "Summary of data: #{data_results.take(3).to_json}..." if data_results.is_a?(Array)

      "#{summary}\n\n#{html}"
    end
  end
end
