# AI chat kit — the Assistants page (Fund, Specific Fund, Portfolio, Portfolio Company and Capital
# Commitment assistants) on the shared chat kit. The assistant itself is stubbed; jobs run inline and
# their Turbo broadcasts are recorded.
# Worked examples: openspec/changes/ai-chat-kit/design.md#worked-examples
@rack_test
Feature: Assistants page on the chat kit

  Background:
    Given "Priya Sharma" is a fund manager at "Golden Angels" with the fund "Golden Angels Fund I"

  # H2 — Happy path: the sidebar lists Priya's conversations with this assistant for this fund, newest first
  Scenario: Sidebar of earlier conversations
    Given Priya has Specific Fund Assistant chats on "Golden Angels Fund I":
      | question                         | last changed |
      | Which LPs are overdue on Call 3? | today 09:15  |
      | NAV for Q2?                      | 2026-09-28   |
    When Priya opens the Specific Fund Assistant for "Golden Angels Fund I"
    Then the assistant sidebar lists "Which LPs are overdue on Call 3?" under "Today" with "Priya Sharma · 09:15"
    And the assistant sidebar lists "NAV for Q2?" under "Older" with "Priya Sharma · 28/09/2026"
    And the assistant header names "Specific Fund Assistant" and links to "Golden Angels Fund I"

  # H3 — Happy path: asking shows the question and a pending answer at once; the job's answer replaces it with a table in a card
  Scenario: Ask and get an answer
    Given the assistant answers:
      """
      Three LPs are overdue on Call 3.

      | Investor | Overdue |
      |---|---|
      | Mehta Family | 40,00,000 |
      """
    And live updates are recorded
    When Priya opens the Specific Fund Assistant for "Golden Angels Fund I"
    And Priya asks the assistant "Which LPs are overdue on Call 3?"
    Then the response adds the question "Which LPs are overdue on Call 3?" with "Thinking…" under it
    And the response leaves the question box to the job
    And the live answer replaces the pending one with a table in a card
    And the live question box is ready again

  # H4 — Happy path: answers carry the hooks Export PowerPoint and the slides read
  Scenario: Answers carry the export hooks
    Given Priya has a Specific Fund Assistant conversation on "Golden Angels Fund I" answered with a table
    When Priya opens the Specific Fund Assistant for "Golden Angels Fund I"
    Then the exported answers include a table inside the answer body

  # E1 — Edge case: a first visit shows one "New conversation" row and the assistant's greeting
  Scenario: First visit
    When Priya opens the Specific Fund Assistant for "Golden Angels Fund I"
    Then the assistant sidebar shows 1 conversation titled "New conversation"
    And the thread greets "Hello, Priya"

  # E3 — Edge case: an older row's date follows the browser's locale
  Scenario: Row dates by locale
    Given Priya has Specific Fund Assistant chats on "Golden Angels Fund I":
      | question    | last changed |
      | NAV for Q2? | 2026-09-28   |
    When Priya opens the Specific Fund Assistant for "Golden Angels Fund I" in locale "en-US"
    Then the assistant sidebar lists "NAV for Q2?" under "Older" with "Priya Sharma · 09/28/2026"

  # E6 — Edge case: an assistant without a record (Fund Assistant) has no record link
  Scenario: Fund Assistant has no record link
    When Priya opens the Fund Assistant
    Then the assistant header names "Fund Assistant" without a record link

  # E7 — Edge case: snake_case names in an answer are not italicised
  Scenario: Snake_case names
    Given Priya has a Specific Fund Assistant conversation on "Golden Angels Fund I" answered "Check fund_id and entity_id."
    When Priya opens the Specific Fund Assistant for "Golden Angels Fund I"
    Then the thread shows "Check fund_id and entity_id." without italics

  # E14 — Edge case: 51 conversations show 50 rows and "50+ conversations"
  Scenario: Long history is capped
    Given Priya has 51 Specific Fund Assistant chats on "Golden Angels Fund I"
    When Priya opens the Specific Fund Assistant for "Golden Angels Fund I"
    Then the assistant sidebar shows 50 conversations and says "50+ conversations"

  # E16 — Edge case: the page uses Tabler icons only
  Scenario: One icon set
    When Priya opens the Specific Fund Assistant for "Golden Angels Fund I"
    Then the chat shows no Font Awesome or Bootstrap Icons

  # E17 — Edge case: a spoken question is asked like a typed one
  Scenario: Hold to speak
    Given the assistant answers "Call 3 is 80% collected."
    And speech is transcribed as "Call 3 status"
    When Priya opens the Specific Fund Assistant for "Golden Angels Fund I"
    And Priya sends a voice question
    Then the response adds the question "Call 3 status" with "Thinking…" under it

  # X42 — Error case: a colleague's conversation cannot be opened by its id
  Scenario: A colleague's conversation
    Given Priya's colleague "Meera Nair" has a Specific Fund Assistant chat on "Golden Angels Fund I" asking "Colleague question"
    When Priya opens that colleague's assistant chat by its id
    Then the thread does not show "Colleague question"

  # X47 — Error case: AI Slides opens for an assistant chat (the shared presentation layout built the tear-sheet editor's URL with no id)
  Scenario: AI Slides page opens
    Given Priya has a Specific Fund Assistant chat on "Golden Angels Fund I" with saved slides "Q3 overdue LPs"
    When Priya opens that chat's AI Slides
    Then the slides show "Q3 overdue LPs" without the slide editor

  # X3 — Error case: a timed-out answer reads "Not answered" with the reason, and the question goes back in the box
  Scenario: Assistant times out
    Given the assistant times out
    And live updates are recorded
    When Priya opens the Specific Fund Assistant for "Golden Angels Fund I"
    And Priya asks the assistant "Which LPs are overdue on Call 3?"
    Then the live answer reads "Not answered" with "The request timed out. Please try again or refine your query."
    And the live question box holds "Which LPs are overdue on Call 3?"
