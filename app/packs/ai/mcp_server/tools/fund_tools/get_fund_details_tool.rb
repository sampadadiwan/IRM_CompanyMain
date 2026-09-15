# frozen_string_literal: true

# MCP tool to get one fund's full details. Surface generated from the `fund` ontology.
# Delegates to {FundAssistantDataManager#get_fund_details}.
class GetFundDetailsTool < ApplicationMcpTool
  ontology "get_fund_details"

  def self.call(server_context:, fund_id:)
    json FundAssistantDataManager.new(user: server_context[:user]).get_fund_details(fund_id: fund_id)
  end
end
