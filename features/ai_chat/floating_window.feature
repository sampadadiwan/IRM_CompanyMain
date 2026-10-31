# AI chat kit — the floating agent chat window (support_agents/_chat_panel) for every agent: the
# Portfolio Assistant agent, the LP chat and the rest. The window's inside is the chat kit, served by
# SupportAgentChatsController. Only the model call is stubbed; GenericChatAgent's session choice is real.
# Worked examples: openspec/changes/ai-chat-kit/design.md#worked-examples
@rack_test
Feature: Floating agent chat window on the chat kit

  Background:
    Given "Priya Sharma" is a fund manager at "Golden Angels" with the fund "Golden Angels Fund I"
    And Golden Angels has the "PortfolioAssistantAgent" agent "Portfolio Assistant" with chat on

  # H6 — Happy path: a question in the window comes back as a kit question and answer, without ratings
  Scenario: Ask in the window
    Given the agent answers "Valuations rose 8% this quarter."
    When Priya opens the window on "Golden Angels Fund I"
    And Priya asks in the window "Show recent valuations"
    Then the window shows the question "Show recent valuations" and the answer "Valuations rose 8% this quarter."
    And the window's answer has no rating buttons

  # H7 — Happy path: Conversations lists the record's conversations with question, who and when
  Scenario: Conversations list
    Given Priya has window conversations on "Golden Angels Fund I":
      | question               | last changed |
      | Show recent valuations | today 10:45  |
      | Plot KPIs over time    | 2026-09-28   |
    When Priya opens the window on "Golden Angels Fund I"
    Then the window lists "Show recent valuations" with "Priya Sharma · 10:45"
    And the window lists "Plot KPIs over time" with "Priya Sharma · 28/09/2026"

  # H8 — Happy path: the LP chat is the kit window and lists only the investor's own conversations
  Scenario: LP chat
    Given Golden Angels has the "LpAssistantAgent" agent "LP Assistant" with chat on
    And "Kavya Iyer" is an investor of Golden Angels with her own LP chat "What's my current IRR?"
    And another investor of Golden Angels has an LP chat "Show my SOA"
    When Kavya opens her LP chat
    Then the window lists "What's my current IRR?"
    And the window does not list "Show my SOA"

  # H11 — Happy path: an empty window offers the agent's suggestions, each to fill the box or Ask at once
  Scenario: Suggested questions
    When Priya opens the window on "Golden Angels Fund I"
    Then the window suggests "Show recent valuations" with a fill button and an Ask button

  # H12 — Happy path: the page carries the bubble and window; the window has Maximise and its conversation list
  Scenario: Window controls
    When Priya opens the Portfolio Assistant agent's page
    Then the page has the chat bubble and a lazy window
    When Priya opens the window on "Golden Angels Fund I"
    Then the window has Conversations, New, Maximise and Close

  # E2 — Edge case: quote marks a first question was pasted with are left out of its title
  Scenario: Quoted question
    Given Priya has window conversations on "Golden Angels Fund I":
      | question                  | last changed |
      | "Why is TSTF2 overpaid?"  | today 10:45  |
    When Priya opens the window on "Golden Angels Fund I"
    Then the window lists "Why is TSTF2 overpaid?" without quote marks

  # E4 — Edge case: a blank question is refused and nothing is saved
  Scenario: Blank question
    When Priya opens the window on "Golden Angels Fund I"
    And Priya asks in the window "   "
    Then the window request is refused and no message is saved

  # E9 — Edge case: New starts a new conversation even when the last one is 5 minutes old
  Scenario: New starts a conversation
    Given the agent answers "Fresh start."
    And Priya has window conversations on "Golden Angels Fund I":
      | question               | last changed |
      | Show recent valuations | 5 minutes ago |
    When Priya starts a new conversation in the window on "Golden Angels Fund I"
    And Priya asks in the window "Plot KPIs over time"
    Then Priya has 2 window conversations on "Golden Angels Fund I"

  # E10 — Edge case: a question asked in a reopened older conversation goes into that conversation
  Scenario: Reopened conversation continues
    Given the agent answers "Continuing."
    And Priya has window conversations on "Golden Angels Fund I":
      | question               | last changed  |
      | Show recent valuations | 5 minutes ago |
      | Plot KPIs over time    | 2 hours ago   |
    When Priya reopens "Plot KPIs over time" in the window on "Golden Angels Fund I"
    And Priya asks in the window "And last quarter?"
    Then "And last quarter?" is in the conversation that started "Plot KPIs over time"

  # E11 — Edge case: a caller naming no conversation (WhatsApp) keeps today's rule — the latest, unless idle 30 minutes
  Scenario: No conversation named keeps today's rule
    Given the agent answers "Same conversation."
    And Priya has window conversations on "Golden Angels Fund I":
      | question               | last changed  |
      | Show recent valuations | 5 minutes ago |
    When the agent is asked "Next?" about "Golden Angels Fund I" without naming a conversation
    Then "Next?" is in the conversation that started "Show recent valuations"

  # E18 — Edge case: the window opens on a new conversation once the latest has been idle over 30 minutes; the old one stays in the list
  Scenario: Idle conversation is not continued by default
    Given Priya has window conversations on "Golden Angels Fund I":
      | question               | last changed |
      | Show recent valuations | 2 hours ago  |
    When Priya opens the window on "Golden Angels Fund I"
    Then the window opens on a new conversation
    And the window lists "Show recent valuations"

  # E13 — Edge case: the window on one record lists only that record's conversations
  Scenario: Window scoped to its record
    Given the fund "Golden Angels Fund II" of Golden Angels
    And Priya has window conversations on "Golden Angels Fund I":
      | question               | last changed |
      | Show recent valuations | today 10:45  |
    And Priya has window conversations on "Golden Angels Fund II":
      | question            | last changed |
      | Fund II performance | today 10:50  |
    When Priya opens the window on "Golden Angels Fund I"
    Then the window lists "Show recent valuations"
    And the window does not list "Fund II performance"

  # E16 — Edge case: the window uses Tabler icons only
  Scenario: One icon set
    When Priya opens the window on "Golden Angels Fund I"
    Then the chat shows no Font Awesome or Bootstrap Icons

  # X1 — Error case: the AI service is unreachable; the answer reads "Not answered" and the question goes back
  Scenario: AI service unreachable
    Given the agent cannot reach the AI service
    When Priya opens the window on "Golden Angels Fund I"
    And Priya asks in the window "Show recent valuations"
    Then the window's pending answer reads "Not answered" with "AI service is temporarily unreachable (network/DNS). Please try again shortly."
    And the window's question box holds "Show recent valuations"

  # X2 — Error case: the agent fails; the answer reads "Not answered" with "Chat agent execution failed"
  Scenario: Agent fails
    Given the agent fails
    When Priya opens the window on "Golden Angels Fund I"
    And Priya asks in the window "Show recent valuations"
    Then the window's pending answer reads "Not answered" with "Chat agent execution failed"

  # X7 — Error case: naming another investor's conversation is ignored; the question goes into her own
  Scenario: Another investor's conversation
    Given Golden Angels has the "LpAssistantAgent" agent "LP Assistant" with chat on
    And the agent answers "Your IRR is 14%."
    And "Kavya Iyer" is an investor of Golden Angels with her own LP chat "What's my current IRR?"
    And another investor of Golden Angels has an LP chat "Show my SOA"
    When Kavya asks her LP chat "And last year?" naming the other investor's conversation
    Then the other investor's conversation is unchanged
    And "And last year?" is in Kavya's own LP chat
