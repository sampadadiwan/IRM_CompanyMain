# frozen_string_literal: true

# MCP tool to list fund units for a specific capital commitment.
# Queries Pundit-scoped FundUnit directly, scoped to the given commitment_id.
class ListFundUnitsTool < ApplicationMcpTool
  description "List fund units for a specific capital commitment. " \
              "Attributes: unit_type, quantity, price, amount, as_of_date. " \
              "Always pass sort and limit for efficiency."

  input_schema(
    properties: {
      commitment_id: { type: "integer", description: "The ID of the capital commitment" },
      query: { type: "object", description: "Ransack filter hash, e.g. { unit_type_eq: 'Class A' }" },
      sort: { type: "string", description: "Sort string, e.g. 'as_of_date desc'" },
      limit: { type: "integer", description: "Limit number of results" },
      aggregate: { type: "string", description: "Aggregation: 'count', 'sum', or 'group_by'" },
      aggregate_field: { type: "string", description: "Field to aggregate on (e.g. 'amount', 'quantity')" },
      group_by_field: { type: "string", description: "Field to group results by (e.g. 'unit_type')" }
    },
    required: ["commitment_id"]
  )

  def self.call(server_context:, commitment_id:, query: {}, sort: nil,
                limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil)
    user = server_context[:user]

    commitment = Pundit.policy_scope(user, CapitalCommitment).find_by(id: commitment_id)
    unless commitment
      return MCP::Tool::Response.new([{
                                       type: "text", text: "Commitment not found or access denied"
                                     }])
    end

    q = (query || {}).with_indifferent_access
    q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
    q[:group_by] ||= group_by_field if group_by_field.present?
    q[:capital_commitment_id_eq] = commitment.id

    results = Pundit.policy_scope(user, FundUnit).ransack(q).result

    if aggregate.present?
      data = FundAssistantDataManager.new(user: user)
                                     .send(:perform_aggregation, results, aggregate,
                                           field: q[:aggregate_field], group_by: q[:group_by])
      return MCP::Tool::Response.new([{ type: "text", text: data.to_json }])
    end

    results = results.limit(limit) if limit.present?

    data = results.map do |u|
      {
        id: u.id,
        unit_type: u.unit_type,
        quantity: u.quantity,
        price: u.price.format,
        amount: u.amount.format,
        as_of_date: u.as_of_date,
        folio_id: u.capital_commitment.folio_id,
        view_link: "/fund_units/#{u.id}"
      }
    end

    MCP::Tool::Response.new([{ type: "text", text: data.to_json }])
  end
end
