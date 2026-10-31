# AI chat kit — a real-browser smoke test (Playwright) of the floating window's Stimulus controllers,
# which the rack_test features cannot run: opening from the bubble, Enter sending with the question
# and "Thinking…" shown at once, a suggestion's Ask, and Maximise showing the conversation list.
# Worked examples: openspec/changes/ai-chat-kit/design.md#worked-examples (H6, H11, H12)
Feature: Floating chat window in the browser

  Background:
    Given "Priya Sharma" is a fund manager at "Golden Angels" with the fund "Golden Angels Fund I"
    And Golden Angels has the "PortfolioAssistantAgent" agent "Portfolio Assistant" with chat on
    And the agent answers slowly "Valuations rose 8% this quarter."

  # H6 / H12 — Happy path: the bubble opens the window; Enter shows the question and "Thinking…" at once, then the answer
  Scenario: Ask from the bubble
    When Priya opens the Portfolio Assistant agent's page
    And Priya clicks the chat bubble
    And Priya types "Show recent valuations" in the window and presses Enter
    Then the window shows "Show recent valuations" with "Thinking…" before the answer arrives
    And the window shows the answer "Valuations rose 8% this quarter."

  # H11 — Happy path: a suggestion's Ask sends it straight away
  Scenario: Ask a suggestion
    When Priya opens the Portfolio Assistant agent's page
    And Priya clicks the chat bubble
    And Priya clicks Ask on the suggestion "Show recent valuations"
    Then the window shows the answer "Valuations rose 8% this quarter."

  # H12 — Happy path: Maximise fills the screen and shows the conversation list beside the thread
  Scenario: Maximise shows the list
    When Priya opens the Portfolio Assistant agent's page
    And Priya clicks the chat bubble
    And Priya maximises the window
    Then the window's conversation list is visible beside the thread
