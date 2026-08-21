Feature: Duplicate sell portfolio investment detection
  A sell PI with the same date, quantity, and amount as an existing sell must not
  silently get a wrong realized gain (see AttributionService's per-buy row locking,
  which closes the race two such sells could otherwise hit). The user must be warned
  and asked for a distinct Ref ID before the duplicate can be saved.

  Background:
    Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    Given there is an investment instrument for the portfolio company "name=Stock;category=Unlisted;sub_category=Equity;sector=Tech"
    Given there is a fund "name=Test fund" for the entity
    Given there are "1" portfolio investments "quantity=1000;investment_date=01/01/2022"

  Scenario: Second sell with the same date, quantity and amount is blocked until a distinct Ref ID is given
    Given I go to API show page
    Given I click on "New Investment"
    And I fill in the new investment form with amount "1000" quantity "-100" on "2022-02-01"
    Given I click on "Save"
    Then I should see the "Portfolio investment was successfully created"

    Given I go to API show page
    Given I click on "New Investment"
    And I fill in the new investment form with amount "1000" quantity "-100" on "2022-02-01"
    Given I click on "Save"
    Then I should see the duplicate investment confirmation with used ref ids "0"
    When I confirm the duplicate with ref id "1"
    Then I should see the "Portfolio investment was successfully created"
    And there should be "2" sell portfolio investments with quantity "-100"
    And the most recently created sell should have ref_id "1"
    And each sell should have the correct realized gain and the buy lot should not be over-allocated

  Scenario: Re-attempting the same Ref ID as an existing duplicate is still rejected
    Given I go to API show page
    Given I click on "New Investment"
    And I fill in the new investment form with amount "1000" quantity "-100" on "2022-02-01"
    Given I click on "Save"
    Then I should see the "Portfolio investment was successfully created"

    Given I go to API show page
    Given I click on "New Investment"
    And I fill in the new investment form with amount "1000" quantity "-100" on "2022-02-01"
    Given I click on "Save"
    Then I should see the duplicate investment confirmation with used ref ids "0"
    When I confirm the duplicate with ref id "0"
    Then I should see the duplicate ref id error

  Scenario: A sell with a different date, quantity or amount does not trigger the duplicate confirmation
    Given I go to API show page
    Given I click on "New Investment"
    And I fill in the new investment form with amount "500" quantity "-50" on "2022-03-01"
    Given I click on "Save"
    Then I should see the "Portfolio investment was successfully created"
    Then I should not see the duplicate investment confirmation
