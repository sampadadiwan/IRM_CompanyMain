Feature: Presentation Analyst Dashboard
  As a fund manager
  I want my portfolio companies bucketed by Management Accountability tier
  So that I can see at a glance which management teams follow through on what they say

  # Mirrors the Portfolio Scoring Dashboard's central rule: a company's tier
  # comes from the validated 0-100 overall_score, never from the report's
  # free-text grade string.
  #
  # The one rule unique to this dashboard: compute_scores' arithmetic returns
  # neutral-to-generous defaults when every input array is empty — exactly
  # what happens on a run that found zero presentations — so a "blocked" run
  # must never be read as a real score even though the payload has one.
  #
  # ```mermaid
  # sequenceDiagram
  #   participant FM as Fund Manager
  #   participant C as PresentationAnalystDashboardController
  #   participant R as SupportAgentReport
  #   participant P as PresentationAnalystPresenter
  #   FM->>C: GET /presentation_analyst_dashboard?status=
  #   C->>R: presentation-analysis reports, last 12 months
  #   R-->>C: reports (all runs, newest first)
  #   C->>P: new(reports, agent, company_ids:)
  #   P->>P: group_by(owner_id) -> latest + previous
  #   P->>P: score_for(report) guards on final_status != "blocked"
  #   P->>P: tier_for(overall_score) per company
  #   P-->>C: counts, distribution, movers, cross-period flags
  #   C->>C: filter_by_tier(scope, params[:status])
  #   C-->>FM: tier cards, distribution, cross-period flags, filtered table
  # ```

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is a presentation analyst agent for the dashboard

  # ── Bucketing comes from the score, not the grade string ─────────────────

  Scenario Outline: Scores land in the tier their band defines
    Given an analyzed portfolio company "Edge Co" with score <score> and grade "X"
    When I visit the presentation analyst dashboard
    Then the "<tier>" tier should show 1 company

    Examples:
      | score | tier                 |
      | 49    | at_risk              |
      | 50    | watch                |
      | 59    | watch                |
      | 60    | reliable             |
      | 79    | reliable             |
      | 80    | high_accountability  |

  Scenario: A blocked run's default arithmetic score is not treated as real
    Given a blocked presentation run for portfolio company "Ghost Co"
    When I visit the presentation analyst dashboard
    Then the "high_accountability" tier should show 0 companies
    And the not-analyzed breakdown should show 1 blocked and 0 never run

  Scenario: A company with scoring deliberately disabled is not counted as blocked
    Given a portfolio company "Opted Out Co" analyzed with scoring disabled
    When I visit the presentation analyst dashboard
    Then the not-analyzed breakdown should show 0 blocked and 0 never run
    And I should see "Opted Out Co" marked as scoring disabled in the presentation table

  Scenario: A scoring-disabled company's real flags still reach the portfolio-wide panel
    Given a portfolio company "Opted Out Co" analyzed with scoring disabled and a dropped risk "Customer concentration"
    When I visit the presentation analyst dashboard
    Then the "Risk Evolution" lens should show 1 item

  # ── Labelling convention ─────────────────────────────────────────────────

  Scenario: Cards name the tier with its grades in parentheses
    Given an analyzed portfolio company "Acme" with score 72 and grade "B+"
    When I visit the presentation analyst dashboard
    Then I should see the tier label "Watch (C)"
    And I should see the tier label "Reliable (B / C+)"

  # ── Drill-down ───────────────────────────────────────────────────────────

  Scenario: A tier filter narrows the table to that bucket
    Given an analyzed portfolio company "Strong Co" with score 88 and grade "A"
    And an analyzed portfolio company "Weak Co" with score 55 and grade "C"
    When I visit the presentation analyst dashboard filtered by "watch"
    Then I should see "Weak Co" in the presentation table
    And I should not see "Strong Co" in the presentation table

  # ── Not Analyzed is a first-class bucket ──────────────────────────────────

  Scenario: Companies never analyzed are reported separately from blocked runs
    Given a portfolio company "Fresh Prospect" that has never been analyzed
    And a blocked presentation run for portfolio company "Ghost Co"
    When I visit the presentation analyst dashboard
    Then the not-analyzed breakdown should show 1 blocked and 1 never run

  Scenario: The not-analyzed view lists companies that have no report at all
    Given a portfolio company "Fresh Prospect" that has never been analyzed
    When I visit the presentation analyst dashboard filtered by "not_analyzed"
    Then I should see "Fresh Prospect" listed as never analyzed

  # ── Movement ─────────────────────────────────────────────────────────────

  Scenario: Delta compares against the previous analysis run
    Given a portfolio company "Riser" analyzed 55 three months ago and 72 now
    When I visit the presentation analyst dashboard
    Then the movement panel should show 1 improved

  Scenario: A company analyzed only once has no delta
    Given an analyzed portfolio company "Fresh Co" with score 72 and grade "B+"
    When I visit the presentation analyst dashboard
    Then the movement panel should show 0 improved and 0 declined

  # ── Cross-Period Flags — no equivalent on the scoring dashboard ──────────

  Scenario: The cross-period flags panel tallies flags across the portfolio
    Given an analyzed portfolio company "Acme" with score 72 and a dropped risk "Data residency compliance"
    When I visit the presentation analyst dashboard
    Then the "Risk Evolution" lens should show 1 item

  # ── Cross-reference against PortfolioScoringAgent ─────────────────────────

  Scenario: A company with strong fundamentals but weak accountability is flagged
    Given there is also a portfolio scoring agent for the dashboard
    And an analyzed portfolio company "Acme" with score 35 and grade "D"
    And "Acme" also has a fundamentals score of 85
    When I visit the presentation analyst dashboard
    Then I should see the narrative risk callout for "Acme"

  Scenario: The cross-reference callout does not appear without a scoring agent
    Given an analyzed portfolio company "Acme" with score 35 and grade "D"
    When I visit the presentation analyst dashboard
    Then I should not see the narrative risk callout for "Acme"

  # ── Run modal — rendering only, never submitted. Submitting it runs the
  #    real Trailblazer pipeline under the :inline job adapter, which makes a
  #    live LLM call (see the @llm-tagged scenarios in
  #    investor_presentation_analyst_agent.feature) — the sibling Portfolio
  #    Scoring Dashboard's own suite never submits its run modal for the same
  #    reason, so this dashboard follows that convention rather than adding a
  #    scenario that would need real API keys to pass. ─────────────────────

  Scenario: The run modal offers the never-analyzed count as a target mode
    Given a portfolio company "Fresh Prospect" that has never been analyzed
    And an analyzed portfolio company "Acme" with score 72 and grade "B+"
    When I visit the presentation analyst dashboard
    Then the run analysis modal should offer 1 never-analyzed company

  # ── Authorization ────────────────────────────────────────────────────────

  Scenario: A user from another entity cannot reach the dashboard
    Given an analyzed portfolio company "Acme" with score 72 and grade "B+"
    And I am logged in as a user from a different entity
    When I try to visit the presentation analyst dashboard
    Then I should be denied access to the presentation analyst dashboard
