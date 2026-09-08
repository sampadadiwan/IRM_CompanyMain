# frozen_string_literal: true

#
# Covers the ontology-driven MCP tool surface. McpOntology generates every tool's name,
# description and input schema from app/packs/ai/mcp_server/ontology/*.yml and validates the
# client's arguments against the same files.
#
# The drift guard below is the important part: it executes every filter, sort, aggregate and
# group_by the ontology advertises against the real database. Ransack drops conditions it
# does not recognise (ignore_unknown_conditions defaults to true), so an attribute that has
# drifted from its model does not raise -- it silently returns unfiltered rows. Comparing the
# generated SQL before and after the condition is the only way to catch that.

# Sample value for each field type, chosen so the condition is valid SQL for that column.
SAMPLE_VALUES = {
  "string" => "sample", "text" => "sample", "enum" => "sample",
  "date" => "2024-01-01", "datetime" => "2024-01-01 00:00:00",
  "money" => 1, "percent" => 1, "decimal" => 1, "integer" => 1, "reference" => 1,
  "boolean" => true
}.freeze

# Predicates that take no operand -- the value is the assertion itself.
VALUELESS_PREDICATES = %w[null not_null true false present blank].freeze

def ransack_condition_value(spec, predicate)
  return true if VALUELESS_PREDICATES.include?(predicate)

  base = spec["values"]&.first || SAMPLE_VALUES.fetch(spec.fetch("type"))
  %w[in not_in].include?(predicate) ? [base] : base
end

# @return [String, nil] why this condition does not work, or nil when it does
def broken_condition(model, field, spec, predicate)
  key = "#{field}_#{predicate}"
  baseline = model.ransack({}).result.to_sql
  relation = model.ransack(key => ransack_condition_value(spec, predicate)).result
  sql = relation.to_sql
  return "#{model}: #{key} was SILENTLY IGNORED by Ransack (SQL unchanged)" if sql == baseline

  relation.limit(0).load
  nil
rescue StandardError => e
  "#{model}: #{key} raised #{e.class}: #{e.message.lines.first.to_s.strip[0, 120]}"
end

# `the user has the company_admin role` and `there is a capital call for the entity` are
# already defined in fund_assistant_authorization_steps.rb and reused here.

# Tool classes are autoloaded, so they cannot be discovered by scanning ObjectSpace --
# the ontology name maps onto the class name directly (list_capital_calls -> ListCapitalCallsTool).
def mcp_tool_class(tool_name)
  "#{tool_name.camelize}Tool".constantize
end

When("I call the {word} MCP tool with query {string}") do |tool_name, query_json|
  response = mcp_tool_class(tool_name).call(server_context: { user: @user, entity: @entity },
                                            query: JSON.parse(query_json))
  @mcp_payload = JSON.parse(response.content.first[:text])
end

When("I call the {word} MCP tool with sort {string}") do |tool_name, sort|
  response = mcp_tool_class(tool_name).call(server_context: { user: @user, entity: @entity }, sort: sort)
  @mcp_payload = JSON.parse(response.content.first[:text])
end

Then("the MCP response should be an error mentioning {string}") do |fragment|
  expect(@mcp_payload).to be_a(Hash)
  expect(@mcp_payload["error"]).to be_present
  expect(@mcp_payload["error"]).to include(fragment)
end

Then("the MCP response should not be an error") do
  expect(@mcp_payload).not_to be_a(Hash)
end

Then("the MCP response should not include the capital call") do
  expect(@mcp_payload.to_json).not_to include(@capital_call.name)
end

Then("the MCP response should include the capital call") do
  expect(@mcp_payload.map { |row| row["id"] }).to include(@capital_call.id)
end

Then("the {word} tool description should not offer {string} as a filter") do |tool_name, attribute|
  filters_block = mcp_tool_class(tool_name).description.split("Returned on every row").first
  expect(filters_block).not_to include("- #{attribute} (")
end

Then("every filter the ontology advertises works against its model") do
  failures = McpOntology.entity_names.flat_map do |name|
    entity = McpOntology[name]
    model = entity.model_name.constantize
    entity.fields.reject { |_, spec| spec["virtual"] }.flat_map do |field, spec|
      entity.predicates_for(field).filter_map { |pred| broken_condition(model, field, spec, pred) }
    end
  end
  expect(failures).to be_empty, "Ontology advertises filters that do not work:\n#{failures.join("\n")}"
end

Then("every sort option the ontology advertises is honoured by Ransack") do
  failures = McpOntology.entity_names.flat_map do |name|
    entity = McpOntology[name]
    model = entity.model_name.constantize
    entity.sort_options.reject { |o| entity.fields.dig(o.split.first, "virtual") }.filter_map do |option|
      sql = model.ransack(s: option).result.to_sql
      "#{model}: sort #{option.inspect} produced no ORDER BY (Ransack ignored it)" unless sql.include?("ORDER BY")
    end
  end
  expect(failures).to be_empty, "Ontology advertises sort keys Ransack ignores:\n#{failures.join("\n")}"
end

Then("every aggregate and group_by field the ontology advertises resolves to a column") do
  failures = McpOntology.entity_names.flat_map do |name|
    entity = McpOntology[name]
    model = entity.model_name.constantize
    columns = model.column_names
    aggregate_failures = entity.aggregatable_fields.filter_map do |field|
      next if columns.include?("#{field}_cents") || columns.include?(field)

      "#{model}: aggregate_field #{field.inspect} is neither #{field}_cents nor a column — " \
        "perform_aggregation would build invalid SQL"
    end
    group_failures = entity.groupable_fields.filter_map do |field|
      next if columns.include?(field)

      "#{model}: group_by_field #{field.inspect} is not a column — perform_aggregation groups by the raw name"
    end
    aggregate_failures + group_failures
  end
  expect(failures).to be_empty, "Ontology advertises aggregates that do not resolve:\n#{failures.join("\n")}"
end

Then("every tool name referenced in a description exists") do
  known = McpOntology.tool_names
  failures = McpOntology.tool_names.flat_map do |tool_name|
    McpOntology.tool(tool_name).description.scan(/\b((?:list|get)_[a-z_]+)\b/).flatten.uniq.filter_map do |referenced|
      "#{tool_name} points at #{referenced}, which is not a tool" unless known.include?(referenced)
    end
  end
  expect(failures).to be_empty, "Descriptions cross-reference tools that do not exist:\n#{failures.join("\n")}"
end

Then("every scope the ontology describes is declared on its query object") do
  failures = McpOntology.entity_names.flat_map do |name|
    entity = McpOntology[name]
    declared = entity.scope_names
    entity.scope_descriptions.keys.filter_map do |described|
      "#{name}: describes scope #{described.inspect}, which its query object does not declare" unless declared.include?(described)
    end
  end
  expect(failures).to be_empty, "Ontology describes scopes that do not exist:\n#{failures.join("\n")}"
end
