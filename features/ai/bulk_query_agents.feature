# Query budgets for the ai-pack agents (round 2 of the bulk-path query work, tmp/query_fixes_round2.md).
# Each scenario runs the real agent code and counts queries by the line that issued them
# (features/step_definitions/query_budget_steps.rb).

@rack_test
Feature: AI agents read their data in a fixed number of queries

  # R1 — Happy path: the RTA agent loads a scheme's commitments and investors once, not once per folio
  Scenario: R1-H1 RTA reconciliation looks up every folio of a scheme in one query
    Given there is a user "first_name=RtaAdmin" for an entity "name=RtaTestEntity;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an RtaReconciliationAgent configured for the entity
    And there is a fund "name=Test Fund" for the entity
    And the fund has a FundUnitSetting with ISIN "INF123A010AX" and name "Class A"
    And the fund has 5 capital commitments with folio_ids and unit_type "Class A" totalling 50000 units
    And the RTA statement PDF contains scheme "Test Fund" ISIN "INF123A010AX" closing units 50000
    And the PDF folio breakdown matches all 5 capital commitments exactly
    And I count queries by call site
    When the RtaReconciliationAgent runs for the fund
    Then the RTA report has no blocking issues
    And the report health_score is 100
    # summary SUM + the folio lookup + the reverse "missing from RTA" check (was 2 + one per folio)
    And at most 3 statements containing 'FROM "capital_commitments"' came from "RtaReconciliationAgent#reconcile_schemes"
    # the investors preload (was one per folio)
    And at most 1 statement containing 'FROM "investors"' came from "RtaReconciliationAgent#reconcile_schemes"

  # R1 — Edge case: a folio number that differs from CapHive's only in letter case still matches, as the per-folio
  # MySQL lookup did (folio_id's collation is case-insensitive)
  Scenario: R1-E1 An RTA folio number in different letter case still matches its commitment
    Given there is a user "first_name=RtaAdmin" for an entity "name=RtaTestEntity;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an RtaReconciliationAgent configured for the entity
    And there is a fund "name=Test Fund" for the entity
    And the fund has a FundUnitSetting with ISIN "INF123A010AX" and name "Class A"
    And the fund has 1 capital commitment with folio_id "FX-AB12" and unit_type "Class A" with 100 units
    And the RTA statement PDF contains scheme "Test Fund" ISIN "INF123A010AX" closing units 100
    And the PDF folio breakdown has folio "fx-ab12" with closing units 100
    When the RtaReconciliationAgent runs for the fund
    Then the RTA folio "fx-ab12" is matched to its commitment with status "match"
    And the report has no blocking issue matching "not found in CapHive"

  # R2 — Happy path: the scoring agent reads KPIs and their mappings preloaded, not per report and per KPI
  Scenario: R2-H1 Portfolio scoring gathers KPI data in three queries
    Given there is a user "first_name=Scorer" for an entity "name=ScoreCo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing portfolio company "name=Apex Analytics;category=Portfolio Company"
    And the portfolio company has 3 Actual quarterly KPI reports, each with 4 approved and 1 unapproved KPI
    And there is a portfolio scoring agent for the entity
    And I count queries by call site
    When the portfolio scoring agent gathers KPI data for the portfolio company
    Then 3 KPI periods are gathered, each with 4 KPIs carrying their denomination
    # reports + KPIs + mappings (was 2 + one per report + one per KPI = 17 here)
    And at most 3 queries came from "PortfolioScoringAgent#gather_kpi_data"

  # R2 — Edge case: unapproved KPIs are still left out, now picked in Ruby from the preloaded KPIs
  Scenario: R2-E1 Portfolio scoring leaves out a report whose KPIs are all unapproved
    Given there is a user "first_name=Scorer" for an entity "name=ScoreCo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing portfolio company "name=Apex Analytics;category=Portfolio Company"
    And the portfolio company has 3 Actual quarterly KPI reports, each with 4 approved and 1 unapproved KPI
    And the portfolio company has 1 more Actual quarterly KPI report with only unapproved KPIs
    And there is a portfolio scoring agent for the entity
    When the portfolio scoring agent gathers KPI data for the portfolio company
    Then 3 KPI periods are gathered, each with 4 KPIs carrying their denomination

  # R5 — Happy path: the all-FAQs page reads every guide's published entries in one query
  Scenario: R5-H1 The all-FAQs catalog reads every guide's FAQ entries in one query
    Given there is a user "first_name=Faq" for an entity "name=FaqCo;entity_type=Investment Fund"
    And published FAQ entries exist for 2 user guides
    And I count queries by call site
    When the all-FAQs catalog is built
    Then the catalog lists the published FAQ entries of those 2 guides in display order
    # one query for every guide (was one per guide in the catalog - about 88)
    And at most 1 statement containing 'FROM "faq_entries"' came from "app/packs/ai/guide_faqs/services/faq_section_renderer.rb"

  # R5 — Edge case: a public reader still sees only public entries
  Scenario: R5-E1 The public all-FAQs catalog leaves out signed-in-only entries
    Given there is a user "first_name=Faq" for an entity "name=FaqCo;entity_type=Investment Fund"
    And published FAQ entries exist for 2 user guides
    When the public all-FAQs catalog is built
    Then the catalog lists only the public FAQ entries of those 2 guides
