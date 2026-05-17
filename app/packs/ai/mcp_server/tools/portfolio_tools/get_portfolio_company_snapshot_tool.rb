# frozen_string_literal: true

# MCP tool to get a high-level snapshot of a portfolio company including
# total invested, current FMV, latest valuation, and return multiples.
class GetPortfolioCompanySnapshotTool < ApplicationMcpTool
  description "Get a high-level snapshot of a portfolio company. Returns total amount invested, " \
              "current fair market value, latest valuation (date, per-share value, currency), " \
              "and return multiples (TVPI, RVPI). Use this for a quick executive summary."

  input_schema(
    properties: {
      portfolio_company_id: { type: "integer", description: "The ID of the portfolio company" }
    },
    required: ["portfolio_company_id"]
  )

  def self.call(server_context:, portfolio_company_id:)
    data_manager = PortfolioAssistantDataManager.new(user: server_context[:user])
    data = data_manager.get_portfolio_company_snapshot(portfolio_company_id: portfolio_company_id)

    MCP::Tool::Response.new([{ type: "text", text: data.to_json }])
  end
end
