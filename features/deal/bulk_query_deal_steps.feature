# Query budgets for deal step generation (round 3 of the bulk-path query work, tmp/query_fixes_round3.md).
# Counts queries by the line that issued them (features/step_definitions/query_budget_steps.rb).
# acts_as_list keeps deal steps numbered by shifting every later step when one is inserted; appending a step after
# the last one has nothing to shift, so D1/D2 skip that UPDATE there and keep it for inserts among existing steps.

@rack_test
Feature: Deal steps are generated without per-step lookups or renumbering

  Background:
    Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Company"
    Given the user has role "company_admin"

  # D1 — Happy path: investors with no steps yet get every template step, numbered in order, with one lookup per
  # investor and no renumbering UPDATEs
  Scenario: D1-H1 Generating a deal's steps reads each investor's steps once and never renumbers
    Given there exists a deal "name=Series A;amount_cents=500000" for my company without templates
    And the deal has "5" step templates
    And the deal has 3 investors with no steps yet
    And I count queries by call site
    When the deal's steps are generated for its investors
    Then every investor of the deal has the template steps, numbered 1 to 5 in template order
    # per investor: the deal's templates + one read of the investor's steps (was the templates + one lookup per
    # template: 3 + 15 = 18 here)
    And at most 6 statements containing 'FROM "deal_activities"' came from "DealInvestor#create_activities"
    # appends only, so nothing to shift (was one UPDATE per new step: 15 here)
    And at most 0 statements containing '"sequence" + ' came from "DealInvestor#create_activities"

  # D1 — Edge case: a template inserted between existing steps still renumbers the investor's later steps, and
  # re-generating keeps every investor's steps in template order with no duplicate numbers
  Scenario: D1-E1 A template inserted mid-list still renumbers investors' later steps
    Given there exists a deal "name=Series A;amount_cents=500000" for my company without templates
    And the deal has "3" step templates
    And the deal has 2 investors with no steps yet
    When the deal's steps are generated for its investors
    And a template "Inserted Step" is inserted at position 2 of the deal
    And the deal's steps are generated for its investors
    Then every investor of the deal has the template steps, numbered 1 to 4 in template order

  # D2 — Happy path: a cloned deal's template steps are created numbered 1..n with no renumbering UPDATEs
  Scenario: D2-H1 Creating a deal creates its template steps without renumbering
    Given there exists a deal "name=Source Deal;amount_cents=500000" for my company without templates
    And the deal has "4" step templates
    And I count queries by call site
    When I create a deal cloning from the source deal
    Then the cloned deal should have "4" step templates
    And the cloned deal's template steps are numbered 1 to 4 in the source deal's order
    # a new deal has no steps to shift (was one UPDATE per template step: 4 here)
    And at most 0 statements containing '"sequence" + ' came from "app/packs/startups/deals/services/create_deal.rb"
