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

  # X39 — Error case: a link the strict cleaner turns into text keeps its text as text, never as markup
  Scenario: Link text is never markup
    Given an answer:
      """
      See [&lt;img src=x onerror=alert(1)&gt;](/funds/1) here
      """
    When it is rendered in strict mode
    Then the rendered answer has no script and no inline event handler
    And the rendered answer says "<img src=x onerror=alert(1)>"

  # X40 — Error case: a rich answer cannot take a page element's id or attach another controller
  Scenario: Rich answers lose their own ids and controllers
    Given an answer:
      """
      <div id="assistant-composer" data-controller="ai-chat-window" data-action="click->x#y">Hijack</div>
      """
    When it is rendered in rich mode
    Then the rendered answer has no element ids and no controller but the chart renderer

  # X45 — Happy path: a Support Console answer links a record id to the record's page, opening in a new tab
  Scenario: Record id links to its page
    Given an answer:
      """
      Remittance [13573](/capital_remittances/13573) is still pending on call [1093](/capital_calls/1093).
      """
    When it is rendered in strict mode
    Then the rendered answer links "13573" to "/capital_remittances/13573" in a new tab
    And the rendered answer links "1093" to "/capital_calls/1093" in a new tab

  # X46 — Error case: a same-site link that is not a record page stays plain text
  Scenario: Other site paths stay text
    Given an answer:
      """
      [Sign out](/users/sign_out), [edit it](/funds/1/edit) and [fund](/funds/abc).
      """
    When it is rendered in strict mode
    Then the rendered answer has no links
    And the rendered answer says "Sign out, edit it and fund."

  # E50 — Edge case: the Support Console's prompt asks for record links and lists the pages it may link
  Scenario: The Console asks for record links
    When the Support Console brief is built for a client
    Then it asks for record ids to be linked like "[13573](/capital_remittances/13573)"
    And it lists "/capital_remittances/<id>" among the record pages
