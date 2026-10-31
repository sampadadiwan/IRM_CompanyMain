# AI chat kit — the Customer Support agent in the floating window keeps 👍/👎 (with a note after 👎)
# and pass-to-a-human (Escalated). Ratings save through the unchanged feedback endpoint.
# Worked examples: openspec/changes/ai-chat-kit/design.md#worked-examples
@rack_test
Feature: Customer Support agent extras on the chat kit

  Background:
    Given "Priya Sharma" is a fund manager at "Golden Angels" with the fund "Golden Angels Fund I"
    And Golden Angels has the "CustomerSupportAgent" agent "Customer Support" with chat on
    And Priya has a Customer Support conversation "How do I issue a call?" answered "Go to Fund › Capital Calls › New."

  # H9 — Happy path: 👎 with a note saves to the review queue, and the rating shows again when the conversation is reopened
  Scenario: Rate down with a note
    When Priya opens the Customer Support window
    Then the answer offers 👍 and 👎
    When Priya rates the answer "negative"
    And Priya sends the feedback note "Wrong fund"
    Then the answer's feedback is "negative" with the note "Wrong fund"
    When Priya opens the Customer Support window
    Then the answer shows its rating "negative"

  # H10 — Happy path: a conversation passed to a human shows Escalated in the list
  Scenario: Escalated conversation
    Given that conversation was passed to a human
    When Priya opens a new conversation in the Customer Support window
    Then the conversation "How do I issue a call?" shows "Escalated"

  # E12 — Edge case: other agents' answers have no rating
  Scenario: No rating on other agents
    Given Golden Angels has the "PortfolioAssistantAgent" agent "Portfolio Assistant" with chat on
    And Priya has a "Portfolio Assistant" conversation on "Golden Angels Fund I" answered "Valuations rose."
    When Priya opens the "Portfolio Assistant" window on "Golden Angels Fund I"
    Then the answer offers no rating

  # X9 — Error case: another entity's user cannot rate Priya's answer
  Scenario: Rating another user's answer
    Given "Arjun Rao" of "Beta Capital" is signed in
    When Arjun rates Priya's answer "negative"
    Then the rating is refused and nothing is saved
