Feature: Fund records stay in their firm, decided by the policy
  A fund record (call, remittance, distribution, commitment, …) may only be created on, or moved to, a
  fund of a firm the user acts for. The policy checks the record's fund as well as the record's own
  entity_id, which comes from the request. The pattern starts with capital calls.

  Background:
    Given Im logged in as a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is a fund "name=Artha Select" for the entity
    And there is another tenant "Zeta Capital" with a fund "Zeta Fund"

  # X1 — Error case: a company admin names another firm's fund (with their own firm's entity_id)
  @security @rack_test
  Scenario: X1 A capital call on another firm's fund is refused
    When I create a capital call "Zeta Q1" on the fund "Zeta Fund"
    Then I am denied access
    And the fund "Zeta Fund" has no capital call "Zeta Q1"

  # H1 — Happy path: the same request on my own fund still works
  @security @rack_test
  Scenario: H1 A capital call on my own fund is created
    Given the fund "Artha Select" has a commitment
    When I create a capital call "Artha Q1" on the fund "Artha Select"
    Then the fund "Artha Select" has a capital call "Artha Q1"

  # X33 — Error case: editing a call cannot move it to another firm's fund (fund_id is read-only, so the
  # change is left out of the save and the call stays where it is)
  @security @rack_test
  Scenario: X33 A capital call cannot be moved to another firm's fund
    Given there is a capital call "Artha Q2" on the fund "Artha Select"
    When I move the capital call "Artha Q2" to the fund "Zeta Fund"
    Then the capital call "Artha Q2" is on the fund "Artha Select"

  # E34 — Edge case: an ordinary edit of my own call still saves
  @security @rack_test
  Scenario: E34 Editing my own capital call still works
    Given there is a capital call "Artha Q3" on the fund "Artha Select"
    When I rename the capital call "Artha Q3" to "Artha Q3 revised"
    Then the fund "Artha Select" has a capital call "Artha Q3 revised"
