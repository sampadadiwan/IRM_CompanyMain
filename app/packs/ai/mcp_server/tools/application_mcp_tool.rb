# frozen_string_literal: true

# Base class for all CapHive MCP tools.
#
# A tool binds itself to its ontology entry with `ontology "list_capital_calls"`, which sets
# the MCP tool name, the description and the JSON input schema from
# app/packs/ai/mcp_server/ontology/*.yml. Everything a client can get wrong is then checked
# by `validation_error` against that same file, so a tool body is left with nothing but the call
# into its data manager.
#
# Permission filtering lives here too; user/entity context arrives via server_context.
#
# @see McpOntology
class ApplicationMcpTool < MCP::Tool
  class << self
    # @param _user [User] the authenticated user
    # @return [Boolean] whether this tool is accessible
    def accessible_by?(_user)
      true
    end

    # Binds this tool class to its ontology entry.
    #
    # @param name [String] tool name as declared under an entity's `tools:` in the YAML
    # @return [McpOntology::Tool]
    def ontology(name = nil)
      return @ontology if name.nil?

      @ontology = McpOntology.tool(name)
      tool_name @ontology.name
      description @ontology.description
      input_schema @ontology.input_schema
      @ontology
    end

    # @param data [Object] anything that serialises to JSON
    # @return [MCP::Tool::Response]
    def json(data)
      MCP::Tool::Response.new([{ type: "text", text: data.to_json }])
    end

    # @param message [String] why the call could not be served
    # @return [MCP::Tool::Response]
    def error(message)
      json({ error: message })
    end

    # Checks the client's arguments against the ontology.
    #
    # Ransack drops conditions it does not recognise (ignore_unknown_conditions defaults to
    # true and this app never overrides it), so without this an attribute the model guessed
    # wrong would come back as a successful-looking response containing *unfiltered* rows.
    # Naming the right attribute in an error is both safer and a faster path to the correct
    # follow-up call.
    #
    # @return [String, nil] an error message, or nil when the call is usable
    def validation_error(query: nil, sort: nil, scope: nil, aggregate: nil,
                         aggregate_field: nil, group_by_field: nil, **filters)
      # `query` and `scope` are named here but can also satisfy a require_one_of guard, so
      # they have to reach missing_required_filter as well as the ontology check. A query
      # whose values are all blank is not a filter -- Ransack drops blank conditions, so
      # counting it would serve a completely unfiltered read from a very large table.
      missing_required_filter(aggregate: aggregate, query: effective_query(query), scope: scope, **filters) ||
        ontology.validate_call(query: query, sort: sort, scope: scope, aggregate: aggregate,
                               aggregate_field: aggregate_field, group_by_field: group_by_field)
    end

    # Builds the Ransack hash the data managers expect, folding the aggregate arguments in
    # the way perform_aggregation reads them back out.
    def ransack_query(query, aggregate_field: nil, group_by_field: nil)
      q = (query || {}).with_indifferent_access
      q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
      q[:group_by] ||= group_by_field if group_by_field.present?
      q
    end

    private

    # @return [Hash, nil] the query hash when it carries at least one usable condition
    #
    # Not `compact_blank`: `false.blank?` is true in ActiveSupport, so it would strip a
    # boolean condition like `notification_sent_eq: false` — a perfectly valid filter the
    # ontology advertises — and the call would be refused as unfiltered.
    def effective_query(query)
      (query || {}).reject { |_, value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }.presence
    end

    # Tools over very large tables declare `require_one_of` so an unfiltered call is refused
    # rather than served from a 500-row truncation that reads like a complete answer.
    def missing_required_filter(**args)
      required = ontology.require_one_of
      return nil if required.empty? || required.any? { |name| args[name.to_sym].present? }

      "At least one of #{required.join(', ')} is required — unfiltered calls are rejected " \
        "on #{ontology.name} because the underlying table is very large."
    end
  end
end
