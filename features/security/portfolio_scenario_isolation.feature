Feature: Portfolio scenario isolation - 2026-10 security review (H8)
  The "Summary Scenario" what-if computes a fund's IRR and every portfolio company's IRR. It was not
  authorized at all, so anyone signed in could read any fund's IRRs by its id. It is now for the
  fund's staff with update rights - the same users who see the Portfolio tab's Scenarios button.
  Design and worked examples: docs/security/security_review_2026_10.md
  (card "H8 — portfolio_scenarios#simple_scenario").

  Background:
    Given Im logged in as a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is a fund "name=Artha Select" for the entity

  # H8-1 — Edge case: another firm's fund is refused and none of its IRRs are shown
  @security @rack_test
  Scenario: H8-1 Opening the summary scenario of another firm's fund is refused
    Given there is another tenant "Zeta Capital" with a fund "Zeta Fund"
    When I open the summary scenario of the fund "Zeta Fund"
    Then I am denied access
    And no scenario IRR is shown

  # H8-2 — Edge case: an LP of the fund, who can see the fund, cannot run its what-if
  @security @rack_test
  Scenario: H8-2 An LP of the fund opening its summary scenario is refused
    Given there is an LP user of my fund with access to the fund
    When the LP user opens the summary scenario of the fund "Artha Select"
    Then I am denied access
    And no scenario IRR is shown

  # H8-3 — Edge case: a read-only employee of the fund cannot run its what-if
  @security @rack_test
  Scenario: H8-3 A read-only employee opening the fund's summary scenario is refused
    Given there is an employee of my firm with read-only access to the fund "Artha Select"
    When the read-only employee opens the summary scenario of the fund "Artha Select"
    Then I am denied access
    And no scenario IRR is shown

  # H8-H — Happy path: the fund's company admin opens Portfolio, Scenarios, Summary Scenario
  @security @rack_test
  Scenario: H8-H The fund's company admin opens the summary scenario
    When I open the summary scenario of the fund "Artha Select"
    Then the summary scenario with its IRRs is shown
