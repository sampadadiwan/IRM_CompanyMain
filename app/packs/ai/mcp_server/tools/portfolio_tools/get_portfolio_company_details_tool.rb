# frozen_string_literal: true

# MCP tool to get detailed information about a specific portfolio company.
class GetPortfolioCompanyDetailsTool < ApplicationMcpTool
  description "Get details for a specific portfolio company. Returns name, category, email, " \
              "tags, city, amount invested, and last interaction date."

  input_schema(
    properties: {
      portfolio_company_id: { type: "integer", description: "The ID of the portfolio company" }
    },
    required: ["portfolio_company_id"]
  )

  def self.call(server_context:, portfolio_company_id:)
    data_manager = PortfolioAssistantDataManager.new(user: server_context[:user])
    data = data_manager.get_portfolio_company_details(portfolio_company_id: portfolio_company_id)

    MCP::Tool::Response.new([{ type: "text", text: data.to_json }])
  end
end
