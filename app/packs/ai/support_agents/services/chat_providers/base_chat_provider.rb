# frozen_string_literal: true

# Abstract base class for chat providers. Each SupportAgent type maps to a
# domain-specific provider that supplies the system prompt, context data,
# and LangChain tools for the chat session.
#
# Subclasses must implement `system_prompt`. Optionally override
# `build_context` and `tools`.
#
# @see DefaultChatProvider
# @see CashFlowChatProvider

class BaseChatProvider
  attr_reader :support_agent, :target, :analyst

  def initialize(support_agent:, target:, analyst:)
    @support_agent = support_agent
    @target = target
    @analyst = analyst
  end

  def system_prompt
    raise NotImplementedError
  end

  def build_context
    ""
  end

  def tools
    []
  end

  # Factory: resolves the right provider based on agent_type.
  # Each agent type maps to a domain-specific provider that supplies
  # the system prompt, context data, and tools for the chat.
  def self.resolve(support_agent:, target:, analyst:)
    provider_class = case support_agent.agent_type
                     when "CashFlowAssistantAgent" then defined?(CashFlowChatProvider) ? CashFlowChatProvider : DefaultChatProvider
                     when "CallNoticeAgent" then defined?(CallNoticeChatProvider) ? CallNoticeChatProvider : DefaultChatProvider
                     when "PortfolioReportAgent" then defined?(PortfolioReportChatProvider) ? PortfolioReportChatProvider : DefaultChatProvider
                     when "PortfolioCompanyAgent" then defined?(PortfolioCompanyChatProvider) ? PortfolioCompanyChatProvider : DefaultChatProvider
                     else DefaultChatProvider
                     end

    provider_class.new(support_agent: support_agent, target: target, analyst: analyst)
  end

  private

  def strict_scope_prompt
    <<~PROMPT
      STRICT SCOPE:
      - You MUST ONLY answer questions related to the data provided to you.
      - If the user asks about anything unrelated to your domain, politely decline and redirect.
      - Example: "I can only help with questions related to the data I have. Could you ask me something about that instead?"
      - NEVER answer general knowledge questions, trivia, or anything outside the provided data.
    PROMPT
  end

  def chart_rendering_prompt
    <<~PROMPT
      CHART RENDERING:
      When the user asks for a chart, graph, or visualization, output this exact HTML:
      <div data-controller="chart-renderer" data-chart-renderer-spec-value='CHART_JSON_HERE' style="width:100%;height:320px;position:relative">
        <canvas data-chart-renderer-target="canvas" style="display:block;width:100%;height:100%"></canvas>
      </div>

      Where CHART_JSON_HERE is a valid Chart.js v4 config. Always include responsive options:
      {"type":"bar","data":{"labels":["A","B"],"datasets":[{"label":"Value","data":[100,200],"borderWidth":1}]},"options":{"responsive":true,"maintainAspectRatio":false,"plugins":{"legend":{"display":true}}}}

      Supported types: bar, line, pie, doughnut, scatter, radar, polarArea.
      Use REAL data from the context provided. Include a brief text summary before/after the chart.
      The JSON must use double quotes only (no single quotes inside the JSON value).
      Always include "responsive":true and "maintainAspectRatio":false in the options.
    PROMPT
  end

  def table_rendering_prompt
    <<~PROMPT
      TABLE AND COMPARISON RENDERING:
      When you receive scenario analysis results or data comparisons from a tool,
      always present the comparison as a styled HTML table — never as plain text or markdown tables.

      Use this style for comparison tables:
      - Table element: style="border-collapse:collapse;width:100%;margin:1em 0"
      - Header row: style="background:#1e3a5f;color:white;padding:8px 12px;text-align:left"
      - Data cells: style="padding:8px 12px;border-bottom:1px solid #e5e7eb"
      - Improved values (cash up, net position better, surplus, runway longer): style="color:#16a34a;font-weight:bold"
      - Worsened values (shortfall, net position worse, runway shorter): style="color:#dc2626;font-weight:bold"
      - Status SURPLUS: style="background:#dcfce7;color:#15803d;padding:2px 8px;border-radius:4px"
      - Status SHORTFALL: style="background:#fee2e2;color:#dc2626;padding:2px 8px;border-radius:4px"
      - Status WATCH: style="background:#fef9c3;color:#854d0e;padding:2px 8px;border-radius:4px"

      GENERAL HTML FORMATTING — apply to ALL responses:
      - Never use markdown bullet dashes (-) or ### headings. Always use HTML.
      - For any list of items, use: <ul style="margin:0.5em 0;padding-left:1.5em"><li style="margin:0.25em 0">...</li></ul>
      - For section headings, use: <strong style="display:block;margin:0.75em 0 0.25em">Heading</strong>
      - For introductory or summary text, use: <p style="margin:0.5em 0">...</p>
    PROMPT
  end
end
