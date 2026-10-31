# AI chat kit — a chat about a record (the KPI report Analysis tab opens these) on the shared chat kit.
# The page and job do not depend on the record's type, so the examples use a fund. The model's
# streaming is stubbed; jobs run inline and their Turbo broadcasts are recorded.
# Worked examples: openspec/changes/ai-chat-kit/design.md#worked-examples
@rack_test
Feature: Record analysis chat on the chat kit

  Background:
    Given "Priya Sharma" is a fund manager at "Golden Angels" with the fund "Golden Angels Fund I"
    And Priya has a chat about "Golden Angels Fund I" that asked "Summarise Q2"

  # H5 — Happy path: the kit page lists the record's chats; a question shows at once and its answer streams into the pending one
  Scenario: Ask and watch the answer stream in
    Given the chat model streams "Revenue grew 12% in Q3. Margins held."
    And live updates are recorded
    When Priya opens that chat
    Then the chat sidebar lists "Summarise Q2"
    When Priya sends "Summarise revenue" in the chat
    Then the chat response adds the question "Summarise revenue" with "Thinking…" under it
    And the live chat answer streamed before it finished
    And the live chat answer shows "Revenue grew 12% in Q3. Margins held."
    And the live chat question box is ready again

  # E5 — Edge case: a record without PDF or CSV documents shows no document picker
  Scenario: No documents, no picker
    When Priya opens that chat
    Then there is no document picker

  # E15 — Edge case: an empty answer is shown as the fallback text
  Scenario: Empty answer
    Given the chat model streams nothing
    And live updates are recorded
    When Priya opens that chat
    And Priya sends "Summarise revenue" in the chat
    Then the live chat answer shows "The assistant was unable to generate a response."

  # E16 — Edge case: the page uses Tabler icons only
  Scenario: One icon set
    When Priya opens that chat
    Then the chat shows no Font Awesome or Bootstrap Icons

  # X4 — Error case: a streaming error alerts the user as before, reads "Not answered" and puts the question back
  Scenario: Streaming fails
    Given the chat model fails with "provider down"
    And live updates are recorded
    And alerts are recorded
    When Priya opens that chat
    And Priya sends "Summarise revenue" in the chat
    Then Priya is alerted "Error while streaming chat response: provider down"
    And the live chat answer reads "Not answered"
    And the live chat question box holds "Summarise revenue"

  # X8 — Error case: a user of another entity cannot open the chat
  Scenario: Another entity's chat
    Given "Arjun Rao" of "Beta Capital" is signed in
    When Arjun opens Priya's chat
    Then the chat's questions are not shown
