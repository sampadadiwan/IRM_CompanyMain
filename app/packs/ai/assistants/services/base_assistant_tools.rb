# BaseAssistantTools
#
# Shared tool definitions for all assistants.
#
class BaseAssistantTools
  # Tool to generate chart visualizations from data.
  class PlotChart < RubyLLM::Tool
    description "Generates an interactive Chart.js chart (HTML) from a dataset and a prompt describing the desired visualization. Use this when the user asks for a graph, plot, or chart."
    param :data, type: :string, desc: "A JSON string of the data to be plotted."
    param :prompt, type: :string, desc: "A natural language prompt describing what the chart should represent."

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(data:, prompt:)
      html = generate_chart_html(data, prompt)
      RubyLLM::Content.new(html)
    end

    private

    # Returns an HTML snippet that renders the chart client-side using Stimulus + Chart.js.
    # This avoids server-side rendering/screenshot dependencies (e.g., Playwright).
    def generate_chart_html(json_data_string, prompt)
      json_data = JSON.parse(json_data_string)
      agent = ChartAgentService.new(json_data: json_data)
      chart_config = agent.generate_chart!(prompt: prompt)
      normalize_chart_config!(chart_config)

      spec_json = chart_config.to_json
      escaped_spec = ERB::Util.html_escape(spec_json)
      escaped_title = ERB::Util.html_escape(prompt.to_s)

      canvas_id = "chart_#{SecureRandom.hex(8)}"

      <<~HTML
        <div class="my-3">
          <div class="fw-semibold mb-2">#{escaped_title}</div>
          <div class="chart-wrap" style="max-width: 900px;">
            <div data-controller="chart-renderer" data-chart-renderer-spec-value="#{escaped_spec}">
              <canvas id="#{canvas_id}" width="900" height="500" data-chart-renderer-target="canvas"></canvas>
            </div>
          </div>
        </div>
      HTML
    end

    # rubocop:disable Metrics/CyclomaticComplexity
    # Ensures the legend is meaningful and points/series are identifiable.
    # Also nudges line/scatter charts to actually render points.
    def normalize_chart_config!(cfg)
      return unless cfg.is_a?(Hash)

      cfg["options"] ||= {}
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
    # rubocop:enable Metrics/CyclomaticComplexity
  end
end
