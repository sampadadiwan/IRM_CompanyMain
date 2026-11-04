# AI chat kit, phase 7 (the AI phase) — every chat screen's assistant is asked for the Support Console's
# answer layout, and every screen draws it: Summary and Key figures cards, a Questions card with Ask
# buttons, and Follow-ups as buttons above the question box. WhatsApp keeps plain answers.
# Worked examples: openspec/changes/ai-chat-kit/design.md#worked-examples
@rack_test
Feature: Answer layout on every chat screen

  Background:
    Given "Priya Sharma" is a fund manager at "Golden Angels" with the fund "Golden Angels Fund I"

  # H19 — Happy path: the Assistants page draws a layout answer as cards, with Ask on questions and follow-ups above the box
  Scenario: Assistants page
    Given Priya has a Specific Fund Assistant conversation on "Golden Angels Fund I" answered in the layout
    When Priya opens the Specific Fund Assistant for "Golden Angels Fund I"
    Then the answer shows a Summary card and the stat card "Overdue" with "₹75,00,000"
    And the question "Was a refund issued?" in the answer has an Ask button
    And the box offers the follow-up "List the overdue LPs" in "assistant-follow-ups"

  # H20 — Happy path: the record chat draws the same layout
  Scenario: Record chat
    Given Priya has a chat about "Golden Angels Fund I" answered in the layout
    When Priya opens that chat
    Then the answer shows a Summary card and the stat card "Overdue" with "₹75,00,000"
    And the box offers the follow-up "List the overdue LPs" in "chat-follow-ups"

  # H21 — Happy path: the floating window draws the same layout
  Scenario: Floating window
    Given Golden Angels has the "PortfolioAssistantAgent" agent "Portfolio Assistant" with chat on
    And Priya has a window conversation on "Golden Angels Fund I" answered in the layout
    When Priya opens the window on "Golden Angels Fund I"
    Then the answer shows a Summary card and the stat card "Overdue" with "₹75,00,000"
    And the question "Was a refund issued?" in the answer has an Ask button
    And the window's box offers the follow-up "List the overdue LPs"

  # H22 — Happy path: the assistants are asked for the layout after their own prompt
  Scenario: Assistants are asked for the layout
    When a Fund Assistant answers a question
    Then its instructions end with the answer layout

  # E19 — Edge case: the window's agents are asked for the layout on the web, not on WhatsApp
  Scenario: Agents on the web, not on WhatsApp
    Given Golden Angels has the "PortfolioAssistantAgent" agent "Portfolio Assistant" with chat on
    When the agent's instructions are built for the "web" channel
    Then they include the answer layout
    When the agent's instructions are built for the "whatsapp" channel
    Then they do not include the answer layout

  # E20 — Edge case: the record chat is asked for the layout for that request only, without saving it to the chat
  Scenario: Record chat instructions are not saved
    Given Priya has a chat about "Golden Angels Fund I" that asked "Summarise Q2"
    And the chat model streams "## Summary\nSteady."
    And the chat's instructions are recorded
    When Priya sends "Summarise revenue" in the chat
    Then the chat was given the answer layout without saving it
