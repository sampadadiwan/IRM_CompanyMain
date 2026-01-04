# AI Assistant: Tool Efficiency & Monitoring Guide

This document outlines the strategy for ensuring AI assistants operate efficiently, minimizing data transfer to LLMs, and monitoring their performance via live reports and Cucumber tests.

## 1. Monitoring Tool Efficiency via the Assistant Dashboard

A live **Efficiency Report** has been integrated into the `AssistantsController`. This report allows you to audit the last 100 tool calls for your entity.

### How to Access
- **Endpoint**: `/assistants/efficiency_report` (Partial)
- **Features**:
    - **Total Calls**: Overview of activity.
    - **Missing Limit Count**: Identifies list operations where the LLM failed to specify a `limit`, which is a primary source of data bloat.
    - **Token Tracking**: Displays the input tokens for the message that triggered the tool call.
    - **Visual Alerts**: Highlights rows where `NO LIMIT` was detected for a `list_` tool.

### Database Logic (Controllers)
The logic is implemented in `AssistantsController#efficiency_report`:
- It joins `ToolCall` with `Message` and `Chat` to scope data to the current user's entity.
- It calculates stats like `missing_limit` by inspecting the `arguments` JSON blob in the database.

---

## 2. Efficiency Strategy: Server-Side Filtering

The goal is to ensure the LLM acts as a "precise surgeon" rather than a "data hoarder".

1.  **Ransack Filtering**: Use the `query` parameter to filter by name, date range, or status at the database level.
2.  **Sorting & Limiting**: Ensure tool descriptions explicitly instruct the LLM to use `sort` and `limit`.
3.  **Field Projection**: Tools should return only essential fields (e.g., ID, Name, Amount) instead of serialized objects with dozens of unnecessary attributes.

---

## 3. Comprehensive Testing Strategy (Cucumber)

Cucumber allows us to define "efficiency contracts" in plain English. We can use these tests to ensure the assistant doesn't regress into inefficient patterns.

### A. Feature Definition
Create a new feature file: `features/ai/assistant_efficiency.feature`

```gherkin
Feature: AI Assistant Data Retrieval Efficiency
  As a Platform Administrator
  I want the AI Assistant to fetch only necessary data
  To minimize token costs and improve response speed

  Background:
    Given a fund "Alpha Venture" exists
    And "Alpha Venture" has 100 portfolio investments
    And I am logged in as a fund manager

  Scenario: Requesting the largest investments uses a limit
    When I ask the AI "What are the 3 largest investments in Alpha Venture?"
    Then a tool "list_portfolio_investments" should have been called
    And the tool arguments should include:
      | limit | 3              |
      | sort  | amount_cents desc |

  Scenario: Searching for a specific company uses a filter
    When I ask the AI "Tell me about the Tesla investment in Alpha Venture"
    Then a tool "list_portfolio_investments" should have been called
    And the tool arguments should include a query for "Tesla"
    And the total data returned to the LLM should be less than 5KB
```

### B. Step Definitions
Implement these steps (e.g., in `features/step_definitions/ai_efficiency_steps.rb`):

```ruby
Then(/^a tool "([^"]*)" should have been called$/) do |tool_name|
  @last_tool_call = ToolCall.where(name: tool_name).last
  expect(@last_tool_call).to be_present
end

And(/^the tool arguments should include:$/) do |table|
  args = @last_tool_call.arguments
  table.rows_hash.each do |key, value|
    expect(args[key].to_s).to eq(value.to_s)
  end
end

And(/^the tool arguments should include a query for "([^"]*)"$/) do |search_term|
  query = @last_tool_call.arguments['query']
  expect(query.values.any? { |v| v.to_s.include?(search_term) }).to be true
end

And(/^the total data returned to the LLM should be less than (\d+)KB$/) do |kb_limit|
  # Links the tool result message to the initiating call
  result_message = Message.where(tool_call_id: @last_tool_call.tool_call_id).first
  expect(result_message.content.bytesize).to be < kb_limit.to_i * 1024
end
```

---

## 4. Developer Checklist for Efficiency

When modifying `SpecificFundAssistantTools`:

- [ ] **Expose Ransack**: Ensure the `query` parameter is passed from the Tool to the Data Manager.
- [ ] **Instructional Descriptions**: Does the tool description say "ALWAYS pass limit and sort for efficiency"?
- [ ] **Token Audit**: Use the `run_monthly_report` debug logs to monitor cumulative token usage across multiple queries.
- [ ] **Log Review**: Periodically review the `tool_calls` table in production to ensure the LLM is utilizing filters as expected.
