# Security review 2026-10, N8 — the record a support-agent run names.
# support_agents#run / #run_with_steps resolve target_type through ApplicationRecord.model_class_from_param
# (allow-list SupportAgent::RUN_TARGET_TYPES, the types the UI sends) and set SupportAgent#run_target, which
# SupportAgentPolicy#run? checks with users_firm?. SupportAgentJob refuses any target outside the agent's own
# firm, so a job enqueued by any path cannot reach another tenant's record either.
# Worked examples: docs/security/security_review_2026_10.md (N8 row, L14 row)
@security @rack_test
Feature: A support agent runs only over its own firm's records

  Background:
    Given "Priya Sharma" is a fund manager at "Golden Angels" with the fund "Golden Angels Fund I"
    And Golden Angels has the "PortfolioCompanyAgent" agent "PortCo Analyst" with chat on
    And Golden Angels has the "NoteSummarizerAgent" agent "Note Summariser" with chat on
    And Golden Angels has the "RtaReconciliationAgent" agent "RTA Reconciler" with chat on
    And a portfolio company "Golden Robotics" exists
    And another firm "Zeta Capital" has a portfolio company "Zeta Labs" and a fund "Zeta Fund I"

  # N8-1 — Edge case: Priya runs her own agent against a record of Zeta; refused before any report is created
  Scenario Outline: N8-1 Running an agent over another firm's <type> through <endpoint> is refused
    Given the support agents are watched and must not run
    When Priya runs the "<agent>" agent through "<endpoint>" on the <type> "<name>"
    Then I am refused
    And no agent ran and no agent report or document was created

    Examples:
      | agent                 | endpoint       | type     | name         |
      | PortfolioCompanyAgent | run            | Investor | Zeta Labs    |
      | NoteSummarizerAgent   | run            | Investor | Zeta Labs    |
      | PortfolioCompanyAgent | run_with_steps | Investor | Zeta Labs    |
      | PortfolioCompanyAgent | run_with_steps | Entity   | Zeta Capital |

  # N8-1 — Edge case: the RTA statement upload is not filed on Zeta's fund either
  Scenario: N8-1 An RTA statement uploaded against another firm's fund is refused and not saved
    Given the support agents are watched and must not run
    When Priya runs the "RtaReconciliationAgent" agent on the Fund "Zeta Fund I" with an RTA statement PDF
    Then I am refused
    And no agent ran and no agent report or document was created

  # N8-2 — Edge case: the job itself, performed with a foreign (or non-model) target, refuses it
  Scenario Outline: N8-2 The agent job performed for <target_type> <name> runs nothing
    Given the support agents are watched and must not run
    When the "PortfolioCompanyAgent" job is performed for target type "<target_type>" with the id of the <type> "<name>"
    Then no agent ran and no agent report or document was created
    And the "PortfolioCompanyAgent" run is logged as failed with "is not a record of this firm"

    Examples:
      | target_type | type     | name            |
      | Investor    | Investor | Zeta Labs       |
      | Entity      | Entity   | Zeta Capital    |
      | Kernel      | Investor | Golden Robotics |

  # N8-H — Happy path: each of two agent kinds still runs on Priya's own portfolio company
  Scenario Outline: N8-H The <agent> runs on the firm's own portfolio company
    Given the LLM is stubbed for the agent run
    When Priya runs the "<agent>" agent through "run" on the Investor "Golden Robotics"
    Then the request succeeds
    And the "<agent>" agent ran once on the Investor "Golden Robotics"

    Examples:
      | agent                 |
      | PortfolioCompanyAgent |
      | NoteSummarizerAgent   |

  # N8-X — Edge case: a target type that is not an allowed model is a 404, not a 500
  Scenario Outline: N8-X Target type <type> through <endpoint> is not found
    Given the support agents are watched and must not run
    When Priya runs the "PortfolioCompanyAgent" agent through "<endpoint>" with target type "<type>"
    Then the run is not found
    And no agent ran and no agent report or document was created

    Examples:
      | endpoint       | type               |
      | run            | Kernel             |
      | run            | ActiveRecord::Base |
      | run            | NoSuchModel        |
      | run            | SupportAgentReport |
      | run_with_steps | Kernel             |
      | run_with_steps | SupportAgentReport |
