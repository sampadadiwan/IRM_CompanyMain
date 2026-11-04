# Security review 2026-10, H3 — the support-agent chat window's target record.
# SupportAgentChatsController#find_chattable resolves chattable_type with safe_constantize and accepts only
# ApplicationRecord models; load_window then authorizes the record with its own policy's show?. A target
# the user may not see is refused before the agent (and the report's documents) is reached.
# Ships with C3: AiPortfolioReportPolicy#show? is what refuses another firm's report.
# Worked examples: docs/security/security_review_2026_10.md (## H3 — Support-agent chat target)
@security @rack_test
Feature: The chat window's record is one the user may see

  Background:
    Given "Priya Sharma" is a fund manager at "Golden Angels" with the fund "Golden Angels Fund I"
    And Golden Angels has the "PortfolioReportAgent" agent "Portfolio Report Agent" with chat on
    And another firm "Zeta Capital" has a portfolio company "Zeta Labs" with an AI portfolio report
    And Zeta's report reads an evaluation folder holding "zeta_pitch_deck.pdf"

  # H3-1 — Error case: opening the window about Zeta's report is refused; the agent is not called
  Scenario: H3-1 Opening a chat about another firm's report is refused
    Given the chat agent must not be called
    When Priya opens the window about Zeta's report
    Then the window is refused

  # H3-2 — Error case: asking about Zeta's report is refused; the agent is not called and nothing is saved
  Scenario: H3-2 Asking about another firm's report is refused
    Given the chat agent must not be called
    When Priya asks the window "Summarise the pitch deck" about Zeta's report
    Then the question is refused without a server error and nothing is saved

  # H3-3 — Edge case: a target type that is not a model falls back to the agent, without an error
  Scenario Outline: H3-3 Target type <type> falls back to the agent
    When Priya opens the window with target type "<type>"
    Then the window opens about the agent

    Examples:
      | type               |
      | Kernel             |
      | ActiveRecord::Base |

  # H3-H — Happy path: a chat about the firm's own report is answered
  Scenario: H3-H Priya chats about her own firm's report
    Given a portfolio company "Golden Robotics" exists
    And an AI portfolio report exists for "Golden Robotics"
    And the agent answers "The deck shows 40% revenue growth."
    When Priya asks the window "Summarise the pitch deck" about her report
    Then the window shows the question "Summarise the pitch deck" and the answer "The deck shows 40% revenue growth."

  # H3-X — Edge case: an LP on the GP's LP agent chats about herself, but not about another investor
  Scenario: H3-X An LP may target herself but not another investor's user
    Given Golden Angels has the "LpAssistantAgent" agent "LP Assistant" with chat on
    And "Kavya Iyer" is an investor of Golden Angels with her own LP chat "What's my current IRR?"
    And another investor of Golden Angels has an LP chat "Show my SOA"
    When Kavya opens her LP chat
    Then the window lists "What's my current IRR?"
    When Kavya opens an LP chat about the other investor
    Then the window is refused
