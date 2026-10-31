# Portfolio Company Assistant — a broken tool must not break the conversation.
# Found from a live failure: every question that used get_portfolio_company_snapshot failed with
# "The last response has unanswered tool calls (get_portfolio_company_snapshot)…", and the
# conversation then refused every later question.
@rack_test
Feature: Portfolio Company Assistant tool resilience

  Background:
    Given "Priya Sharma" is a fund manager at "Golden Angels" with the fund "Golden Angels Fund I"
    And Golden Angels has the portfolio company "AX"

  # X1 — Error case: the snapshot of the assistant's own company works (the subclass rejected portfolio_company_id)
  Scenario: Company snapshot
    When the Portfolio Company Assistant for "AX" takes its snapshot
    Then the snapshot names "AX"

  # X2 — Error case: a tool that raises reports its error to the model instead of breaking the round
  Scenario: A failing tool returns an error result
    When an assistant tool fails with "database unavailable"
    Then the model gets the error "The get_portfolio_company_snapshot tool failed: database unavailable"

  # X3 — Error case: a conversation left with an unanswered tool call is repaired before the next question
  Scenario: Stuck conversation repaired
    Given a Portfolio Company Assistant conversation on "AX" ended with an unanswered "get_portfolio_company_snapshot" call
    When the assistant prepares to answer the next question
    Then 1 unanswered tool call is closed with an error result
    And the conversation accepts a new question
