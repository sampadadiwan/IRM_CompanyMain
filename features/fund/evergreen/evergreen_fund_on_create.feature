Feature: Choose closed-ended or open-ended when creating a fund
  Worked examples H1–H5, E1–E6, X1–X5 — openspec/changes/evergreen-fund-on-create/design.md#worked-examples

  Background:
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has "enable_units" permission

  # H1 — Happy path: New Fund › Open-ended › "Alpha Long-Short Fund" with unit types "A, B" › preset Indian Cat III › Class A and B at ₹10,000 › Create fund creates the fund and its terms together.
  Scenario: Create an open-ended fund in one flow
    Given the entity has evergreen funds switched on
    When I start a new fund
    And I choose fund type "Open-ended"
    And I fill the fund details "Alpha Long-Short Fund" with unit types "A, B"
    And I go to step 2 of the fund
    And I continue to the evergreen steps
    And I pick the preset "cat_iii_aif"
    And I set the initial price of class "A" to "10000"
    And I set the initial price of class "B" to "10000"
    And I create the fund
    Then I should see "Alpha Long-Short Fund created as an open-ended fund"
    And the fund "Alpha Long-Short Fund" should be open-ended with classes "A,B" priced "10000"

  # H2 — Happy path: New Fund › Closed-ended › Save creates a closed-ended fund exactly as before.
  @rack_test
  Scenario: Create a closed-ended fund
    Given the entity has evergreen funds switched on
    When I start a new fund
    And I choose fund type "Closed-ended"
    And I fill the fund details "Beta Growth Fund" with unit types "A"
    And I go to step 2 of the fund
    And I save the closed-ended fund
    Then the fund "Beta Growth Fund" should be closed-ended

  # H3 — Happy path: on step 2 of New Fund, Back returns to the fund details with what was typed kept.
  @rack_test
  Scenario: Back returns to the fund details
    When I start a new fund
    And I fill the fund details "Gamma Fund" with unit types "A"
    And I go to step 2 of the fund
    And I go back to the fund details
    Then the "fund_name" field should contain "Gamma Fund"

  # H5 — Happy path: New Fund opens on the type page — Closed-ended and Open-ended cards, Continue disabled until one is picked; picking Open-ended and Continue opens the fund details showing "Open-ended", and Back returns to the type page with Open-ended still picked.
  Scenario: New Fund starts by choosing the fund type
    Given the entity has evergreen funds switched on
    When I start a new fund
    Then I should see the fund type page with both types and Continue disabled
    When I choose fund type "Open-ended"
    Then the fund details should show the type "Open-ended"
    When I go back to the fund type page
    Then the "Open-ended" card should be selected

  # E1 — Edge case: a company without evergreen funds sees no fund type choice, and a request asking for open-ended still creates a closed-ended fund.
  @rack_test
  Scenario: A company without evergreen gets closed-ended funds only
    When I start a new fund
    Then the fund type choice should not be offered
    When a request creates the fund "Delta Fund" with unit types "A" and fund type "open_ended"
    Then the fund "Delta Fund" should be closed-ended

  # E2 — Edge case: the class cards follow the unit types — "A, B" gives two cards; going back and changing it to "A" leaves one.
  Scenario: Class cards follow the unit types
    Given the entity has evergreen funds switched on
    When I start a new fund
    And I choose fund type "Open-ended"
    And I fill the fund details "Alpha Long-Short Fund" with unit types "A, B"
    And I go to step 2 of the fund
    And I continue to the evergreen steps
    Then the classes step should show the classes "A,B"
    When I go back to the fund details
    And I change the unit types to "A"
    And I go to step 2 of the fund
    And I continue to the evergreen steps
    Then the classes step should show the classes "A"

  # E3 — Edge case: unit types " A, B, A " (spaces and a repeat) give two cards, A and B.
  Scenario: Spaced and repeated unit types give one card each
    Given the entity has evergreen funds switched on
    When I start a new fund
    And I choose fund type "Open-ended"
    And I fill the fund details "Alpha Long-Short Fund" with unit types " A, B, A "
    And I go to step 2 of the fund
    And I continue to the evergreen steps
    Then the classes step should show the classes "A,B"

  # E4 — Edge case: choosing Open-ended and then Closed-ended before saving creates a closed-ended fund; the evergreen fields are ignored.
  @rack_test
  Scenario: Changing your mind before saving
    Given the entity has evergreen funds switched on
    When I start a new fund
    And I choose fund type "Open-ended"
    And I choose fund type "Closed-ended"
    And I fill the fund details "Epsilon Fund" with unit types "A"
    And I go to step 2 of the fund
    And I save the closed-ended fund
    Then the fund "Epsilon Fund" should be closed-ended

  # E5 — Edge case: the edit form shows the fund type read-only — "Open-ended (evergreen)" for an evergreen fund — and no type page.
  @rack_test
  Scenario: The edit form shows the type read-only
    Given the entity has evergreen funds switched on
    And there is a fund "name=Alpha Long-Short Fund;currency=INR;unit_types=A" for the entity
    And the fund is evergreen
    When I edit the fund
    Then the fund type should read "Open-ended (evergreen)"
    And the fund type choice should not be offered

  # H4 — Happy path: Edit Fund on an open-ended fund carries on into its open-ended terms; adding unit type "B" adds a Class B card, and Save fund saves the fund and its terms together (class A kept, B at ₹12,000).
  Scenario: Editing an open-ended fund adds a class with the fund
    Given the entity has evergreen funds switched on
    And there is a fund "name=Alpha Long-Short Fund;currency=INR;unit_types=A" for the entity
    And the fund is evergreen
    When I edit the fund
    And I change the unit types to "A, B"
    And I go to step 2 of the fund
    And I continue to the evergreen steps
    Then the classes step should show the classes "A,B"
    When I set the initial price of class "B" to "12000"
    And I save the open-ended fund
    Then the fund "Alpha Long-Short Fund" should have classes "A,B" with class "B" priced "12000"

  # E6 — Edge case: Evergreen Settings still edits an open-ended fund's terms (gate 10 %) and has no "Make closed-ended again".
  @rack_test
  Scenario: Evergreen Settings edits terms only
    Given the entity has evergreen funds switched on
    And there is a fund "name=Alpha Long-Short Fund;currency=INR;unit_types=A" for the entity
    And the fund is evergreen
    When I open the evergreen settings of the fund
    And I set the evergreen field "gate_pct" to "10"
    And I save the evergreen settings
    Then I should see "Settings saved"
    And I should not see "Make closed-ended again"

  # X1 — Error case: an open-ended fund needs unit types — with none typed, Next into the open-ended terms goes back to step 1 with "Add at least one unit type for an open-ended fund"; a request that gets past the form is refused with "Add at least one unit class for an open-ended fund" and nothing is saved.
  @rack_test
  Scenario: An open-ended fund needs a unit class
    Given the entity has evergreen funds switched on
    When I start a new fund
    And I choose fund type "Open-ended"
    And I fill the fund details "Alpha Long-Short Fund" with unit types ""
    And I go to step 2 of the fund
    And I try to continue to the evergreen steps
    Then I should see "Add at least one unit type for an open-ended fund"
    And the "fund_name" field should contain "Alpha Long-Short Fund"
    When a request creates the fund "Alpha Long-Short Fund" with unit types "" and fund type "open_ended"
    Then the request should be answered with status 422
    And no fund should have been created

  # X2 — Error case: Class B with no starting price is refused — "Class B needs a starting price" — nothing is saved and the typed values are kept.
  Scenario: Every class needs a starting price
    Given the entity has evergreen funds switched on
    When I start a new fund
    And I choose fund type "Open-ended"
    And I fill the fund details "Alpha Long-Short Fund" with unit types "A, B"
    And I go to step 2 of the fund
    And I continue to the evergreen steps
    And I set the initial price of class "A" to "10000"
    # The Classes step's required check stops Next; the server's "Class B needs a starting price" is the backstop
    And I try to go past the classes step
    Then the starting price of class "B" should be marked required
    And no fund should have been created
    And the "fund_name" field should contain "Alpha Long-Short Fund"

  # X3 — Error case: an open-ended request with no fund name is refused (422) and nothing is saved.
  @rack_test
  Scenario: A missing fund name saves nothing
    Given the entity has evergreen funds switched on
    When a request creates the fund "" with unit types "A" and fund type "open_ended"
    Then the request should be answered with status 422
    And no fund should have been created

  # X4 — Error case: an existing closed-ended fund can't be made evergreen — no menu item, the old POST has no route (404), and its settings address redirects with "A fund's type is chosen when it is created and can't be changed".
  @rack_test
  Scenario: A closed-ended fund can't be made evergreen
    Given the entity has evergreen funds switched on
    And there is a fund "name=Zeta Fund;currency=INR;unit_types=A" for the entity
    Then the fund actions should not offer "Make this fund evergreen"
    When a request tries to make the fund evergreen through the old settings address
    Then the request should be answered with status 404
    When I open the evergreen settings address of the closed-ended fund
    Then I should see "A fund's type is chosen when it is created and can't be changed"
    And the fund "Zeta Fund" should be closed-ended

  # X5 — Error case: an evergreen fund can't be switched back — no "Make closed-ended again", and the old DELETE has no route (404); the fund stays open-ended.
  @rack_test
  Scenario: An open-ended fund can't be switched back
    Given the entity has evergreen funds switched on
    And there is a fund "name=Alpha Long-Short Fund;currency=INR;unit_types=A" for the entity
    And the fund is evergreen
    When I open the evergreen settings of the fund
    Then I should not see "Make closed-ended again"
    When a request tries to switch the fund back through the old settings address
    Then the request should be answered with status 404
    And the fund should still be open-ended
