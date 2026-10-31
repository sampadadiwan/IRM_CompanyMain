# AI chat kit — how an answer is rendered, by mode (AiChatHelper#ai_answer_html).
# :strict is the Support Console's cleaner (X24); :rich is the chat panel's (charts kept) for the
# Assistants page, the KPI chat and the floating agent window.
# Worked examples: openspec/changes/ai-chat-kit/design.md#worked-examples
Feature: AI chat answer rendering

  # E8 — Edge case: a chart in an answer is kept in rich mode and stripped in strict mode
  Scenario: Chart kept in rich mode, stripped in strict mode
    Given an answer:
      """
      Revenue by quarter:

      <canvas data-controller="chart-renderer" data-chart-renderer-spec-value="{}"></canvas>
      """
    When it is rendered in rich mode
    Then the rendered answer has a chart canvas
    When it is rendered in strict mode
    Then the rendered answer has no chart canvas
    And the rendered answer says "Revenue by quarter:"

  # X6 — Error case: scripts and inline event handlers in an answer are removed in rich mode
  Scenario: Scripts stripped in rich mode
    Given an answer:
      """
      Total is 5.

      <script>alert(1)</script><img src="x" onerror="alert(1)">
      """
    When it is rendered in rich mode
    Then the rendered answer has no script and no inline event handler
    And the rendered answer says "Total is 5."

  # E8 / E7 — Edge case: both modes give tables the kit's Bootstrap card, and snake_case names stay plain
  Scenario: Tables and snake_case names in both modes
    Given an answer:
      """
      Check fund_id and entity_id.

      | Investor | Overdue |
      |---|---|
      | Mehta Family | 40,00,000 |
      """
    When it is rendered in rich mode
    Then the rendered answer has a table in a card
    And the rendered answer has no italics
    When it is rendered in strict mode
    Then the rendered answer has a table in a card
    And the rendered answer has no italics
