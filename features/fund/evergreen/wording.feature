Feature: Evergreen wording — US terms, entity wording and a fund's unit name
  Worked examples E212, E213, E214, E215 — openspec/changes/open-ended-funds/design.md#worked-examples

  Background:
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has evergreen funds switched on
    And today is "2026-09-01"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "P Family Trust" is an investor of the fund with a portal user
    And "P Family Trust" holds "4892.3679" units of class "A" in folio "F-101" issued "2026-11-02" at "10,220"
    And an approved NAV for class "A" on "2026-11-30" with NAV per unit "10,160.94" and units "99892.3679"
    And today is "2026-12-01"

  # E212 — Edge case: a US browser (en-US) sees US terms — the folio is an "Account" and the dealing tab is the "Calendar".
  @rack_test
  Scenario: US wording for an en-US browser
    Given the browser asks for the locale "en-US"
    When I open folio "F-101"
    Then I should see "Account: F-101"
    When I open the fund page
    Then the evergreen tab "Calendar" should be shown

  # E213 — Edge case: a fund set to Shares says shares on the investor's page — "NAV / share" — while the entity keeps Units.
  @rack_test
  Scenario: A fund that issues shares
    Given the fund's investors hold "share"
    When "P Family Trust" logs in to the portal
    And I open the fund as an investor
    Then I should see "NAV / share"
    And I should not see "NAV / unit"

  # E214 — Edge case: with no fund or entity choice, the unit word is the default "unit".
  @rack_test
  Scenario: Units by default
    When "P Family Trust" logs in to the portal
    And I open the fund as an investor
    Then I should see "NAV / unit"

  # E215 — Edge case: the entity's own wording ("Account" for the folio, shares for units) applies to every fund that has not chosen its own unit name.
  @rack_test
  Scenario: The entity's wording applies to its funds
    Given the entity's open-ended fund wording is "unit=share;capital_commitment=Account"
    When I open folio "F-101"
    Then I should see "Account: F-101"
    When "P Family Trust" logs in to the portal
    And I open the fund as an investor
    Then I should see "NAV / share"
