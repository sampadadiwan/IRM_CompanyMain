# Worked examples X1–X5, X7–X9, X19, X20 — openspec/changes/grid-columns-inline-settings/business-rules.md#1-table-columns--phase-1
@rack_test @security
Feature: Table columns in place — access
  Only a company admin of the firm, not acting as an investor, may open or save a table's columns. Direct requests
  that bypass the page are refused the same way, and a save changes nothing but columns, headings and order.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And my firm's "Investor" columns are "investor_name, category"

  # X1 — Error case: an employee who is not a company admin gets no button; direct requests are refused
  Scenario: Plain employee refused
    Given I am signed in as a plain employee of my firm
    When I open the "/investors" page
    Then there should be no columns button
    When I request the columns panel for my firm's "Investor" form type
    Then the columns request should be refused
    When I save the "Investor" columns "city" directly
    Then the columns request should be refused
    And my firm's "Investor" columns should be "investor_name, category"

  # X2 — Error case: acting as an investor — no button, direct request refused
  Scenario: Acting as an investor
    Given I am acting as an investor
    When I request the columns panel for my firm's "Investor" form type
    Then the columns request should be refused

  # X3 — Error case: another firm's report can't be changed
  Scenario: Another firm's report
    Given another firm has a report "Other LPs" on "/investors" with columns "investor_name, city"
    When I save columns "category" for the other firm's report directly
    Then the columns request should be refused
    And the other firm's report columns should still be "investor_name, city"

  # X4 — Error case: a column that is not offered, saved or shown is refused (keys run as method chains)
  Scenario: Forged column refused
    When I save the "Investor" columns "entity.users" directly
    Then the columns save should be refused with "entity.users cannot be added"
    And my firm's "Investor" columns should be "investor_name, category"

  # X5 — Error case: an altered or expired record of what the table showed is refused
  Scenario: Altered or expired panel record
    When I request the columns panel with an altered record
    Then the columns request should be refused
    When I save the "Investor" columns "city" with a record from 13 hours ago
    Then the columns request should be refused
    And my firm's "Investor" columns should be "investor_name, category"

  # X7 — Error case: another user's draft report can't be changed
  Scenario: Report the user may not edit
    Given another user of my firm has a draft report "Draft LPs" on "/investors" with columns "investor_name, city"
    When I save columns "category" for the draft report directly
    Then the columns request should be refused
    And the draft report's columns should still be "investor_name, city"

  # X8 — Error case: fields the panel never sends are ignored
  Scenario: Extra fields ignored
    When I save the "Investor" columns "investor_name, city" directly with extra fields
    Then my firm's "Investor" columns should be "investor_name, city", all my firm's, with their own data types

  # X9 — Error case: a record type without standard columns is not found
  Scenario: Unknown record type
    When I request the columns panel for a record type without standard columns
    Then the columns request should be refused

  # X19 — Error case: a data type that is not offered is refused
  Scenario: Invalid data type
    When I save the "Investor" column "city" with data type "Ruby" directly
    Then the columns save should be refused with "Ruby is not a data type"
    And my firm's "Investor" columns should be "investor_name, category"

  # X20 — Error case: another firm's Configure Grids is refused
  Scenario: Another firm's Configure Grids
    Given another firm has an "Investor" form type
    When I open Configure Grids for the other firm's "Investor" form type
    Then the columns request should be refused
