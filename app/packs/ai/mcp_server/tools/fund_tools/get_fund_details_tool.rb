# frozen_string_literal: true

# MCP tool to get detailed information about a specific fund.
# Delegates to {FundAssistantDataManager#get_fund_details}.
# @see FundAssistantDataManager#get_fund_details
class GetFundDetailsTool < ApplicationMcpTool
  description "Get details of a specific fund including name, currency, close dates, " \
              "tracking currency amounts, committed/collected/distributed totals, and master fund info. " \
              "Use list_funds first to find the fund_id, then call this for full details."

  input_schema(
    properties: {
      fund_id: { type: "integer", description: "The ID of the fund. Use list_funds to find fund IDs by name: query: { name_cont: 'fund name' }" }
    },
    required: ["fund_id"]
  )

  def self.call(server_context:, fund_id:)
    data_manager = FundAssistantDataManager.new(user: server_context[:user])
    data = data_manager.get_fund_details(fund_id: fund_id)

    MCP::Tool::Response.new([{ type: "text", text: data.to_json }])
  end
end
