Feature: Portfolio Scoring Dashboard
  As a fund manager
  I want my portfolio companies bucketed by grade tier
  So that I can see at a glance how many are strong and how many need attention

  # The dashboard's central rule: a company's tier comes from the validated
  # 0-100 overall_score, never from the LLM's free-text grade string. Different
  # sector skill files can use different letter conventions, and only
  # overall_score is enforced by PortfolioScoringAgent#validate_score_keys!.
  # The grade is displayed beside the tier so the card reconciles against the
  # badge on each company's own score card.
  #
  # ```mermaid
  # sequenceDiagram
  #   participant FM as Fund Manager
  #   participant C as PortfolioScoringDashboardController
  #   participant R as SupportAgentReport
  #   participant P as PortfolioScoringPresenter
  #   FM->>C: GET /portfolio_scoring_dashboard?status=&basis=
  #   C->>R: scoring reports, last 12 months, selected columns
  #   R-->>C: reports (all runs, newest first)
  #   C->>P: new(reports, agent, basis:)
  #   P->>P: group_by(owner_id) -> latest + previous
  #   P->>P: tier_for(overall_score) per company
  #   P-->>C: counts, distribution, movers, not-scored breakdown
  #   C->>C: filter_by_tier(scope, params[:status])
  #   C-->>FM: tier cards, distribution, filtered table
  # ```

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is a portfolio scoring agent for the dashboard

  # ── Bucketing comes from the score, not the grade string ─────────────────

  Scenario: A nonsense grade still buckets by score
    Given a scored portfolio company "Oddball" with score 85 and grade "Z"
    When I visit the portfolio scoring dashboard
    Then the "outperform" tier should show 1 company
    And I should see the grade "Z" for "Oddball"

  Scenario Outline: Scores land in the tier their band defines
    Given a scored portfolio company "Edge Co" with score <score> and grade "X"
    When I visit the portfolio scoring dashboard
    Then the "<tier>" tier should show 1 company

    Examples:
      | score | tier       |
      | 39    | at_risk    |
      | 40    | watch      |
      | 59    | watch      |
      | 60    | on_track   |
      | 79    | on_track   |
      | 80    | outperform |

  # ── Labelling convention ─────────────────────────────────────────────────

  Scenario: Cards name the tier with its grades in parentheses
    Given a scored portfolio company "Acme" with score 72 and grade "B+"
    When I visit the portfolio scoring dashboard
    Then I should see the tier label "Watch List (C+ / C)"
    And I should see the tier label "On Track (B+ / B)"

  # ── Drill-down ───────────────────────────────────────────────────────────

  Scenario: A tier filter narrows the table to that bucket
    Given a scored portfolio company "Strong Co" with score 88 and grade "A"
    And a scored portfolio company "Weak Co" with score 45 and grade "C"
    When I visit the portfolio scoring dashboard filtered by "watch"
    Then I should see "Weak Co" in the scoring table
    And I should not see "Strong Co" in the scoring table

  Scenario: Filter links use the tier slug, not the grade letters
    Given a scored portfolio company "Acme" with score 72 and grade "B+"
    When I visit the portfolio scoring dashboard
    Then the tier card links should use slug "watch"

  # ── Not Scored is a first-class bucket ───────────────────────────────────

  Scenario: Companies with no sector are reported separately from failures
    Given a portfolio company "No Sector Co" with no sector
    And a failed scoring run for portfolio company "Broken Co"
    When I visit the portfolio scoring dashboard
    Then the not-scored breakdown should show 1 failed and 1 without a sector

  Scenario: The not-scored view lists companies that have no report at all
    Given a portfolio company "No Sector Co" with no sector
    When I visit the portfolio scoring dashboard filtered by "not_scored"
    Then I should see "No Sector Co" listed as never scored

  # ── Movement ─────────────────────────────────────────────────────────────

  Scenario: Delta compares against the previous scoring run
    Given a portfolio company "Riser" scored 55 three months ago and 72 now
    When I visit the portfolio scoring dashboard
    Then the movement panel should show 1 improved

  Scenario: A company scored only once has no delta
    Given a scored portfolio company "Fresh Co" with score 72 and grade "B+"
    When I visit the portfolio scoring dashboard
    Then the movement panel should show 0 improved and 0 declined

  Scenario: Every movement figure opens the rows behind it
    Given a portfolio company "Riser" scored 55 three months ago and 72 now
    When I visit the portfolio scoring dashboard filtered by "improved"
    Then I should see "Riser" in the scoring table
    And I should see the filter chip "Improved since last run"

  Scenario: A movement figure of zero is not a link
    Given a scored portfolio company "Fresh Co" with score 72 and grade "B+"
    When I visit the portfolio scoring dashboard
    Then the "improved" movement figure should not be a link

  # ── Sector and tag scope the whole portfolio, not just the table ─────────

  Scenario: Filtering by sector rescopes every figure on the page
    Given a scored portfolio company "Saas Co" in sector "SaaS" with score 85
    And a scored portfolio company "Bio Co" in sector "Biotech" with score 45
    When I visit the portfolio scoring dashboard scoped to sector "SaaS"
    Then the "outperform" tier should show 1 company
    And the "watch" tier should show 0 companies
    And I should see "Saas Co" in the scoring table
    And I should not see "Bio Co" in the scoring table
    And I should see the scope banner for "sector SaaS"

  Scenario: Filtering by tag rescopes every figure on the page
    Given a scored portfolio company "Tagged Co" tagged "Growth" with score 85
    And a scored portfolio company "Untagged Co" in sector "SaaS" with score 85
    When I visit the portfolio scoring dashboard scoped to tag "Growth"
    Then the "outperform" tier should show 1 company
    And I should see the scope banner for "tag Growth"

  Scenario: A tier card keeps the active sector scope
    Given a scored portfolio company "Saas Co" in sector "SaaS" with score 85
    When I visit the portfolio scoring dashboard scoped to sector "SaaS"
    Then the tier card links should keep the sector scope "SaaS"

  # ── Value basis ──────────────────────────────────────────────────────────

  Scenario: The value toggle preserves the active tier filter
    Given a scored portfolio company "Weak Co" with score 45 and grade "C"
    When I visit the portfolio scoring dashboard filtered by "watch"
    Then the value toggle link should keep the "watch" filter

  # ── Authorization ────────────────────────────────────────────────────────

  Scenario: A user from another entity cannot reach the dashboard
    Given a scored portfolio company "Acme" with score 72 and grade "B+"
    And I am logged in as a user from a different entity
    When I try to visit the portfolio scoring dashboard
    Then I should be denied access to the scoring dashboard
