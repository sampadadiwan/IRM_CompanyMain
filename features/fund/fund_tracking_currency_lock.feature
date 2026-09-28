Feature: Fund tracking currency is locked on the edit form after creation
  Tracking amounts are stored in the tracking currency but labelled with whatever
  funds.tracking_currency says, so editing the column alone would relabel old-currency figures as
  the new currency. Once a fund exists the edit form's field is locked for everyone - support
  included - and a direct update is refused. The only way to change it is the support-only
  Actions > Change Tracking Currency, which also rebuilds the tracking amounts (see
  change_tracking_currency.feature and FundPolicy#change_tracking_currency?).

  Background:
    Given Im logged in as a user "first_name=Test" for an entity "name=Test Entity;entity_type=Investment Fund;currency=USD"
    Given the user has role "company_admin"
    Given there is a fund "name=Test Fund;currency=USD" for the entity

  Scenario: A regular company admin sees the tracking currency field disabled on edit
    When I visit the edit page for the fund
    Then the tracking currency field should be disabled

  Scenario: A regular company admin cannot change tracking currency via a direct update
    When I try to update the fund's tracking currency to "USD" bypassing the disabled field
    Then the tracking currency update should be refused
    And the fund's tracking currency should still be blank

  Scenario: A regular company admin cannot open the Change Tracking Currency screen
    When I visit the change tracking currency page for the fund
    Then the tracking currency update should be denied

  Scenario: Support also cannot change tracking currency from the edit form
    Given the user has role "support"
    When I visit the edit page for the fund
    Then the tracking currency field should be disabled
    When I try to update the fund's tracking currency to "USD" bypassing the disabled field
    Then the tracking currency update should be refused
    And the fund's tracking currency should still be blank
