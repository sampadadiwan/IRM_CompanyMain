# frozen_string_literal: true

# MCP tool to get one capital commitment's full position.
# Surface generated from the `capital_commitment` ontology.
#
# Queries the Pundit-scoped CapitalCommitment directly rather than through
# CapitalCommitmentAssistantDataManager, which requires a pre-bound commitment instance.
class GetCommitmentDetailsTool < ApplicationMcpTool
  ontology "get_commitment_details"

  def self.call(server_context:, commitment_id:)
    commitment = Pundit.policy_scope(server_context[:user], CapitalCommitment)
                       .includes(:fund, :investor)
                       .find_by(id: commitment_id)
    return error("Commitment #{commitment_id} not found, or you do not have access to it.") unless commitment

    json(
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
    )
  end
end
