Feature: Fund tracking currency is locked to support after creation
  Tracking currency can corrupt tracking amounts across account entries if changed
  carelessly after a fund has committed activity, so only support may correct it once
  a fund exists. See FundPolicy#update_tracking_currency?.

  Background:
    Given Im logged in as a user "first_name=Test" for an entity "name=Test Entity;entity_type=Investment Fund;currency=USD"
    Given the user has role "company_admin"
    Given there is a fund "name=Test Fund;currency=USD" for the entity

  Scenario: A regular company admin sees the tracking currency field disabled on edit
    When I visit the edit page for the fund
    Then the tracking currency field should be disabled

  Scenario: A regular company admin cannot change tracking currency via a direct update
    When I try to update the fund's tracking currency to "USD" bypassing the disabled field
    Then the tracking currency update should be denied
    And the fund's tracking currency should still be blank

  Scenario: A support user can change tracking currency after creation
    Given the user has role "support"
    When I visit the edit page for the fund
    Then the tracking currency field should not be disabled
    When I try to update the fund's tracking currency to "USD" bypassing the disabled field
    Then the fund's tracking currency should be "USD"
