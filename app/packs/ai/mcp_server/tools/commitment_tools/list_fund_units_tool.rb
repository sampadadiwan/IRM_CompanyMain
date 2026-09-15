# frozen_string_literal: true

# MCP tool to list the fund units issued against one capital commitment.
# Surface generated from the `fund_unit` ontology.
#
# Queries Pundit-scoped FundUnit directly. The commitment scoping is a Ransack condition on
# capital_commitment_id, which only became effective once that attribute was added to
# FundUnit.ransackable_attributes -- before that Ransack dropped it and the tool returned
# every unit in the user's scope.
class ListFundUnitsTool < ApplicationMcpTool
  ontology "list_fund_units"

  def self.call(server_context:, commitment_id:, query: {}, sort: nil,
                limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil)
    if (message = validation_error(query: query, sort: sort, aggregate: aggregate,
                                   aggregate_field: aggregate_field, group_by_field: group_by_field,
                                   commitment_id: commitment_id))
      return error(message)
    end

    user = server_context[:user]
    commitment = Pundit.policy_scope(user, CapitalCommitment).find_by(id: commitment_id)
    return error("Commitment #{commitment_id} not found, or you do not have access to it.") unless commitment

    q = ransack_query(query, aggregate_field: aggregate_field, group_by_field: group_by_field)
    q[:s] ||= sort if sort.present?
    q[:capital_commitment_id_eq] = commitment.id

    results = Pundit.policy_scope(user, FundUnit).ransack(q).result

    if aggregate.present?
      return json FundAssistantDataManager.new(user: user)
                                          .send(:perform_aggregation, results, aggregate,
                                                field: q[:aggregate_field], group_by: q[:group_by])
    end

    results = results.limit(limit.presence || FundAssistantDataManager::DEFAULT_QUERY_LIMIT)

    json(results.map do |unit|
      {
        id: unit.id,
        unit_type: unit.unit_type,
        quantity: unit.quantity,
        price: unit.price.format,
        premium: unit.premium.format,
        amount: unit.amount.format,
        issue_date: unit.issue_date,
        owner_type: unit.owner_type,
        folio_id: unit.capital_commitment.folio_id,
        view_link: "/fund_units/#{unit.id}"
      }
    end)
  end
end
