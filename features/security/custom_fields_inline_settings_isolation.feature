# Worked examples X10–X12, X16–X18 — openspec/changes/grid-columns-inline-settings/business-rules.md#3-custom-fields-on-record-pages--phase-4
@rack_test @security
Feature: Custom fields in place — access
  Only a company admin of the firm, not acting as an investor, may open or save a record type's custom fields from a
  record's page. Direct requests are refused the same way; a save changes nothing but the panel's field settings.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And there is an investor named "Ravi Menon"
    And my firm's "Investor" form type has the fields:
      | name        | label       | type        | flags | meta            |
      | risk_rating | Risk rating | Select      |       | Low,Medium,High |
      | net_worth   | Net worth   | Calculation |       | 1 + 1           |
    And the investor "Ravi Menon" is on my firm's "Investor" form type

  # X10 — Error case: an employee who is not a company admin gets no icon; direct requests are refused
  Scenario: Plain employee refused
    Given I am signed in as a plain employee of my firm
    When I open the page of the investor "Ravi Menon"
    Then there should be no custom fields icon
    When I request the custom fields panel for the investor "Ravi Menon"
    Then the fields request should be refused
    When I save the fields "[{\"label\":\"Planted\",\"field_type\":\"TextField\"}]" directly for the investor "Ravi Menon"
    Then the fields request should be refused
    And my firm's "Investor" fields should be "risk_rating, net_worth"

  # X11 — Error case: acting as an investor — refused
  Scenario: Acting as an investor
    Given I am acting as an investor
    When I request the custom fields panel for the investor "Ravi Menon"
    Then the fields request should be refused

  # X12 — Error case: another firm's record — refused; its form type unchanged
  Scenario: Another firm's record
    Given another firm has an investor "Other LP"
    When I request the custom fields panel for the other firm's investor
    Then the fields request should be refused
    When I save a new field directly for the other firm's investor
    Then the fields request should be refused
    And the other firm's form type should be unchanged

  # X16 — Error case: a forged save renaming and removing a calculation field changes nothing for a non-support user
  Scenario: Calculation guarded
    When I save the fields "[{\"id\":{id:net_worth},\"label\":\"Hacked\"},{\"id\":{id:net_worth},\"_destroy\":true}]" directly for the investor "Ravi Menon"
    Then the field "net_worth" should be unchanged with label "Net worth"
    And my firm's "Investor" fields should be "risk_rating, net_worth"

  # X17 — Error case: fields the panel never sends are ignored
  Scenario: Extra fields ignored
    When I save the fields of the investor "Ravi Menon" directly with extra fields
    Then only the label of "risk_rating" should have changed, to "Risk"

  # X18 — Error case: a record type without custom fields is not found
  Scenario: Unknown record type
    When I request the custom fields panel for the record type "Kernel"
    Then the fields request should be refused
