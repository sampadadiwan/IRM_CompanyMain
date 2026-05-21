# frozen_string_literal: true

# MCP tool to get detailed information about a specific capital commitment.
# Queries Pundit-scoped CapitalCommitment directly (not via CapitalCommitmentAssistantDataManager,
# which requires a pre-bound commitment instance).
class GetCommitmentDetailsTool < ApplicationMcpTool
  description "Get details of a specific capital commitment including investor, fund, " \
              "committed/collected/distributed amounts, onboarding status, and fund close. " \
              "Use list_capital_commitments first to find commitment IDs by investor name or folio ID."

  input_schema(
    properties: {
      commitment_id: { type: "integer", description: "The ID of the capital commitment. Use list_capital_commitments with { investor_name_cont: 'name' } to find IDs." }
    },
    required: ["commitment_id"]
  )

  def self.call(server_context:, commitment_id:)
    commitment = Pundit.policy_scope(server_context[:user], CapitalCommitment)
                       .includes(:fund, :investor)
                       .find_by(id: commitment_id)

    unless commitment
      return MCP::Tool::Response.new([{
                                       type: "text", text: "Commitment not found or access denied"
                                     }])
    end

    data = {
      id: commitment.id,
      folio_id: commitment.folio_id,
      investor: commitment.investor_name,
      fund: commitment.fund&.name,
      unit_type: commitment.unit_type,
      commitment_date: commitment.commitment_date,
      committed_amount: commitment.committed_amount.format,
      call_amount: commitment.call_amount.format,
      collected_amount: commitment.collected_amount.format,
      distribution_amount: commitment.distribution_amount.format,
      onboarding_completed: commitment.onboarding_completed,
      fund_close: commitment.fund_close,
      currency: commitment.folio_currency,
      view_link: "/capital_commitments/#{commitment.id}"
    }

    MCP::Tool::Response.new([{ type: "text", text: data.to_json }])
  end
end
