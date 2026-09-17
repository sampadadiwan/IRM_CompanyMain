Feature: Ransack filter date locale handling
  The generic search filter used across the app's index pages (_filter.html.erb /
  _condition_fields.html.erb) swaps a date/datetime attribute's value field to a
  locale-aware date picker instead of a bare text field. Previously the raw typed
  text was parsed server-side by Ruby's locale-blind Date.parse, which silently
  dropped the whole filter condition whenever the typed date didn't happen to fit
  that heuristic's day-first guess (e.g. a user typing a date in their browser's
  own mm/dd/yyyy convention with a day > 12).

  Background:
    Given Im logged in as a user "" for an entity "name=TestFund;entity_type=Investment Fund;enable_funds=true"
    Given the user has role "company_admin"
    Given there is an existing fund "name=FilterFund"
    Given there is an existing investor "investor_name=Investor A"
    Given there is an existing capital commitment for "FilterFund" and "Investor A" with committed amount "100000" and commitment date "2020-07-22"
    Given there is an existing capital commitment for "FilterFund" and "Investor A" with committed amount "200000" and commitment date "2020-01-05"

  @javascript
  Scenario: Selecting a date attribute swaps the value field to a locale-date widget
    When I visit the capital commitments index with filter open
    And I select "Commitment date" as the filter attribute
    Then the filter value field should be the locale-date widget

  @javascript
  Scenario: Filtering by a date typed in the current locale's format returns the right row
    When I visit the capital commitments index with filter open
    And I select "Commitment date" as the filter attribute
    And I fill in the filter date with "22/07/2020"
    And I submit the filter
    Then I should see "1" capital commitment in the results
    And the result should contain committed amount "100,000"
    And the result should not contain committed amount "200,000"

  @javascript
  Scenario: Filtering by a date typed in the browser's own mm/dd/yyyy format returns the right row
    Given my browser sends an Accept-Language header of "en-US"
    When I visit the capital commitments index with filter open
    And I select "Commitment date" as the filter attribute
    And I fill in the filter date with "07/22/2020"
    And I submit the filter
    Then I should see "1" capital commitment in the results
    And the result should contain committed amount "100,000"
    And the result should not contain committed amount "200,000"
