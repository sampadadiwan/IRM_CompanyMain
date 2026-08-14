@llm
Feature: Portfolio Scoring Agent scoring accuracy
  As a fund manager
  I want the scoring agent to rank companies the way the rubric says it should
  So that I can trust the tiers on the Portfolio Scoring Dashboard

  # This is an ACCURACY test, not a plumbing test. The real LlmService.ruby_llm_chat
  # is called — no doubles — so the LLM actually reads the rubric and the company data
  # and produces a real score. Config/plumbing coverage lives in
  # portfolio_scoring_agent_config.feature and portfolio_scoring_dashboard.feature.
  #
  # Experimental design: all three companies share sector "SaaS", so all three resolve
  # to the SAME skill file (the "sector: General" fallback, which is the real bundled
  # rubric at public/sample_uploads/portfolio_scoring_generic_skill.txt). The rubric is
  # held constant; the only variable is data quality. Score differences therefore
  # measure scoring accuracy rather than skill-file routing.
  #
  # Each company's KPIs, valuations and narrative are built to sit in the MIDDLE of a
  # rubric band on every one of the five dimensions — no boundary cases:
  #
  #   Dimension (weight)        | Apex Analytics | Meridian Cloud | Halcyon Systems
  #   Revenue & Growth   (0.25) | +74% YoY       | +21% YoY       | -19% YoY
  #   Unit Economics     (0.25) | GM 79/LTV 4.4x | GM 47/LTV 2.3x | GM 17/LTV 0.8x
  #   Efficiency & Burn  (0.20) | 26mo / 0.6x    | 14mo / 1.4x    | 4mo / 3.2x
  #   Valuation & Return (0.20) | up round 6.2x  | flat 4.5x ARR  | 58% down round
  #   KPI Quality        (0.10) | 5 of 5 qtrs    | 4 of 5 qtrs    | 3 of 5 qtrs
  #   ------------------------------------------------------------------------------
  #   Weighted prediction       | ~90 (A, outperform) | ~66 (B, on_track) | ~20 (D, at_risk)
  #
  # Assertions are deliberately layered so normal LLM variance does not fail the build:
  # ordering + minimum gap is the primary signal (robust to uniform bias), score bands
  # carry 10-25 points of buffer, and the tier is pinned only for the two extremes.
  #
  # ```mermaid
  # sequenceDiagram
  #   participant T as Cucumber
  #   participant PS as PortfolioScoringAgent
  #   participant SA as SupportAgent
  #   participant LLM as LlmService (live gemini-3-flash-preview)
  #   participant R as SupportAgentReport
  #   T->>PS: call(support_agent_id:, target: investor)
  #   PS->>SA: skill_for_sector("SaaS")
  #   SA-->>PS: Generic Portfolio Skill document (real rubric)
  #   PS->>PS: gather KPIs (Actual/approved), valuations, narrative doc
  #   PS->>LLM: skill rubric + company data
  #   LLM-->>PS: {overall_score, grade, dimensions, ...}
  #   PS->>R: create!(status: completed, json_fields["score"])
  #   T->>R: assert ordering, bands, tier, structure
  # ```

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is a portfolio scoring agent using the real generic scoring rubric

  Scenario: The agent separates a strong, an average and a distressed company
    Given a strong-performing portfolio company "Apex Analytics"
    And an average-performing portfolio company "Meridian Cloud"
    And a distressed portfolio company "Halcyon Systems"
    When the portfolio scoring agent scores all three companies
    Then the scores should be ordered "Apex Analytics" then "Meridian Cloud" then "Halcyon Systems" with a gap of at least 15
    And "Apex Analytics" should score at least 80 and land in the "outperform" tier
    And "Meridian Cloud" should score between 55 and 79 and land in neither the "outperform" nor the "at_risk" tier
    And "Halcyon Systems" should score at most 45 and land in the "at_risk" tier
    And every scoring report should be complete and internally consistent
