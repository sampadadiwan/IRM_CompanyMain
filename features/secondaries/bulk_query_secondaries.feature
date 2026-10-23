# Query budgets for the secondaries pack (round 2 of the bulk-path query work, tmp/query_fixes_round2.md).
# Counts queries by the line that issued them (features/step_definitions/query_budget_steps.rb).

@notification @import
Feature: Secondary sale notifications load their recipients in a fixed number of queries

  # R3 — Happy path: "allocation complete" loads every verified offer's user and investor in one query each,
  # and every seller still gets the email
  Scenario: R3-H1 The allocation complete email loads offer users and investors once
    Given Im logged in as a user "first_name=Emp1" for an entity "entity_type=Company"
    Given the user has role "company_admin"
    Given there is a sale "name=Grand Sale;price_type=Fixed Price;final_price=10000;percent_allowed=100"
    And the sale has an allocation SPA template
    And Given I upload an investors file for the company
    And Given I upload an investor access file for employees
    And Given I upload a offer file "offers_allocate.xlsx"
    And when the offers are approved
    And given I upload an interests file "interests_allocate.xlsx"
    Then when the allocation is done
    Then when the allocations are verified
    And every approved offer of the sale is verified
    Given the email queue is cleared
    And I count queries by call site
    When the allocation complete notification is sent for the sale
    Then each seller must receive email with subject "Secondary Sale: #{@sale.name} allocation complete."
    # The offers loop (lines 46-47): users and investors come from the find_each preload on line 46, none from
    # the per-offer line 47 (was one user or investor lookup per verified offer there). The recipients' own
    # lookups (Investor#notification_users) and the interests loop below are not part of this budget.
    And at least 1 statement containing 'FROM "users"' came from "app/packs/secondaries/secondary_sales/models/concerns/secondary_sale_notifiers.rb:46"
    And at most 0 statements containing 'FROM "users"' came from "app/packs/secondaries/secondary_sales/models/concerns/secondary_sale_notifiers.rb:47"
    And at most 0 statements containing 'FROM "investors"' came from "app/packs/secondaries/secondary_sales/models/concerns/secondary_sale_notifiers.rb:47"
